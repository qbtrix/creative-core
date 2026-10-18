// ProfileConvertTests.swift: PixelBuffer.converted(from:to:) changes the
// numbers of a linear premultiplied buffer from one profile's primaries to
// another's. sRGB to Display P3 and back is the identity within 1e-5; alpha
// never moves; alpha 0 pixels come back untouched; a colour is converted
// straight (unpremultiplied), not premultiplied; out-of-gamut values are
// kept, not clamped; a non-finite result or a bad profile throws RasterError
// with a plain message; a source whose curve is not CoreColor's sRGB curve
// decodes with its own curve; between built-ins the sRGB curve gets no
// curve pass, so sRGB to Display P3 and back is exact to 1e-6; a target
// whose curve is not the sRGB curve encodes with its own curve.
import CoreColor
import CoreRaster
import Testing

/// A 7 x 5 buffer of seeded random premultiplied pixels with alpha in 0.05...1.
private func randomBuffer(seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: 7, height: 5)
    for y in 0..<5 {
        for x in 0..<7 {
            var p = randomPixel(&rng)
            p.a = .random(in: 0.05...1, using: &rng)
            try buffer.setPixel(x: x, y: y, p.premultiplied())
        }
    }
    return buffer
}

private func close(_ a: RGBA, _ b: RGBA, within eps: Float) -> Bool {
    abs(a.r - b.r) <= eps && abs(a.g - b.g) <= eps && abs(a.b - b.b) <= eps && a.a == b.a
}

@Suite struct ProfileConvertTests {
    @Test func thereAndBackIsIdentity() throws {
        let buffer = try randomBuffer(seed: 0xC0_10_75)
        let p3 = try buffer.converted(from: .sRGB, to: .displayP3)
        let back = try p3.converted(from: .displayP3, to: .sRGB)
        #expect(p3 != buffer)
        for y in 0..<5 {
            for x in 0..<7 {
                #expect(close(try back.pixel(x: x, y: y), try buffer.pixel(x: x, y: y), within: 1e-5))
                #expect(try p3.pixel(x: x, y: y).a == buffer.pixel(x: x, y: y).a)
            }
        }
    }

    @Test func unpremultipliesFirst() throws {
        let straight = RGBA(r: 0.8, g: 0.3, b: 0.1, a: 0.25)
        let buffer = try PixelBuffer(width: 1, height: 1, fill: straight.premultiplied())
        let out = try buffer.converted(from: .sRGB, to: .displayP3).pixel(x: 0, y: 0)
        let want = try ProfileTransform(from: .sRGB, to: .displayP3)
            .applyLinear(Color3(Double(straight.r), Double(straight.g), Double(straight.b)))
        let expected = RGBA(r: Float(want.c0), g: Float(want.c1), b: Float(want.c2), a: 0.25).premultiplied()
        #expect(close(out, expected, within: 1e-6))
        #expect(out.r != (try buffer.pixel(x: 0, y: 0)).r)
    }

    @Test func transparentPixelsUnchanged() throws {
        var buffer = try PixelBuffer(width: 2, height: 1)
        try buffer.setPixel(x: 1, y: 0, RGBA(r: 0.4, g: -0.2, b: 0.9, a: 0))
        let out = try buffer.converted(from: .sRGB, to: .displayP3)
        #expect(out == buffer)
    }

    @Test func keepsOutOfGamut() throws {
        // Pure Display P3 green lies outside sRGB: red and blue go negative,
        // green goes past 1, and every value stays finite.
        let green = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0, g: 0.5, b: 0, a: 0.5))
        let out = try green.converted(from: .displayP3, to: .sRGB).pixel(x: 0, y: 0)
        let want = try ProfileTransform(from: .displayP3, to: .sRGB).applyLinear(Color3(0, 1, 0))
        #expect(want.c0 < 0 && want.c1 > 1 && want.c2 < 0)
        #expect(out.isFinite)
        #expect(close(out, RGBA(r: Float(want.c0) / 2, g: Float(want.c1) / 2, b: Float(want.c2) / 2, a: 0.5),
                      within: 1e-6))
    }

    @Test func nonFiniteResultThrows() throws {
        let huge = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: .greatestFiniteMagnitude, g: 0, b: 0, a: 1))
        #expect(throws: RasterError.self) { try huge.converted(from: .displayP3, to: .sRGB) }
    }

    @Test func badProfileThrowsRasterError() throws {
        var singular = ColorProfile.sRGB
        singular.toXYZD50 = [1, 1, 1, 1, 1, 1, 1, 1, 1]
        let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1))
        #expect(throws: RasterError.self) { try buffer.converted(from: .sRGB, to: singular) }
    }

    @Test func singularTargetMessage() throws {
        let zero = ColorProfile(name: "Zero", isGray: false, toXYZD50: Array(repeating: 0, count: 9),
                                curves: ColorProfile.sRGB.curves)
        let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1))
        let error = #expect(throws: RasterError.self) { try buffer.converted(from: .sRGB, to: zero) }
        guard case .invalid(let why) = error else { return }
        #expect(why.contains("singular colourants"))
        #expect(!why.contains("invalid("))
        #expect(why.hasPrefix("convert sRGB to Zero: profile Zero"))
    }

    @Test func decodesWithSourceCurve() throws {
        let g22 = ColorProfile(name: "G22", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                               curves: Array(repeating: .gamma(2.2), count: 3))
        let grey = Float(TransferCurve.decode(0.5))
        let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: grey, g: grey, b: grey, a: 1))
        let out = try buffer.converted(from: g22, to: .linearSRGB).pixel(x: 0, y: 0)
        let want: Float = 0.217_637_64  // 0.5^2.2
        #expect(abs(out.r - want) <= 1e-6 && abs(out.g - want) <= 1e-6 && abs(out.b - want) <= 1e-6)
        #expect(out.a == 1)
    }

    @Test func builtInsRoundTripExactly() throws {
        let buffer = try randomBuffer(seed: 0x5E_6B_93)
        let back = try buffer.converted(from: .sRGB, to: .displayP3).converted(from: .displayP3, to: .sRGB)
        for y in 0..<5 {
            for x in 0..<7 {
                #expect(close(try back.pixel(x: x, y: y), try buffer.pixel(x: x, y: y), within: 1e-6))
            }
        }
    }

    @Test func encodesWithTargetCurve() throws {
        let g22 = ColorProfile(name: "G22", isGray: false, toXYZD50: ColorProfile.sRGB.toXYZD50,
                               curves: Array(repeating: .gamma(2.2), count: 3))
        let lin: Float = 0.217_637_64  // 0.5^2.2
        let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: lin, g: lin, b: lin, a: 1))
        let out = try buffer.converted(from: .linearSRGB, to: g22).pixel(x: 0, y: 0)
        let want = Float(TransferCurve.decode(0.5))  // encoded 0.5, held as TransferCurve's linear light
        #expect(abs(out.r - want) <= 1e-6 && abs(out.g - want) <= 1e-6 && abs(out.b - want) <= 1e-6)
        #expect(out.a == 1)
    }
}
