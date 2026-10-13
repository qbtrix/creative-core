// DevelopAdjustmentTests.swift: white balance, contrast, and highlights and
// shadows on PixelBuffer. All-zero parameters give back the input exactly,
// each slider moves the channels and tones it names and no others, contrast is
// monotonic across its range, alpha is untouched, and out-of-range or NaN
// values throw.
import CoreRaster
import Testing

/// An opaque pixel's straight color after `adjust`.
private func adjusted(_ value: RGBA, _ adjust: (PixelBuffer) throws -> PixelBuffer) throws -> RGBA {
    try adjust(PixelBuffer(width: 1, height: 1, fill: value)).pixel(x: 0, y: 0)
}

private func grey(_ v: Float) -> RGBA { RGBA(r: v, g: v, b: v, a: 1) }

private func luminance(_ p: RGBA) -> Float {
    let w = Histogram.luminanceWeights
    return w.r * p.r + w.g * p.g + w.b * p.b
}

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

@Test func allZeroDevelopParametersReturnTheInputExactly() throws {
    let buffer = try randomBuffer(seed: 231)
    #expect(try buffer.whiteBalance(temperature: 0, tint: 0) == buffer)
    #expect(try buffer.contrast(0) == buffer)
    #expect(try buffer.highlightsShadows(highlights: 0, shadows: 0) == buffer)
}

@Test func temperatureWarmsAndKeepsGreyLuminance() throws {
    let g = grey(0.4)
    let warm = try adjusted(g) { try $0.whiteBalance(temperature: 50, tint: 0) }
    #expect(warm.r > warm.b)
    #expect(abs(luminance(warm) - luminance(g)) <= 1e-4, "\(warm)")
    let cool = try adjusted(g) { try $0.whiteBalance(temperature: -50, tint: 0) }
    #expect(cool.b > cool.r)
}

@Test func tintPushesTowardMagentaAndKeepsGreyLuminance() throws {
    let g = grey(0.4)
    let magenta = try adjusted(g) { try $0.whiteBalance(temperature: 0, tint: 50) }
    #expect(magenta.g < magenta.r && magenta.g < magenta.b, "\(magenta)")
    #expect(abs(luminance(magenta) - luminance(g)) <= 1e-4)
    let both = try adjusted(g) { try $0.whiteBalance(temperature: 100, tint: -100) }
    #expect(abs(luminance(both) - luminance(g)) <= 1e-4)
}

@Test func contrastPivotsOnMidGrey() throws {
    let mid = try adjusted(grey(0.18)) { try $0.contrast(50) }
    #expect(abs(mid.r - 0.18) <= 1e-5)
    #expect(try adjusted(grey(0.5)) { try $0.contrast(50) }.r > 0.5)
    #expect(try adjusted(grey(0.05)) { try $0.contrast(50) }.r < 0.05)
    let flatter = try adjusted(grey(0.5)) { try $0.contrast(-50) }.r
    #expect(flatter < 0.5 && flatter > 0.18)
}

@Test func contrastIsMonotonicAcrossItsRange() throws {
    var ramp = try PixelBuffer(width: 101, height: 1)
    for x in 0...100 {
        try ramp.setPixel(x: x, y: 0, grey(Float(x) / 100))
    }
    for amount in stride(from: Float(-100), through: 100, by: 10) {
        let out = try ramp.contrast(amount)
        let values = try (0...100).map { try out.pixel(x: $0, y: 0).r }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 }, "contrast \(amount)")
    }
}

@Test func highlightsMoveOnlyBrightPixels() throws {
    let bright = try adjusted(grey(0.9)) { try $0.highlightsShadows(highlights: -100, shadows: 0) }
    #expect(bright.r < 0.9)
    let dark = try adjusted(grey(0.02)) { try $0.highlightsShadows(highlights: -100, shadows: 0) }
    #expect(abs(dark.r - 0.02) <= 1e-3)
}

@Test func shadowsMoveOnlyDarkPixels() throws {
    let dark = try adjusted(grey(0.02)) { try $0.highlightsShadows(highlights: 0, shadows: 100) }
    #expect(dark.r > 0.02)
    let bright = try adjusted(grey(0.9)) { try $0.highlightsShadows(highlights: 0, shadows: 100) }
    #expect(abs(bright.r - 0.9) <= 1e-3)
}

@Test func developAdjustmentsNeverChangeAlpha() throws {
    let buffer = try randomBuffer(seed: 17)
    let outputs = try [
        buffer.whiteBalance(temperature: 70, tint: -30),
        buffer.contrast(-60),
        buffer.highlightsShadows(highlights: -80, shadows: 90),
    ]
    for out in outputs {
        for y in 0..<buffer.height {
            for x in 0..<buffer.width {
                #expect(try out.pixel(x: x, y: y).a == buffer.pixel(x: x, y: y).a)
            }
        }
    }
}

@Test func outOfRangeAndNaNDevelopValuesThrow() throws {
    let buffer = try PixelBuffer(width: 1, height: 1, fill: grey(0.5))
    for bad: Float in [100.5, -101, .nan, .infinity, -.infinity] {
        #expect(throws: RasterError.self) { try buffer.whiteBalance(temperature: bad, tint: 0) }
        #expect(throws: RasterError.self) { try buffer.whiteBalance(temperature: 0, tint: bad) }
        #expect(throws: RasterError.self) { try buffer.contrast(bad) }
        #expect(throws: RasterError.self) { try buffer.highlightsShadows(highlights: bad, shadows: 0) }
        #expect(throws: RasterError.self) { try buffer.highlightsShadows(highlights: 0, shadows: bad) }
    }
    #expect(try buffer.contrast(100) != buffer)
    #expect(try buffer.contrast(-100) != buffer)
}
