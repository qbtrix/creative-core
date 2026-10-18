// ProfileConvertTests.swift: PixelBuffer.converted(from:to:) changes the
// numbers of a linear premultiplied buffer from one profile's primaries to
// another's. sRGB to Display P3 and back is the identity within 1e-5; alpha
// never moves; alpha 0 pixels come back untouched; a colour is converted
// straight (unpremultiplied), not premultiplied; out-of-gamut values are
// kept, not clamped; a non-finite result or a bad profile throws RasterError
// with a plain message; a source whose curve is not CoreColor's sRGB curve
// decodes with its own curve; between built-ins the sRGB curve gets no
// curve pass, so sRGB to Display P3 and back is exact to 1e-6; a target
// whose curve is not the sRGB curve encodes with its own curve; the input
// is file numbers decoded with TransferCurve, not curve-free linear light;
// the fast curve tables match the exact per-pixel path within 1e-5, and
// values the tables do not cover (out of gamut, tiny) take that exact path.
import CoreColor
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

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

    /// The documented input contract: pixels are file numbers decoded with TransferCurve, so a gamma-2.2
    /// source converted to its own gamma-1 twin gives pow(encode(v), 2.2), not v (a "linear in" reading).
    @Test func sourceCurveReplacesTransferCurveDecode() throws {
        var linear = ColorProfile(name: "G22", isGray: false, toXYZD50: ColorProfile.displayP3.toXYZD50,
                                  curves: Array(repeating: .gamma(2.2), count: 3))
        let g22 = linear
        linear.curves = Array(repeating: .gamma(1), count: 3)
        var rng = SplitMix64(seed: 0xD0_C5_22)
        for _ in 0..<20 {
            let encoded = Double.random(in: 0.05...1, using: &rng)
            let v = Float(TransferCurve.decode(encoded))
            let buffer = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: v, g: v, b: v, a: 1))
            let out = try buffer.converted(from: g22, to: linear).pixel(x: 0, y: 0)
            let want = Float(pow(TransferCurve.encode(Double(v)), 2.2))
            #expect(abs(out.r - want) <= 1e-5 && abs(out.g - want) <= 1e-5 && abs(out.b - want) <= 1e-5, "\(encoded)")
        }
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

    /// The fast path (curve tables, hoisted matrix) against the documented exact path, pixel by pixel, both
    /// ways between the walk's wide-gamut gamma profile and linear sRGB: in-range values, out-of-gamut and
    /// tiny values the tables do not cover, and alpha 0 pixels.
    @Test func curveTablesMatchExactPath() throws {
        let width = 64, height = 16, wide = ProfileWalkTests.wide
        var rng = SplitMix64(seed: 0xC3_7AB1)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                func channel() -> Float {
                    switch Int.random(in: 0..<20, using: &rng) {
                    case 0: return .random(in: -0.5...0, using: &rng)
                    case 1: return .random(in: 1...1.5, using: &rng)
                    case 2: return .random(in: 0...1e-8, using: &rng)
                    default: return .random(in: 0...1, using: &rng)
                    }
                }
                let a: Float = (x + y) % 9 == 0 ? 0 : .random(in: 0.05...1, using: &rng)
                try buffer.setPixel(x: x, y: y, RGBA(r: channel(), g: channel(), b: channel(), a: a).premultiplied())
            }
        }
        let decode = try ProfileTransform(from: wide, to: .linearSRGB)
        let encode = try ProfileTransform(from: .linearSRGB, to: wide)
        let cases: [(ColorProfile, ColorProfile, (Color3) -> Color3)] = [
            (wide, .linearSRGB, { s in
                decode.apply(Color3(TransferCurve.encode(s.c0), TransferCurve.encode(s.c1), TransferCurve.encode(s.c2)))
            }),
            (.linearSRGB, wide, { s in
                let e = encode.apply(s)
                return Color3(TransferCurve.decode(e.c0), TransferCurve.decode(e.c1), TransferCurve.decode(e.c2))
            }),
        ]
        for (source, target, exact) in cases {
            let out = try buffer.converted(from: source, to: target)
            for y in 0..<height {
                for x in 0..<width {
                    let p = try buffer.pixel(x: x, y: y), q = try out.pixel(x: x, y: y)
                    guard p.a > 0 else { #expect(q == p); continue }
                    let s = p.unpremultiplied(), got = q.unpremultiplied()
                    let want = exact(Color3(Double(s.r), Double(s.g), Double(s.b)))
                    #expect(q.a == p.a)
                    #expect(abs(Double(got.r) - want.c0) <= 1e-5 && abs(Double(got.g) - want.c1) <= 1e-5
                            && abs(Double(got.b) - want.c2) <= 1e-5, "\(source.name) (\(x), \(y)): \(got) against \(want)")
                }
            }
        }
    }
}
