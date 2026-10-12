// AdjustmentsTests.swift: exposure, levels and curves on PixelBuffer. Identity
// parameters give back the input exactly, worked values for each op, curves
// through their control points and monotone on seeded random points, alpha
// untouched, and every invalid parameter throws.
import CoreRaster
import Testing

/// A buffer of seeded random pixels (premultiplied), 4x3.
private func randomBuffer(seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: 4, height: 3)
    for y in 0..<3 {
        for x in 0..<4 {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    return buffer
}

/// An opaque 1-row buffer holding `values` as gray pixels, so straight equals premultiplied.
private func grayRow(_ values: [Float]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: values.count, height: 1)
    for (x, v) in values.enumerated() {
        try buffer.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    return buffer
}

private func grays(_ buffer: PixelBuffer) throws -> [Float] {
    try (0..<buffer.width).map { try buffer.pixel(x: $0, y: 0).r }
}

@Test func identityParametersReturnTheInputExactly() throws {
    let buffer = try randomBuffer(seed: 114)
    #expect(try buffer.exposure(stops: 0) == buffer)
    #expect(try buffer.levels(inBlack: 0, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1) == buffer)
    #expect(try buffer.curves(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]) == buffer)
}

@Test func exposurePlusOneDoublesLinearValues() throws {
    let straight = RGBA(r: 0.25, g: 0.5, b: 1.5, a: 0.5)
    let buffer = try PixelBuffer(width: 1, height: 1, fill: straight.premultiplied())
    let got = try buffer.exposure(stops: 1).pixel(x: 0, y: 0).unpremultiplied()
    #expect(got == RGBA(r: 0.5, g: 1, b: 3, a: 0.5))
    let down = try grays(grayRow([0.8]).exposure(stops: -2))
    #expect(down == [0.2])
}

@Test func levelsMapsBlackWhiteAndGamma() throws {
    let row = try grayRow([0, 0.2, 0.6, 1, 1.4])
    let stretched = try grays(row.levels(inBlack: 0.2, inWhite: 0.6, gamma: 1, outBlack: 0.1, outWhite: 0.9))
    let want: [Float] = [0.1, 0.1, 0.9, 1.7, 2.5]
    #expect(zip(stretched, want).allSatisfy { abs($0 - $1) <= 1e-6 }, "\(stretched)")
    // Gamma 2 is a square root of the normalized value: 0.25 -> 0.5.
    let brightened = try grays(grayRow([0.25]).levels(inBlack: 0, inWhite: 1, gamma: 2, outBlack: 0, outWhite: 1))
    #expect(abs(brightened[0] - 0.5) <= 1e-6)
}

@Test func adjustmentsNeverChangeAlpha() throws {
    let buffer = try randomBuffer(seed: 7)
    let adjusted = [
        try buffer.exposure(stops: 0.7),
        try buffer.levels(inBlack: 0.1, inWhite: 0.9, gamma: 1.3, outBlack: 0.05, outWhite: 0.8),
        try buffer.curves(points: [CurvePoint(x: 0, y: 0.1), CurvePoint(x: 0.5, y: 0.7), CurvePoint(x: 1, y: 0.9)]),
    ]
    for result in adjusted {
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                #expect(try result.pixel(x: x, y: y).a == buffer.pixel(x: x, y: y).a)
            }
        }
    }
}

@Test func curvesPassThroughPointsAndStayMonotoneOnRandomPoints() throws {
    var rng = SplitMix64(seed: 0xC0FFEE)
    for _ in 0..<200 {
        let count = Int.random(in: 2...8, using: &rng)
        let xs = Set((0..<count).map { _ in Float.random(in: 0...1, using: &rng) }).sorted()
        guard xs.count >= 2 else { continue }
        let ys = xs.map { _ in Float.random(in: -1...2, using: &rng) }.sorted()
        let points = zip(xs, ys).map { CurvePoint(x: $0, y: $1) }

        let atPoints = try grays(grayRow(xs).curves(points: points))
        #expect(zip(atPoints, ys).allSatisfy { abs($0 - $1) <= 1e-6 }, "\(points) -> \(atPoints)")

        let grid = (0...200).map { Float($0) / 200 }
        let mapped = try grays(grayRow(grid).curves(points: points))
        #expect(zip(mapped, mapped.dropFirst()).allSatisfy { $0 <= $1 + 1e-6 }, "\(points)")
    }
}

@Test func curvesExtendAlongTheEndTangents() throws {
    // Two points make a straight line, so values outside 0.2...0.6 follow it.
    let points = [CurvePoint(x: 0.2, y: 0.4), CurvePoint(x: 0.6, y: 0.8)]
    let got = try grays(grayRow([0, 0.4, 1, 2]).curves(points: points))
    let want: [Float] = [0.2, 0.6, 1.2, 2.2]
    #expect(zip(got, want).allSatisfy { abs($0 - $1) <= 1e-6 }, "\(got)")
}

@Test func everyInvalidParameterThrows() throws {
    let buffer = try randomBuffer(seed: 1)
    let ok = (inBlack: Float(0), inWhite: Float(1), gamma: Float(1), outBlack: Float(0), outWhite: Float(1))
    for stops in [Float.nan, .infinity, -.infinity, 200] {
        #expect(throws: RasterError.self) { try buffer.exposure(stops: stops) }
    }
    let badLevels: [(Float, Float, Float, Float, Float)] = [
        (.nan, ok.inWhite, ok.gamma, ok.outBlack, ok.outWhite),
        (ok.inBlack, .infinity, ok.gamma, ok.outBlack, ok.outWhite),
        (ok.inBlack, ok.inWhite, .nan, ok.outBlack, ok.outWhite),
        (ok.inBlack, ok.inWhite, ok.gamma, -.infinity, ok.outWhite),
        (ok.inBlack, ok.inWhite, ok.gamma, ok.outBlack, .nan),
        (0.5, 0.5, ok.gamma, ok.outBlack, ok.outWhite),
        (0.6, 0.5, ok.gamma, ok.outBlack, ok.outWhite),
        (ok.inBlack, ok.inWhite, 0, ok.outBlack, ok.outWhite),
        (ok.inBlack, ok.inWhite, -1, ok.outBlack, ok.outWhite),
    ]
    for p in badLevels {
        #expect(throws: RasterError.self) {
            try buffer.levels(inBlack: p.0, inWhite: p.1, gamma: p.2, outBlack: p.3, outWhite: p.4)
        }
    }
    let badCurves: [[CurvePoint]] = [
        [],
        [CurvePoint(x: 0.5, y: 0.5)],
        [CurvePoint(x: 0.5, y: 0), CurvePoint(x: 0.2, y: 1)],
        [CurvePoint(x: 0.5, y: 0), CurvePoint(x: 0.5, y: 1)],
        [CurvePoint(x: -0.1, y: 0), CurvePoint(x: 1, y: 1)],
        [CurvePoint(x: 0, y: 0), CurvePoint(x: 1.1, y: 1)],
        [CurvePoint(x: .nan, y: 0), CurvePoint(x: 1, y: 1)],
        [CurvePoint(x: 0, y: .infinity), CurvePoint(x: 1, y: 1)],
    ]
    for points in badCurves {
        #expect(throws: RasterError.self) { try buffer.curves(points: points) }
    }
}
