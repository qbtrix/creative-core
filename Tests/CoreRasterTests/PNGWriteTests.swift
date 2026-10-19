// PNGWriteTests.swift: PNG.write and PNGCodec.encodePNG checked against the
// W3C PNG specification: rereads equal at 8 bits and within one step at 16,
// IHDR depth, big-endian samples, chunk order and CRCs, IDATs of at most
// 64 KiB, the least-sum filter choice (12.8), and an ORA round trip through
// PNGCodec. Written files are parsed with PNGFixtures. Rereads wait on IC-4.
@testable import CoreRaster
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct PNGWriteTests {
    typealias F = PNGFixtures

    /// Seeded pixels an 8-bit file holds exactly: sRGB bytes with alpha 0 (and colour 0), 128 or 255.
    static func bytePixels(_ seed: UInt64, _ width: Int, _ height: Int) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        let bytes = (0..<(width * height)).flatMap { _ -> [UInt8] in
            let alpha = [UInt8(0), 128, 255][Int.random(in: 0...2, using: &rng)]
            return alpha == 0 ? [0, 0, 0, 0] : (0..<3).map { _ in UInt8.random(in: 0...255, using: &rng) } + [alpha]
        }
        return try PixelBuffer(rgba8: bytes, width: width, height: height)
    }

    /// The inflated IDAT stream of a written PNG.
    static func scanlines(_ data: Data) throws -> [UInt8] {
        let idat = F.chunks(data).filter { $0.type == "IDAT" }.flatMap(\.body)
        return [UInt8](try Inflate.zlib(Data(idat), limit: 1 << 24))
    }

    @Test func eightBitRoundTrip() throws {
        let source = try Self.bytePixels(0x5E1, 13, 7)
        for level in [0, 6, 9] { #expect(try PNG.read(PNG.write(source, level: level)) == source, "level \(level)") }
        #expect(try PNGCodec().decodePNG(PNGCodec().encodePNG(source, bitsPerChannel: 8)) == source)
    }

    @Test func sixteenBitWithinOneStep() throws {
        var rng = SplitMix64(seed: 0x5E2), source = try PixelBuffer(width: 11, height: 6)
        for y in 0..<6 {
            for x in 0..<11 {
                let c = (0..<3).map { _ in Float.random(in: 0...1, using: &rng) }
                try source.setPixel(x: x, y: y, RGBA(r: c[0], g: c[1], b: c[2], a: .random(in: 0.25...1, using: &rng)).premultiplied())
            }
        }
        let back = try PNG.read(PNG.write(source, bitsPerChannel: 16))
        for y in 0..<6 {
            for x in 0..<11 {
                let p = try source.pixel(x: x, y: y).unpremultiplied(), q = try back.pixel(x: x, y: y).unpremultiplied()
                let encoded = { (v: Float) in TransferCurve.encode(Double(v)) }
                for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b)] { #expect(abs(encoded(u) - encoded(v)) <= 1.01 / 65_535) }
                #expect(abs(p.a - q.a) <= 0.51 / 65_535)
            }
        }
    }

    /// 7.1: 16-bit samples are written high byte first; encoded 0x1234 is the bytes 0x12 0x34.
    @Test func bigEndian16() throws {
        let v = Float(TransferCurve.decode(Double(0x1234) / 65_535))
        let lines = try Self.scanlines(PNG.write(PixelBuffer(width: 1, height: 1, fill: RGBA(r: v, g: v, b: v, a: 1)), bitsPerChannel: 16))
        #expect(lines.count == 9 && lines[0] <= 4)
        #expect(Array(lines.dropFirst()) == [0x12, 0x34, 0x12, 0x34, 0x12, 0x34, 0xFF, 0xFF])
    }

    @Test func ihdrDepthRecorded() throws {
        let source = try Self.bytePixels(0x5E3, 3, 2)
        for depth in [8, 16] {
            let data = try PNG.write(source, bitsPerChannel: depth), bytes = [UInt8](data)
            #expect(bytes.count > 33 && bytes[24] == depth && bytes[25] == 6 && bytes[28] == 0, "IHDR depth, RGBA, not interlaced")
            #expect(try PNG.info(data) == PNGInfo(width: 3, height: 2, bitDepth: depth, colorType: 6, interlaced: false))
        }
    }

    @Test func chunkCRCsValid() throws {
        let data = try PNG.write(Self.bytePixels(0x5E4, 200, 200), level: 0)
        let chunks = F.chunks(data)
        #expect(Array(data.prefix(8)) == F.signature && chunks.first?.type == "IHDR")
        #expect(chunks.last.map { $0.type == "IEND" && $0.body.isEmpty } == true)
        #expect(chunks.allSatisfy(\.crcOK) && chunks.map { 12 + $0.body.count }.reduce(8, +) == data.count)
        let idats = chunks.filter { $0.type == "IDAT" }
        #expect(idats.count >= 3 && idats.allSatisfy { $0.body.count <= 65_536 }, "160,200 stored bytes split by 64 KiB")
    }

    /// 12.8: each row takes the filter with the least sum of its bytes read as signed. A 16-pixel horizontal
    /// ramp (sRGB 4x + 4, opaque) with equal rows makes None the worst choice on every row.
    @Test func adaptiveFilterSmaller() throws {
        let row: [UInt8] = (0..<16).flatMap { (x: Int) -> [UInt8] in let v = UInt8(4 * x + 4); return [v, v, v, 255] }
        let image = try PixelBuffer(rgba8: row + row + row + row, width: 16, height: 4)
        let lines = try Self.scanlines(PNG.write(image))
        #expect(lines.count == 4 * 65)
        func cost(_ filtered: [UInt8]) -> Int { filtered.dropFirst().reduce(0) { $0 + abs(Int(Int8(bitPattern: $1))) } }
        for y in 0..<4 {
            let written = Array(lines[(y * 65)..<(y * 65 + 65)]), prior = y == 0 ? nil : row
            let costs = (0...4).map { cost(F.filtered(row, prior: prior, filter: $0, bpp: 4)) }
            #expect(written[0] != 0 && written[0] <= 4, "row \(y)")
            #expect(written == F.filtered(row, prior: prior, filter: Int(min(written[0], 4)), bpp: 4) && cost(written) == costs.min())
            // Row 0 ties Sub with Paeth, later rows tie Up with Paeth: the lower type wins.
            #expect(Int(written[0]) == costs.indices.first { costs[$0] == costs.min() }, "row \(y)")
        }
    }

    @Test func levelOutsideRangeActsAsNearestEnd() throws {
        let source = try Self.bytePixels(0x5EB, 9, 5)
        #expect(try PNG.write(source, level: 12) == PNG.write(source, level: 9))
        #expect(try PNG.write(source, level: -1) == PNG.write(source, level: 0))
        #expect(try PNG.write(source, level: 0) != PNG.write(source, level: 9))
    }

    /// `PNGCodec` writes at its own level: level 0 stores, so it matches `PNG.write` at 0 and not at 9.
    @Test func codecWritesAtItsLevel() throws {
        let source = try Self.bytePixels(0x5EC, 9, 5)
        let stored = try PNGCodec(level: 0).encodePNG(source, bitsPerChannel: 8)
        #expect(try stored == PNG.write(source, level: 0))
        #expect(try stored != PNG.write(source, level: 9))
        #expect(try PNGCodec(level: 9).encodePNG(source, bitsPerChannel: 8) == PNG.write(source, level: 9))
    }

    /// Write failures through `PNGCodec` read as plain text that says it was writing.
    @Test func codecWriteTextIsPlain() throws {
        do {
            _ = try PNGCodec().encodePNG(Self.bytePixels(0x5ED, 2, 2), bitsPerChannel: 12)
            Issue.record("12-bit write returned")
        } catch CodecError.pixelCodec(let text) {
            #expect(text == "PNG write: unsupported: 12-bit samples: only 8 or 16")
        }
    }

    @Test func oraRoundTripThroughPNGCodec() throws {
        let layers = try (0..<3).map { PixelLayer(name: "layer \($0)", pixels: try Self.bytePixels(0x5E5 + UInt64($0), 5 + $0, 4), x: $0, y: -$0) }
        let image = LayeredImage(width: 9, height: 6, nodes: layers.map { .pixels($0) }, composite: try Self.bytePixels(0x5E9, 9, 6))
        #expect(try OpenRaster.read(OpenRaster.write(image, pixels: PNGCodec()), pixels: PNGCodec()) == image)
    }

    @Test func otherDepthsRefused() throws {
        let source = try Self.bytePixels(0x5EA, 2, 2)
        #expect(F.thrown { try PNG.write(source, bitsPerChannel: 12) } == "unsupported")
        #expect(F.thrown { try PNGCodec().encodePNG(source, bitsPerChannel: 12) } == "pixelCodec")
        #expect(F.thrown { try PNG.write(PixelBuffer(width: PNG.maxSide + 1, height: 1)) } == "tooLarge")
    }
}
