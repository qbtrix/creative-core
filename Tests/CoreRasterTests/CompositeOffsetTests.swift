// CompositeOffsetTests.swift: composite(_:onto:x:y:mode:opacity:), the source
// at an integer offset clipped to the backdrop. Checked against the same-size
// composite of the source padded with transparent pixels (a transparent source
// pixel leaves the backdrop exactly), plus the issue's concrete placements.
import CoreRaster
import Testing

private func randomBuffer(_ w: Int, _ h: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    return buffer
}

/// `source` copied onto a transparent buffer the size of `backdrop` at (x, y), clipped.
private func padded(_ source: PixelBuffer, like backdrop: PixelBuffer, x: Int, y: Int) throws -> PixelBuffer {
    var out = try PixelBuffer(width: backdrop.width, height: backdrop.height)
    for sy in 0..<source.height {
        for sx in 0..<source.width where (0..<out.width).contains(x + sx) && (0..<out.height).contains(y + sy) {
            try out.setPixel(x: x + sx, y: y + sy, source.pixel(x: sx, y: sy))
        }
    }
    return out
}

private let red = RGBA(r: 1, g: 0, b: 0, a: 1)

@Test func zeroOffsetMatchesTheSameSizeCompositeInEveryMode() throws {
    var rng = SplitMix64(seed: 181)
    for _ in 0..<10 {
        let w = Int.random(in: 1...6, using: &rng)
        let h = Int.random(in: 1...6, using: &rng)
        let source = try randomBuffer(w, h, &rng)
        let backdrop = try randomBuffer(w, h, &rng)
        let opacity = Float.random(in: 0...1, using: &rng)
        for mode in BlendMode.allCases {
            #expect(try composite(source, onto: backdrop, x: 0, y: 0, mode: mode, opacity: opacity)
                == composite(source, onto: backdrop, mode: mode, opacity: opacity))
        }
    }
}

@Test func anyOffsetMatchesThePaddedSourceInEveryMode() throws {
    var rng = SplitMix64(seed: 1810)
    for _ in 0..<40 {
        let backdrop = try randomBuffer(.random(in: 1...6, using: &rng), .random(in: 1...6, using: &rng), &rng)
        let source = try randomBuffer(.random(in: 1...6, using: &rng), .random(in: 1...6, using: &rng), &rng)
        let x = Int.random(in: -7...7, using: &rng)
        let y = Int.random(in: -7...7, using: &rng)
        let opacity = Float.random(in: 0...1, using: &rng)
        let reference = try padded(source, like: backdrop, x: x, y: y)
        for mode in BlendMode.allCases {
            #expect(try composite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity)
                == composite(reference, onto: backdrop, mode: mode, opacity: opacity), "\(mode) at (\(x), \(y))")
        }
    }
}

@Test func positiveOffsetChangesExactlyTheOverlap() throws {
    let backdrop = try PixelBuffer(width: 8, height: 4)
    let source = try PixelBuffer(width: 2, height: 2, fill: red)
    let out = try composite(source, onto: backdrop, x: 3, y: 1, mode: .normal, opacity: 1)
    for y in 0..<4 {
        for x in 0..<8 {
            let inside = (3...4).contains(x) && (1...2).contains(y)
            #expect(try out.pixel(x: x, y: y) == (inside ? red : .clear), "(\(x), \(y))")
        }
    }
}

@Test func negativeOffsetLandsOnlyTheOverlappingCorner() throws {
    let backdrop = try PixelBuffer(width: 8, height: 4)
    var source = try PixelBuffer(width: 2, height: 2, fill: RGBA(r: 0, g: 0, b: 1, a: 1))
    try source.setPixel(x: 1, y: 1, red)
    let out = try composite(source, onto: backdrop, x: -1, y: -1, mode: .normal, opacity: 1)
    var want = backdrop
    try want.setPixel(x: 0, y: 0, red)
    #expect(out == want)
}

@Test func partlyOffCanvasClipsAtTheFarEdges() throws {
    let backdrop = try PixelBuffer(width: 8, height: 4)
    let source = try PixelBuffer(width: 3, height: 3, fill: red)
    let out = try composite(source, onto: backdrop, x: 6, y: 2, mode: .normal, opacity: 1)
    var want = backdrop
    for (x, y) in [(6, 2), (7, 2), (6, 3), (7, 3)] { try want.setPixel(x: x, y: y, red) }
    #expect(out == want)
}

@Test func offCanvasSourceReturnsTheBackdrop() throws {
    var rng = SplitMix64(seed: 18100)
    let backdrop = try randomBuffer(8, 4, &rng)
    let source = try PixelBuffer(width: 2, height: 2, fill: red)
    for (x, y) in [(100, 0), (8, 0), (0, 4), (-2, 0), (0, -2), (Int.max, Int.max), (Int.min, Int.min)] {
        #expect(try composite(source, onto: backdrop, x: x, y: y, mode: .multiply, opacity: 1) == backdrop)
    }
}

@Test func opacityAndModeCarryThrough() throws {
    let backdrop = try PixelBuffer(width: 3, height: 1, fill: RGBA(r: 0.4, g: 0.6, b: 0.2, a: 1))
    let source = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.8, g: 0.3, b: 0.5, a: 1))
    let out = try composite(source, onto: backdrop, x: 1, y: 0, mode: .multiply, opacity: 0.5)
    // Multiply gives (0.32, 0.18, 0.1); half opacity mixes it evenly with the backdrop.
    let got = try out.pixel(x: 1, y: 0)
    let diffs = zip([got.r, got.g, got.b, got.a], [0.36, 0.39, 0.15, 1] as [Float]).map { abs($0 - $1) }
    #expect(diffs.allSatisfy { $0 <= 1e-6 }, "got \(got)")
    #expect(try out.pixel(x: 0, y: 0) == backdrop.pixel(x: 0, y: 0))
    #expect(try out.pixel(x: 2, y: 0) == backdrop.pixel(x: 2, y: 0))
}

@Test func badOpacityThrowsEvenOffCanvas() throws {
    let a = try PixelBuffer(width: 2, height: 2)
    for opacity: Float in [2, -0.001, .nan, .infinity] {
        for (x, y) in [(0, 0), (100, 0)] {
            #expect(throws: RasterError.self) { try composite(a, onto: a, x: x, y: y, mode: .normal, opacity: opacity) }
        }
    }
}
