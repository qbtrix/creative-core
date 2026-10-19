// PNGReadTests.swift: PNG.info, PNG.read and PNGCodec.decodePNG against
// PNGs built byte by byte from the W3C PNG specification (PNGFixtures):
// every colour type and depth, the five filters and the Paeth ties, Adam7,
// tRNS, 16-bit big-endian precision, the sRGB transfer undone, and damaged
// or oversized files refused before decoding.
@testable import CoreRaster
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct PNGReadTests {
    typealias F = PNGFixtures
    /// The 15 colour type and depth pairs the spec allows (11.2.2, table 11.1).
    static let pairs = [(0, 1), (0, 2), (0, 4), (0, 8), (0, 16), (2, 8), (2, 16), (3, 1), (3, 2), (3, 4), (3, 8), (4, 8), (4, 16), (6, 8), (6, 16)]
    static let palette = (0..<256).map { [$0, 255 - $0, ($0 * 7) % 256] }

    /// The reference buffer for `pixels` by the spec's sample rules.
    func expected(_ pixels: [[[Int]]], _ colorType: Int, _ depth: Int, alpha: [Int] = [], key: [Int]? = nil) throws -> PixelBuffer {
        try F.linear(pixels.map { $0.map { F.straight($0, colorType: colorType, depth: depth, palette: Self.palette, alpha: alpha, key: key) } })
    }

    func file(_ pixels: [[[Int]]], _ colorType: Int, _ depth: Int, interlaced: Bool = false, extra: [[UInt8]] = []) -> Data {
        let plte = colorType == 3 ? [F.chunk("PLTE", Self.palette.prefix(1 << depth).flatMap { $0.map(UInt8.init) })] : []
        return F.png(pixels, depth: depth, colorType: colorType, interlaced: interlaced, extra: plte + extra)
    }

    @Test func infoReadsIHDR() throws {
        let info = try PNG.info(file(F.ramp(5, 3, channels: 4, depth: 16), 6, 16, interlaced: true))
        #expect(info == PNGInfo(width: 5, height: 3, bitDepth: 16, colorType: 6, interlaced: true))
        #expect(try PNG.info(file(F.ramp(30_000, 1, channels: 1, depth: 1), 0, 1)).width == PNG.maxSide)
    }

    @Test func everyColorTypeAndDepth() throws {
        for (colorType, depth) in Self.pairs {
            // Width 5 leaves pad bits at the end of each 1-, 2- and 4-bit row.
            let pixels = F.ramp(5, 3, channels: F.channels(colorType), depth: depth)
            let read = try PNG.read(file(pixels, colorType, depth))
            #expect(try F.maxDifference(read, expected(pixels, colorType, depth)) <= 1e-6, "type \(colorType) depth \(depth)")
        }
    }

    @Test func everyFilterUndone() throws {
        let pixels = F.ramp(6, 5, channels: 3, depth: 8)
        for filter in 0...4 {
            let data = F.png(pixels, depth: 8, colorType: 2, filter: { ($0 + filter) % 5 })
            #expect(try F.maxDifference(PNG.read(data), expected(pixels, 2, 8)) <= 1e-6, "filters from \(filter)")
        }
    }

    /// Paeth (9.4) prefers a, then b, then c on ties. Pixel (1, 1) has a 30, b 60, c 50: pa = pc = 10 < pb, so a.
    /// Pixel (3, 1) has a 60, b 30, c 50: pb = pc = 10 < pa, so b. Strict comparisons pick c for both.
    @Test func paethTies() throws {
        let pixels = [[50, 60, 50, 30], [30, 100, 60, 90]].map { $0.map { [$0] } }
        #expect(F.paeth(30, 60, 50) == 30 && F.paeth(60, 30, 50) == 30)
        let read = try PNG.read(F.png(pixels, depth: 8, colorType: 0, filter: { $0 == 1 ? 4 : 0 }))
        #expect(try F.maxDifference(read, expected(pixels, 0, 8)) <= 1e-6)
    }

    @Test func adam7() throws {
        // 9 x 9 fills every pass and starts a second block; 5 x 3 leaves pass 3 empty (no scanlines, 8.2); pass 2 holds pixel (4, 0).
        for (width, height, colorType, depth) in [(9, 9, 6, 8), (5, 3, 0, 1), (8, 8, 2, 16)] {
            let pixels = F.ramp(width, height, channels: F.channels(colorType), depth: depth)
            let interlaced = try PNG.read(file(pixels, colorType, depth, interlaced: true))
            #expect(try interlaced == PNG.read(file(pixels, colorType, depth)))
            #expect(try F.maxDifference(interlaced, expected(pixels, colorType, depth)) <= 1e-6, "\(width)x\(height)")
        }
    }

    @Test func paletteTRNSAlpha() throws {
        let pixels = [[0, 1, 2, 3]].map { $0.map { [$0] } }, alpha = [0, 128, 255]
        let read = try PNG.read(file(pixels, 3, 2, extra: [F.chunk("tRNS", alpha.map(UInt8.init))]))
        #expect(try F.maxDifference(read, expected(pixels, 3, 2, alpha: alpha)) <= 1e-6)
        #expect(try read.pixel(x: 0, y: 0) == .clear && read.pixel(x: 3, y: 0).a == 1)
        // A tRNS key colour (11.3.2.1) makes matching grey or RGB pixels transparent; 16-bit keys are two bytes.
        let grey = [[[3], [7]]], rgb = [[[1000, 2, 3], [1000, 2, 4]]]
        let greyRead = try PNG.read(file(grey, 0, 4, extra: [F.chunk("tRNS", [0, 7])]))
        #expect(try F.maxDifference(greyRead, expected(grey, 0, 4, key: [7])) <= 1e-6)
        let rgbRead = try PNG.read(file(rgb, 2, 16, extra: [F.chunk("tRNS", [0x03, 0xE8, 0, 2, 0, 3])]))
        #expect(try F.maxDifference(rgbRead, expected(rgb, 2, 16, key: [1000, 2, 3])) <= 1e-6)
        #expect(try rgbRead.pixel(x: 0, y: 0) == .clear && rgbRead.pixel(x: 1, y: 0).a == 1)
    }

    /// 16-bit samples are big-endian (7.1) and keep all 16 bits: 0x1234 and 0x1235 differ, 0x12 0x34 is not 0x3412.
    @Test func sixteenBitBigEndian() throws {
        let read = try PNG.read(F.png([[[0x1234], [0x1235], [0x3412]]], depth: 16, colorType: 0))
        let values = try (0..<3).map { try read.pixel(x: $0, y: 0).r }
        for (value, sample) in zip(values, [0x1234, 0x1235, 0x3412]) {
            #expect(abs(Double(value) - TransferCurve.decode(Double(sample) / 65_535)) <= 1e-7)
        }
        #expect(values[1] > values[0])
    }

    /// The sRGB transfer is undone and alpha premultiplied: encoded 128 is linear 0.21586 (IEC 61966-2-1), not 0.50196.
    @Test func linearPixels() throws {
        let read = try PNG.read(F.png([[[128, 128, 128, 255], [255, 128, 0, 128]]], depth: 8, colorType: 6))
        let grey = try read.pixel(x: 0, y: 0), half = try read.pixel(x: 1, y: 0)
        #expect(abs(grey.r - 0.215_861) <= 1e-5 && grey.r == grey.g && grey.g == grey.b && grey.a == 1)
        #expect(abs(half.a - 128 / 255) <= 1e-6 && abs(half.r - 128 / 255) <= 1e-5 && abs(half.g - 0.215_861 * 128 / 255) <= 1e-5 && half.b == 0)
    }

    @Test func ancillaryChunksAndSplitIDAT() throws {
        let pixels = F.ramp(7, 4, channels: 4, depth: 8)
        let gamma = F.chunk("gAMA", F.be32(100_000)), text = F.chunk("tEXt", Array("Comment\u{0}hi".utf8))
        let read = try PNG.read(F.png(pixels, depth: 8, colorType: 6, extra: [gamma, text], idats: 3))
        #expect(try F.maxDifference(read, expected(pixels, 6, 8)) <= 1e-6)
        #expect(try PNGCodec().decodePNG(file(pixels, 6, 8)) == read)
    }

    @Test func damagedFilesThrow() throws {
        let good = [UInt8](F.png([[[1], [2]], [[3], [4]]], depth: 8, colorType: 0))
        let head = Array(good.prefix(8 + 25)), end = F.chunk("IEND", [])
        var badCRC = good, badIDATCRC = good
        badCRC[32] ^= 0x01  // the last byte of IHDR's CRC (signature 8, then length, type, 13 bytes, CRC)
        badIDATCRC[good.count - 13] ^= 0x01  // the last byte of IDAT's CRC, before IEND's 12 bytes
        let cases: [(String, [UInt8])] = [
            ("IHDR CRC", badCRC), ("IDAT CRC", badIDATCRC), ("truncated", Array(good.prefix(good.count - 30))),
            ("no IHDR", F.signature + F.chunk("IDAT", F.stored([0, 1])) + end),
            ("RGB at depth 4", F.signature + F.chunk("IHDR", F.ihdr(1, 1, depth: 4, colorType: 2)) + end),
            ("palette without PLTE", [UInt8](F.png([[[0]]], depth: 8, colorType: 3))),
            ("filter type 5", head + F.chunk("IDAT", F.stored([5, 1, 2, 0, 3, 4])) + end),
            ("IDAT too short", head + F.chunk("IDAT", F.stored([0, 1, 2, 0])) + end),
        ]
        for (name, bytes) in cases { #expect(F.thrown { try PNG.read(Data(bytes)) } == "damaged", "\(name)") }
        #expect(F.thrown { try PNG.info(Data(good.dropFirst())) } == "notThisFormat")
        #expect(F.thrown { try PNGCodec().decodePNG(Data(badCRC)) } == "pixelCodec")
    }

    /// Sizes come from IHDR and are refused before any pixel buffer or inflate: the IDATs here are far too short,
    /// so `tooLarge` (not `damaged`) shows the check came first. Extra inflated bytes past the size IHDR implies throw.
    @Test func refusesHuge() throws {
        for (width, height) in [(PNG.maxSide + 1, 1), (1, PNG.maxSide + 1), (20_000, 20_000)] {
            let bytes = F.signature + F.chunk("IHDR", F.ihdr(width, height, depth: 8, colorType: 6)) + F.chunk("IDAT", F.stored([0])) + F.chunk("IEND", [])
            #expect(F.thrown { try PNG.read(Data(bytes)) } == "tooLarge", "\(width)x\(height)")
            let overSide = width > PNG.maxSide || height > PNG.maxSide  // info refuses a side; only read refuses the area
            #expect(F.thrown { try PNG.info(Data(bytes)) } == (overSide ? "tooLarge" : "returned"))
        }
        // 2 x 2 grey 8-bit implies 2 x (1 + 2) = 6 filtered bytes; a stream holding 1,006 must not decode.
        let bloated = F.signature + F.chunk("IHDR", F.ihdr(2, 2, depth: 8, colorType: 0))
            + F.chunk("IDAT", F.stored([0, 1, 2, 0, 3, 4] + [UInt8](repeating: 0, count: 1_000))) + F.chunk("IEND", [])
        #expect(throws: CodecError.self) { try PNG.read(Data(bloated)) }
    }
}
