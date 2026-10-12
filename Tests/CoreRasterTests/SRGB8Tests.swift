// SRGB8Tests.swift: PixelBuffer to and from 8-bit sRGB RGBA bytes. Every byte
// level survives import then export exactly, the curve's ends and known mid
// values, clamping of out-of-range values, partial and zero alpha, size checks,
// and a seeded fuzz of import sizes and bytes.
import CoreRaster
import Testing

@Test func everyOpaqueLevelRoundTripsExactly() throws {
    let levels = (0...255).map { UInt8($0) }
    // Each level in R, reversed in G, a fixed 128 in B, opaque.
    let bytes = levels.flatMap { level -> [UInt8] in [level, 255 - level, 128, 255] }
    let buffer = try PixelBuffer(width: 256, height: 1, sRGB8Bytes: bytes)
    #expect(try buffer.sRGB8Bytes() == bytes)
}

@Test func curveEndsAndMidpointsMatchTheSRGBStandard() throws {
    let buffer = try PixelBuffer(width: 3, height: 1, sRGB8Bytes: [0, 255, 188, 255, 0, 0, 0, 255, 255, 255, 255, 255])
    #expect(try buffer.pixel(x: 0, y: 0).r == 0)
    #expect(try buffer.pixel(x: 0, y: 0).g == 1)
    // sRGB 188/255 is linear 0.5029 (IEC 61966-2-1).
    #expect(abs(try buffer.pixel(x: 0, y: 0).b - 0.5029) < 1e-4)
    #expect(try buffer.pixel(x: 1, y: 0) == RGBA(r: 0, g: 0, b: 0, a: 1))
    #expect(try buffer.pixel(x: 2, y: 0) == RGBA(r: 1, g: 1, b: 1, a: 1))
    // Linear 0.5 encodes to sRGB 0.7354, byte 188.
    let half = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.5, g: 0, b: 1, a: 1))
    #expect(try half.sRGB8Bytes() == [188, 0, 255, 255])
}

@Test func outOfRangeValuesClamp() throws {
    var buffer = try PixelBuffer(width: 2, height: 1)
    try buffer.setPixel(x: 0, y: 0, RGBA(r: -0.5, g: 1.5, b: 40, a: 1))
    // Alpha above 1 clamps to 255; straight 0.25 encodes to byte 137.
    try buffer.setPixel(x: 1, y: 0, RGBA(r: 2, g: 0, b: 0.5, a: 2))
    #expect(try buffer.sRGB8Bytes() == [0, 255, 255, 255, 255, 0, 137, 255])
    let negative = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 1, g: 1, b: 1, a: -0.5))
    #expect(try negative.sRGB8Bytes() == [0, 0, 0, 0])
    // A tiny alpha makes the straight color overflow Float; it clamps instead of throwing.
    let tiny = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 1, g: 0, b: 0, a: 0.01))
    #expect(try tiny.sRGB8Bytes() == [255, 0, 0, 3])
    let subnormal = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 1, g: 0, b: 0, a: 1e-40))
    #expect(try subnormal.sRGB8Bytes() == [0, 0, 0, 0])
}

@Test func partialAlphaIsStraightInBytesAndPremultipliedInTheBuffer() throws {
    // sRGB 255 and 188 at alpha 51/255 = 0.2.
    let bytes: [UInt8] = [255, 188, 0, 51]
    let buffer = try PixelBuffer(width: 1, height: 1, sRGB8Bytes: bytes)
    let p = try buffer.pixel(x: 0, y: 0)
    #expect(abs(p.r - 0.2) < 1e-6)
    #expect(abs(p.g - 0.2 * 0.5029) < 1e-4)
    #expect(p.b == 0)
    #expect(abs(p.a - 0.2) < 1e-6)
    #expect(try buffer.sRGB8Bytes() == bytes)
    // Every level at every alpha above zero exports its color unchanged
    // when it came from bytes, for a sample of alphas.
    for alpha: UInt8 in [1, 64, 128, 254] {
        let row = (0...255).flatMap { level -> [UInt8] in [UInt8(level), UInt8(level), UInt8(level), alpha] }
        let back = try PixelBuffer(width: 256, height: 1, sRGB8Bytes: row).sRGB8Bytes()
        let diffs = zip(back, row).map { abs(Int($0) - Int($1)) }
        // Low alpha loses Float precision in the premultiplied color, never more than one level.
        #expect(diffs.allSatisfy { $0 <= (alpha < 64 ? 1 : 0) }, "alpha \(alpha)")
    }
}

@Test func zeroAlphaExportsZeroedColor() throws {
    let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.7, g: 0.3, b: 0.1, a: 0))
    #expect(try buffer.sRGB8Bytes() == [0, 0, 0, 0])
    // Imported color under alpha 0 is lost on purpose: there is nothing to show.
    let imported = try PixelBuffer(width: 1, height: 1, sRGB8Bytes: [200, 100, 50, 0])
    #expect(try imported.pixel(x: 0, y: 0) == .clear)
    #expect(try imported.sRGB8Bytes() == [0, 0, 0, 0])
}

@Test func importRejectsBadSizesAndByteCounts() {
    #expect(throws: RasterError.self) { try PixelBuffer(width: 2, height: 1, sRGB8Bytes: [0, 0, 0, 0]) }
    #expect(throws: RasterError.self) { try PixelBuffer(width: 0, height: 1, sRGB8Bytes: []) }
    #expect(throws: RasterError.self) { try PixelBuffer(width: Int.max, height: 2, sRGB8Bytes: []) }
}

@Test func importFuzzThrowsOrRoundTripsWithoutCrashing() throws {
    var rng = SplitMix64(seed: 141)
    for _ in 0..<300 {
        let width = Int.random(in: -2...5, using: &rng)
        let height = Int.random(in: -2...5, using: &rng)
        // Half the time the byte count fits the size, so both paths run.
        let fits = Bool.random(using: &rng) && width > 0 && height > 0
        let count = fits ? width * height * 4 : Int.random(in: 0...120, using: &rng)
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }
        guard let buffer = try? PixelBuffer(width: width, height: height, sRGB8Bytes: bytes) else { continue }
        #expect(buffer.width == width && buffer.height == height)
        #expect(try buffer.sRGB8Bytes().count == bytes.count)
    }
}
