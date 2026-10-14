// DevelopAdjustmentTests.swift: the develop sliders on PixelBuffer (white
// balance, contrast, highlights and shadows). Zero gives back the input
// exactly, each slider moves values the documented way, contrast stays
// monotonic, alpha is untouched, and out-of-range or NaN values throw.
import CoreRaster
import Testing

/// An opaque 1-row buffer of gray pixels, so straight equals premultiplied.
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

private func luminance(_ p: RGBA) -> Float {
    let w = Histogram.luminanceWeights
    return w.r * p.r + w.g * p.g + w.b * p.b
}

/// A 4x3 buffer of seeded random premultiplied pixels.
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

@Test func developZeroReturnsTheInputExactly() throws {
    let buffer = try randomBuffer(seed: 231)
    #expect(try buffer.whiteBalance(temperature: 0, tint: 0) == buffer)
    #expect(try buffer.contrast(0) == buffer)
    #expect(try buffer.highlightsShadows(highlights: 0, shadows: 0) == buffer)
}

@Test func whiteBalanceWarmsAndTintsAndKeepsGreyLuminance() throws {
    let grey = try grayRow([0.4])
    let warm = try grey.whiteBalance(temperature: 50, tint: 0).pixel(x: 0, y: 0)
    #expect(warm.r > warm.b)
    #expect(abs(luminance(warm) - 0.4) <= 1e-4)
    let magenta = try grey.whiteBalance(temperature: 0, tint: 50).pixel(x: 0, y: 0)
    #expect(magenta.g < magenta.r && magenta.g < magenta.b)
    #expect(abs(luminance(magenta) - 0.4) <= 1e-4)
    let cool = try grey.whiteBalance(temperature: -50, tint: -50).pixel(x: 0, y: 0)
    #expect(cool.b > cool.r && cool.g > cool.r)
}

@Test func contrastKeepsMidGreyAndPushesAwayFromIt() throws {
    let got = try grays(grayRow([0.18, 0.5, 0.05]).contrast(50))
    #expect(abs(got[0] - 0.18) <= 1e-5)
    #expect(got[1] > 0.5)
    #expect(got[2] < 0.05)
    let flat = try grays(grayRow([0.5, 0.05]).contrast(-50))
    #expect(flat[0] < 0.5 && flat[1] > 0.05)
}

@Test func contrastIsMonotonicOnARampForEverySetting() throws {
    let ramp = try grayRow((0...100).map { Float($0) / 100 })
    for amount in stride(from: Float(-100), through: 100, by: 10) {
        let mapped = try grays(ramp.contrast(amount))
        #expect(zip(mapped, mapped.dropFirst()).allSatisfy { $0 <= $1 }, "contrast \(amount)")
    }
}

@Test func contrastMovesValuesOutsideZeroToOneTheContrastWay() throws {
    // Issue #247: these moved against the contrast direction.
    let row = try grayRow([-0.5, 1.5, 2, 4])
    #expect(try grays(row.contrast(100)) == [-0.75, 1.75, 2.5, 5.5])
    #expect(try grays(row.contrast(-100)) == [-0.25, 1.25, 1.5, 2.5])
    let wide = try grayRow((-20...40).map { Float($0) / 10 })
    let before = try grays(wide)
    for amount in stride(from: Float(-100), through: 100, by: 10) where amount != 0 {
        let after = try grays(wide.contrast(amount))
        #expect(zip(after, after.dropFirst()).allSatisfy { $0 <= $1 }, "contrast \(amount)")
        for (v, out) in zip(before, after) where v < 0 || v > 1 {
            // More contrast pushes away from mid grey; less pulls toward it
            // without crossing 0 or 1.
            let away = (v > 1) == (amount > 0)
            #expect(away ? out > v : out < v, "contrast \(amount) at \(v)")
            #expect(v > 1 ? out > 1 : out < 0, "contrast \(amount) at \(v)")
        }
    }
}

@Test func contrastInsideZeroToOneIsTheSCurve() throws {
    // Contrast reads a table of the curve (issue #255): within 1e-6 of it,
    // including between the table's entries, and exact at 0 and 1.
    let ramp = try grayRow((0...2003).map { Float($0) / 2003 })
    for amount in [Float(-100), -35, 60, 100] {
        let push = amount / 200
        let curve = try ramp.curves(points: [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.09, y: 0.09 * (1 - push)),
            CurvePoint(x: 0.18, y: 0.18),
            CurvePoint(x: 0.59, y: 0.59 + 0.41 * push),
            CurvePoint(x: 1, y: 1),
        ])
        let got = try grays(ramp.contrast(amount))
        for (x, want) in try grays(curve).enumerated() {
            #expect(abs(got[x] - want) <= 1e-6, "contrast \(amount) at \(x)")
        }
        #expect(got.first == 0 && got.last == 1, "contrast \(amount)")
    }
}

@Test func highlightsAndShadowsMoveOnlyTheirEnd() throws {
    let row = try grayRow([0.9, 0.02])
    let recovered = try grays(row.highlightsShadows(highlights: -100, shadows: 0))
    #expect(recovered[0] < 0.9 - 0.1)
    #expect(abs(recovered[1] - 0.02) <= 1e-3)
    let lifted = try grays(row.highlightsShadows(highlights: 0, shadows: 100))
    #expect(lifted[1] > 0.02 + 0.01)
    #expect(abs(lifted[0] - 0.9) <= 1e-3)
}

@Test func developSlidersNeverChangeAlpha() throws {
    let buffer = try randomBuffer(seed: 32)
    let adjusted = [
        try buffer.whiteBalance(temperature: 70, tint: -30),
        try buffer.contrast(-60),
        try buffer.highlightsShadows(highlights: -80, shadows: 90),
    ]
    for result in adjusted {
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                #expect(try result.pixel(x: x, y: y).a == buffer.pixel(x: x, y: y).a)
            }
        }
    }
}

@Test func developSlidersRejectOutOfRangeAndNaN() throws {
    let buffer = try grayRow([0.3])
    for bad in [Float.nan, .infinity, -.infinity, 100.5, -101] {
        #expect(throws: RasterError.self) { try buffer.whiteBalance(temperature: bad, tint: 0) }
        #expect(throws: RasterError.self) { try buffer.whiteBalance(temperature: 0, tint: bad) }
        #expect(throws: RasterError.self) { try buffer.contrast(bad) }
        #expect(throws: RasterError.self) { try buffer.highlightsShadows(highlights: bad, shadows: 0) }
        #expect(throws: RasterError.self) { try buffer.highlightsShadows(highlights: 0, shadows: bad) }
    }
}
