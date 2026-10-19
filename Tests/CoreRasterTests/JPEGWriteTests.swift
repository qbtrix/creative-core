// JPEGWriteTests.swift: JPEG.write checked against ITU-T T.81 and JFIF 1.02:
// quality 90 reopens within a mean of 3/255, qualities 1...100 only, SOI then
// the JFIF APP0, a baseline 4:2:0 frame, the Annex K Huffman tables, and the
// K.1 / K.2 quantization tables scaled by quality, luma's on the Y component.
// Written files are parsed with JPEGFixtures.split.
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
}
