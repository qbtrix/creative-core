// JPEGWriteTests.swift: JPEG.write checked against ITU-T T.81 and JFIF 1.02:
// quality 90 reopens within a mean of 3/255, qualities 1...100 only, SOI then
// the JFIF APP0, a baseline 4:2:0 frame, the Annex K Huffman tables, and the
// K.1 / K.2 quantization tables scaled by quality, luma's on the Y component,
// 0xFF bytes stuffed, ZRL for long zero runs and 1-bit padding (F.1.2), and
// alpha un-premultiplied then dropped. Written files are parsed with
// JPEGFixtures.split.
@testable import CoreRaster
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct JPEGWriteTests {
    typealias F = JPEGFixtures

    /// Opaque seeded gradients: each channel a ramp in its own seeded direction, so 4:2:0 and quantization lose little.
    static func gradient(_ seed: UInt64, _ width: Int, _ height: Int) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        let ramps = (0..<3).map { _ in (Int.random(in: -2...2, using: &rng), Int.random(in: -2...2, using: &rng), Int.random(in: 40...215, using: &rng)) }
        let bytes = (0..<(width * height)).flatMap { (i: Int) -> [UInt8] in
            ramps.map { r in UInt8(clamping: r.2 + r.0 * (i % width - width / 2) + r.1 * (i / width - height / 2)) } + [255]
        }
        return try PixelBuffer(rgba8: bytes, width: width, height: height)
    }

    /// Each component's quantization table (natural order) by the SOF's Tq, read from the DQT segments (B.2.4.1).
    static func tables(_ data: Data) -> [[Int]] {
        let segments = F.split(data).segments
        var byID: [Int: [Int]] = [:]
        for body in segments.filter({ $0.marker == 0xDB }).map(\.body) {
            var at = 0
            while at + 65 <= body.count {
                var natural = [Int](repeating: 0, count: 64)
                for k in 0..<64 { natural[F.zigzag[k]] = Int(body[at + 1 + k]) }
                byID[Int(body[at] & 0x0F)] = natural; at += 65
            }
        }
        guard let sof = segments.first(where: { $0.marker == 0xC0 })?.body, sof.count >= 6 else { return [] }
        return (0..<Int(sof[5])).compactMap { c in sof.count > 8 + 3 * c ? byID[Int(sof[8 + 3 * c])] : nil }
    }

    /// The scaling every quality takes: 5000 / q below 50, else 200 - 2q, then (K * scale + 50) / 100 in 1...255.
    static func scaled(_ table: [Int], _ quality: Int) -> [Int] {
        let scale = quality < 50 ? 5000 / quality : 200 - 2 * quality
        return table.map { min(max(($0 * scale + 50) / 100, 1), 255) }
    }

    @Test func qualityNinetyReopens() throws {
        for (seed, width, height) in [(UInt64(0x81), 37, 29), (0x82, 64, 48)] {
            let source = try Self.gradient(seed, width, height), back = try JPEG.read(JPEG.write(source, quality: 90))
            #expect(back.width == width && back.height == height)
            var total = 0.0
            for i in 0..<(width * height) {
                let p = try source.pixel(x: i % width, y: i / width), q = try back.pixel(x: i % width, y: i / width)
                for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b)] { total += abs(TransferCurve.encode(Double(u)) - TransferCurve.encode(Double(v))) * 255 }
                #expect(q.a == 1)
            }
            #expect(total / Double(3 * width * height) <= 3, "\(width)x\(height): mean \(total / Double(3 * width * height)) levels")
        }
    }

    @Test func qualityRange() throws {
        let source = try Self.gradient(0x83, 17, 9)
        for quality in [1, 100] { #expect(try JPEG.read(JPEG.write(source, quality: quality)).width == 17, "quality \(quality)") }
        for quality in [0, 101, -1, Int.max] {
            #expect(PNGFixtures.thrown { try JPEG.write(source, quality: quality) } == "unsupported", "quality \(quality)")
        }
        #expect(PNGFixtures.thrown { try JPEG.write(PixelBuffer(width: JPEG.maxSide + 1, height: 1), quality: 90) } == "tooLarge")
        #expect(PNGFixtures.thrown { try JPEG.write(PixelBuffer(width: 1, height: JPEG.maxSide + 1), quality: 90) } == "tooLarge")
        do { _ = try JPEG.write(PixelBuffer(width: JPEG.maxSide + 1, height: 1), quality: 90); Issue.record("wrote") } catch {
            guard case CodecError.tooLarge(let text) = error else { Issue.record("\(error)"); return }
            #expect(text.contains("\(JPEG.maxSide)") && text.hasPrefix("JPEG"), "\(text)")
        }
    }

    /// B.2.1 and JFIF 1.02: SOI, then APP0 "JFIF\0"; the frame is baseline SOF0, Y at 2x2 and Cb, Cr at 1x1 (4:2:0).
    @Test func startsWithSOIAndJFIF() throws {
        let data = try JPEG.write(Self.gradient(0x84, 23, 15))
        #expect(Array(data.prefix(4)) == [0xFF, 0xD8, 0xFF, 0xE0] && Array(data.dropFirst(6).prefix(5)) == Array("JFIF".utf8) + [0])
        #expect(Array(data.suffix(2)) == [0xFF, 0xD9])
        let segments = F.split(data).segments
        #expect(!segments.contains { [0xC1, 0xC2, 0xC3].contains($0.marker) })
        let sof: [UInt8] = segments.first(where: { $0.marker == 0xC0 }).map(\.body) ?? []
        #expect(sof.count == 15 && Array(sof.prefix(6)) == [8, 0, 15, 0, 23, 3])
        #expect(sof.count == 15 && [sof[7], sof[10], sof[13]] == [0x22, 0x11, 0x11])
        #expect(try JPEG.info(data) == JPEGInfo(width: 23, height: 15, components: 3, progressive: false, orientation: 1))
    }

    /// The DHT tables (B.2.4.2) are K.3 to K.6: luma DC and AC as table 0, chroma as table 1.
    @Test func annexKHuffmanTables() throws {
        var found: [Int: [Int]] = [:]
        for body in F.split(try JPEG.write(Self.gradient(0x85, 16, 16))).segments.filter({ $0.marker == 0xC4 }).map(\.body) {
            var at = 0
            while at + 17 <= body.count {
                let count = body[(at + 1)..<(at + 17)].reduce(0) { $0 + Int($1) }, end = min(at + 17 + count, body.count)
                found[Int(body[at])] = body[(at + 1)..<end].map(Int.init); at = end
            }
        }
        for (key, table) in [(0x00, F.dcLuma), (0x10, F.acLuma), (0x01, F.dcChroma), (0x11, F.acChroma)] {
            #expect(found[key] == table.bits + table.values, "table class \(key >> 4), id \(key & 15)")
        }
    }

    /// Quality 50 writes K.1 and K.2 as printed, 100 all ones, and the others the scaling above: an inverted
    /// scale writes coarse tables at high quality.
    @Test func qualityScale() throws {
        let source = try Self.gradient(0x86, 16, 16)
        for quality in [1, 10, 25, 50, 75, 90, 100] {
            let t = Self.tables(try JPEG.write(source, quality: quality))
            #expect(t.count == 3 && t.first == Self.scaled(F.lumaQ, quality), "quality \(quality)")
        }
        #expect(Self.tables(try JPEG.write(source, quality: 50)).first == F.lumaQ)
        #expect(Self.tables(try JPEG.write(source, quality: 100)).first == [Int](repeating: 1, count: 64))
    }

    /// The Y component (SOF component 1) names the table holding scaled K.1; Cb and Cr name scaled K.2.
    @Test func lumaTables() throws {
        let source = try Self.gradient(0x87, 16, 16)
        for quality in [30, 90] {
            let t = Self.tables(try JPEG.write(source, quality: quality))
            #expect(t == [Self.scaled(F.lumaQ, quality)] + [[Int]](repeating: Self.scaled(F.chromaQ, quality), count: 2), "quality \(quality)")
        }
    }

    /// The entropy-coded bytes of a written file: the scan after the SOS header, before EOI.
    static func entropy(_ data: Data) -> [UInt8] {
        let scan = F.split(data).scan
        guard scan.count >= 6 else { return [] }
        let start = 2 + (Int(scan[2]) << 8 | Int(scan[3]))
        return start <= scan.count - 2 ? Array(scan[start..<(scan.count - 2)]) : []
    }

    /// F.1.2.3 and F.1.2.2: seeded opaque noise at quality 100 codes 0xFF bytes, each followed by a stuffed
    /// 0x00, and reopens close to the source; a lone (7, 7) coefficient, 62 zeros after the DC, needs ZRL codes
    /// (run 16) before it and reopens as the same pattern.
    @Test func noiseReopensAtHundred() throws {
        var rng = SplitMix64(seed: 0x88)
        let (width, height) = (32, 24)
        let bytes = (0..<(width * height)).flatMap { _ in (0..<3).map { _ in UInt8.random(in: 0...255, using: &rng) } + [255] }
        let source = try PixelBuffer(rgba8: bytes, width: width, height: height)
        let data = try JPEG.write(source, quality: 100), coded = Self.entropy(data)
        #expect(zip(coded, coded.dropFirst()).contains { $0 == (0xFF, 0x00) })
        let back = try JPEG.read(data), out = try back.rgba8()
        #expect(back.width == width && back.height == height && out.count == bytes.count)
        // 4:2:0 halves chroma on noise, so the bound is on luma: within 3 levels per pixel on average.
        var total = 0.0
        for i in stride(from: 0, to: min(out.count, bytes.count), by: 4) {
            let luma = { (b: [UInt8]) in 0.299 * Double(b[i]) + 0.587 * Double(b[i + 1]) + 0.114 * Double(b[i + 2]) }
            total += abs(luma(bytes) - luma(out))
        }
        #expect(total / Double(width * height) <= 3, "mean luma error \(total / Double(width * height))")

        // One MCU: the top left Y block is the (7, 7) basis function alone, the rest flat mid grey.
        let t = JPEGDecoder.cosines, amplitude: Float = 200
        let pattern = (0..<64).map { amplitude * t[($0 % 8) * 8 + 7] * t[($0 / 8) * 8 + 7] }
        var e = JPEGEncoder(quality: 100)
        e.block(pattern, 0)
        for c in [0, 0, 0, 1, 2] { e.block([Float](repeating: 0, count: 64), c) }
        e.bits.flush()
        let image = try JPEG.read(Data(e.header(16, 16) + e.bits.bytes + [0xFF, 0xD9])), grey = try image.rgba8()
        #expect(grey.count == 16 * 16 * 4)
        for k in 0..<64 where grey.count == 16 * 16 * 4 {
            let got = Float(grey[((k / 8) * 16 + k % 8) * 4]), want = 128 + pattern[k]
            #expect(abs(got - want) <= 1.5, "pixel (\(k % 8), \(k / 8)): \(got), want \(want)")
        }
    }

    /// F.1.2.3: a partial last byte is padded with 1-bits; an empty one adds nothing.
    @Test func padsWithOnes() {
        var w = JPEGBitWriter()
        w.put(0b101, 3)
        w.flush()
        #expect(w.bytes == [0xBF])
        w.flush()
        #expect(w.bytes == [0xBF])
    }

    /// Alpha is un-premultiplied, then dropped: half-transparent mid grey reopens as opaque mid grey, and a fully
    /// transparent pixel as black.
    @Test func alphaDropped() throws {
        let (width, height) = (16, 8)
        let bytes = (0..<(width * height)).flatMap { (i: Int) -> [UInt8] in i % width < 8 ? [128, 128, 128, 128] : [200, 50, 90, 0] }
        let out = try JPEG.read(JPEG.write(PixelBuffer(rgba8: bytes, width: width, height: height), quality: 100)).rgba8()
        #expect(out.count == bytes.count)
        for i in 0..<(width * height) where out.count == bytes.count {
            let want: Int = i % width < 8 ? 128 : 0
            for c in 0..<3 { #expect(abs(Int(out[i * 4 + c]) - want) <= 3, "pixel \(i), channel \(c): \(out[i * 4 + c])") }
            #expect(out[i * 4 + 3] == 255)
        }
    }
}
