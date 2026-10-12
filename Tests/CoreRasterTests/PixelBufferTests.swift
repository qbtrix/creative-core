// PixelBufferTests.swift: PixelBuffer size validation (seeded fuzz), bounds-
// checked get and set, non-finite rejection, and the RGBA premultiply helpers.
import CoreRaster
import Testing

private func randomPixel(_ rng: inout SplitMix64) -> RGBA {
    RGBA(r: .random(in: -2...2, using: &rng), g: .random(in: -2...2, using: &rng),
         b: .random(in: -2...2, using: &rng), a: .random(in: 0...1, using: &rng))
}

@Test func sizeFuzzThrowsForEveryInvalidSizeAndNeverCrashes() throws {
    var rng = SplitMix64(seed: 112)
    let edges = [Int.min, -1_000_000, -1, 0, 1, 2, 63, 16_384, 16_385, 1 << 31, 1 << 62, Int.max]
    var invalid = 0
    for _ in 0..<2_000 {
        let w = Bool.random(using: &rng) ? edges.randomElement(using: &rng) ?? 0 : Int.random(in: -8...8, using: &rng)
        let h = Bool.random(using: &rng) ? edges.randomElement(using: &rng) ?? 0 : Int.random(in: -8...8, using: &rng)
        let wide = w.multipliedFullWidth(by: h)
        let valid = w >= 1 && h >= 1 && wide.high == 0 && wide.low <= UInt(PixelBuffer.maxPixels)
        if valid {
            #expect(try PixelBuffer.validatedSize(width: w, height: h) == w * h)
            // Only allocate the small ones; the boundary is covered by validatedSize.
            if w * h <= 64 * 64 {
                let buffer = try PixelBuffer(width: w, height: h)
                #expect(buffer.width == w && buffer.height == h)
            }
        } else {
            invalid += 1
            #expect(throws: RasterError.self) { try PixelBuffer.validatedSize(width: w, height: h) }
            #expect(throws: RasterError.self) { try PixelBuffer(width: w, height: h) }
        }
    }
    #expect(invalid > 500)
}

@Test func sizeLimitIsExactlyMaxPixels() throws {
    #expect(PixelBuffer.maxPixels == 268_435_456)
    #expect(try PixelBuffer.validatedSize(width: 16_384, height: 16_384) == PixelBuffer.maxPixels)
    #expect(try PixelBuffer.validatedSize(width: PixelBuffer.maxPixels, height: 1) == PixelBuffer.maxPixels)
    #expect(throws: RasterError.self) { try PixelBuffer.validatedSize(width: 16_385, height: 16_384) }
    #expect(throws: RasterError.self) { try PixelBuffer.validatedSize(width: 1, height: PixelBuffer.maxPixels + 1) }
    #expect(throws: RasterError.self) { try PixelBuffer.validatedSize(width: Int.max, height: 2) }
    #expect(throws: RasterError.self) { try PixelBuffer.validatedSize(width: 0, height: 5) }
}

@Test func initFillsEveryPixel() throws {
    let fill = RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.5)
    let buffer = try PixelBuffer(width: 3, height: 2, fill: fill)
    for y in 0..<2 {
        for x in 0..<3 { #expect(try buffer.pixel(x: x, y: y) == fill) }
    }
    #expect(try PixelBuffer(width: 1, height: 1).pixel(x: 0, y: 0) == .clear)
    #expect(throws: RasterError.self) { try PixelBuffer(width: 1, height: 1, fill: RGBA(r: .nan, g: 0, b: 0, a: 1)) }
}

@Test func setAndGetRoundTripIncludingCorners() throws {
    var rng = SplitMix64(seed: 7)
    for _ in 0..<50 {
        let w = Int.random(in: 1...17, using: &rng)
        let h = Int.random(in: 1...17, using: &rng)
        var buffer = try PixelBuffer(width: w, height: h)
        var expected: [[RGBA]] = Array(repeating: Array(repeating: .clear, count: w), count: h)
        let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
        let others = (0..<20).map { _ in (Int.random(in: 0..<w, using: &rng), Int.random(in: 0..<h, using: &rng)) }
        for (x, y) in corners + others {
            let p = randomPixel(&rng)
            try buffer.setPixel(x: x, y: y, p)
            expected[y][x] = p
        }
        for y in 0..<h {
            for x in 0..<w { #expect(try buffer.pixel(x: x, y: y) == expected[y][x]) }
        }
    }
}

@Test func outOfBoundsReadsAndWritesThrowAndLeaveTheBufferUnchanged() throws {
    var buffer = try PixelBuffer(width: 4, height: 3)
    let before = buffer
    let p = RGBA(r: 1, g: 1, b: 1, a: 1)
    for (x, y) in [(-1, 0), (0, -1), (4, 0), (0, 3), (4, 3), (Int.min, 0), (0, Int.max)] {
        #expect(throws: RasterError.self) { try buffer.pixel(x: x, y: y) }
        #expect(throws: RasterError.self) { try buffer.setPixel(x: x, y: y, p) }
    }
    #expect(buffer == before)
}

@Test func nonFinitePixelsAreRejected() throws {
    var buffer = try PixelBuffer(width: 2, height: 2)
    let before = buffer
    let bad = [RGBA(r: .nan, g: 0, b: 0, a: 1), RGBA(r: 0, g: .infinity, b: 0, a: 1),
               RGBA(r: 0, g: 0, b: -.infinity, a: 1), RGBA(r: 0, g: 0, b: 0, a: .nan)]
    for p in bad {
        #expect(throws: RasterError.self) { try buffer.setPixel(x: 1, y: 1, p) }
    }
    #expect(buffer == before)
}

@Test func buffersAreValuesThatCompareByContent() throws {
    var a = try PixelBuffer(width: 2, height: 2)
    let b = a
    try a.setPixel(x: 0, y: 0, RGBA(r: 0.5, g: 0, b: 0, a: 0.5))
    #expect(a != b)
    #expect(try b.pixel(x: 0, y: 0) == .clear)
    #expect(try PixelBuffer(width: 2, height: 1) != PixelBuffer(width: 1, height: 2))
}

@Test func premultiplyHelpers() {
    #expect(RGBA(r: 0.8, g: 0.4, b: 0.2, a: 0.5).premultiplied() == RGBA(r: 0.4, g: 0.2, b: 0.1, a: 0.5))
    #expect(RGBA(r: 0.4, g: 0.2, b: 0.1, a: 0.5).unpremultiplied() == RGBA(r: 0.8, g: 0.4, b: 0.2, a: 0.5))
    #expect(RGBA(r: 0.3, g: 0.2, b: 0.1, a: 0).unpremultiplied() == .clear)
    var rng = SplitMix64(seed: 99)
    for _ in 0..<1_000 {
        let p = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                     b: .random(in: 0...1, using: &rng), a: .random(in: 0.001...1, using: &rng))
        let back = p.premultiplied().unpremultiplied()
        #expect(abs(back.r - p.r) <= 1e-6 && abs(back.g - p.g) <= 1e-6)
        #expect(abs(back.b - p.b) <= 1e-6 && back.a == p.a)
    }
}
