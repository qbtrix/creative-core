// ToneEncodingTests.swift: levels, curves and the histogram on sRGB-encoded
// values (ToneEncoding.sRGB). A parameter means the value a display shows:
// a curve point at x 0.5 moves the pixel whose sRGB value is 0.5, levels'
// black point is an encoded value, and the histogram puts that pixel in the
// middle bin. Linear stays the default, identities return the input, and the
// table the sRGB mapping reads matches the exact mapping, near black too.
import CoreColor
import CoreRaster
import Testing

/// A one-pixel opaque grey whose sRGB-encoded value is `encoded`.
private func grey(encoded: Double) throws -> PixelBuffer {
    let v = Float(TransferCurve.decode(encoded))
    return try PixelBuffer(width: 1, height: 1, fill: RGBA(r: v, g: v, b: v, a: 1))
}

/// The sRGB-encoded red value of a one-pixel buffer.
private func encodedRed(_ buffer: PixelBuffer) throws -> Double {
    TransferCurve.encode(Double(try buffer.pixel(x: 0, y: 0).r))
}

@Test func anSRGBCurvePointAtAHalfMovesTheGreyThatDisplaysAsAHalf() throws {
    let mid = try grey(encoded: 0.5)
    let lifted = try mid.curves(points: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.7), .init(x: 1, y: 1)], encoding: .sRGB)
    #expect(abs(try encodedRed(lifted) - 0.7) <= 1e-5)
    // On linear values the same point would read the grey as 0.214, not 0.5.
    let linear = try mid.curves(points: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.7), .init(x: 1, y: 1)])
    #expect(abs(try encodedRed(linear) - 0.7) > 0.05)
}

@Test func anSRGBCurveThroughItsMidpointKeepsMidGrey() throws {
    let mid = try grey(encoded: 0.5)
    let kept = try mid.curves(points: [.init(x: 0, y: 0), .init(x: 0.5, y: 0.5), .init(x: 0.75, y: 0.9), .init(x: 1, y: 1)], encoding: .sRGB)
    #expect(abs(try encodedRed(kept) - 0.5) <= 1e-5)
}

@Test func sRGBLevelsTakeEncodedBlackAndWhitePoints() throws {
    // (0.6 - 0.2) / (1 - 0.2) = 0.5 on the encoded axis.
    let out = try grey(encoded: 0.6).levels(inBlack: 0.2, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1, encoding: .sRGB)
    #expect(abs(try encodedRed(out) - 0.5) <= 1e-5)
    let alpha = try out.pixel(x: 0, y: 0).a
    #expect(alpha == 1)
}

@Test func sRGBIdentitiesReturnTheInputUnchanged() throws {
    var rng = SplitMix64(seed: 546)
    var image = try PixelBuffer(width: 5, height: 3)
    for y in 0..<3 {
        for x in 0..<5 { try image.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
    }
    #expect(try image.curves(points: [.init(x: 0, y: 0), .init(x: 1, y: 1)], encoding: .sRGB) == image)
    #expect(try image.levels(inBlack: 0, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1, encoding: .sRGB) == image)
}

@Test func sRGBToneKeepsValuesOutsideTheUnitRangeFinite() throws {
    let hdr = try PixelBuffer(width: 2, height: 1, fill: RGBA(r: 4, g: -0.5, b: 1.5, a: 0.5))
    let out = try hdr.curves(points: [.init(x: 0, y: 0.1), .init(x: 1, y: 0.9)], encoding: .sRGB)
    for x in 0..<2 { #expect(try out.pixel(x: x, y: 0).isFinite) }
    #expect(try out.pixel(x: 0, y: 0).a == 0.5)
}

@Test func theSRGBHistogramPutsDisplayMidGreyInTheMiddleBin() throws {
    let mid = try grey(encoded: 0.5)
    let shown = try Histogram(of: mid, bins: 256, encoding: .sRGB)
    let linear = try Histogram(of: mid, bins: 256)
    #expect(shown.luminance[128] == 1 && shown.red[128] == 1)
    #expect(linear.luminance[54] == 1, "linear 0.214 lands in bin 54")
}

@Test func theSRGBTableMatchesTheExactMappingAcrossTheRange() throws {
    // Levels with gamma 2 on encoded values: decode(encode(v)^0.5), exactly.
    var rng = SplitMix64(seed: 4096)
    var ramp = try PixelBuffer(width: 500, height: 1)
    var inputs: [Double] = []
    for x in 0..<500 {
        let v = x < 4 ? [0, 1e-4, 0.003, 1][x] : Double.random(in: 0...1, using: &rng)
        inputs.append(v)
        try ramp.setPixel(x: x, y: 0, RGBA(r: Float(v), g: Float(v), b: Float(v), a: 1))
    }
    let out = try ramp.levels(inBlack: 0, inWhite: 1, gamma: 2, outBlack: 0, outWhite: 1, encoding: .sRGB)
    for (x, v) in inputs.enumerated() {
        let exact = TransferCurve.decode(TransferCurve.encode(Double(Float(v))).squareRoot())
        #expect(abs(Double(try out.pixel(x: x, y: 0).r) - exact) <= 2e-5, "at \(v)")
    }
}
