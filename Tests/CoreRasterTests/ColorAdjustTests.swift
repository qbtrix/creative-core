// ColorAdjustTests.swift: tone-pack TP-3's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md): vibrance, hueSaturation and hsl.
// `ToneCheck` holds the helpers the tone suites
// share: values are stated as straight sRGB-encoded rgb, as ToneFixtures does.
import CoreColor
import CoreRaster
import Testing

enum ToneCheck {
    /// Straight sRGB-encoded rgb of a premultiplied linear pixel (alpha 0 gives zero).
    static func encoded(_ p: RGBA) -> SIMD3<Double> {
        let s = p.unpremultiplied()
        return SIMD3(TransferCurve.encode(Double(s.r)), TransferCurve.encode(Double(s.g)), TransferCurve.encode(Double(s.b)))
    }

    /// The premultiplied linear pixel of straight encoded `rgb` at alpha `a`.
    static func pixel(_ rgb: SIMD3<Double>, a: Float = 1) -> RGBA {
        RGBA(r: Float(TransferCurve.decode(rgb.x)), g: Float(TransferCurve.decode(rgb.y)),
             b: Float(TransferCurve.decode(rgb.z)), a: a).premultiplied()
    }

    static func luma(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func spread(_ c: SIMD3<Double>) -> Double { c.max() - c.min() }

    /// The largest componentwise difference.
    static func gap(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return max(abs(d.x), abs(d.y), abs(d.z))
    }

    static func gap(_ p: RGBA, _ q: RGBA) -> Float { max(abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a)) }

    /// Standard HSL of encoded rgb: hue in degrees 0..<360.
    static func hsl(_ c: SIMD3<Double>) -> (h: Double, s: Double, l: Double) {
        let hi = c.max(), lo = c.min(), l = (hi + lo) / 2, d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let h = hi == c.x ? (c.y - c.z) / d : hi == c.y ? (c.z - c.x) / d + 2 : (c.x - c.y) / d + 4
        return ((h * 60 + 360).truncatingRemainder(dividingBy: 360), d / (1 - abs(2 * l - 1)), l)
    }

    static func rgb(h: Double, s: Double, l: Double) -> SIMD3<Double> {
        let c = (1 - abs(2 * l - 1)) * s, hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let sector: SIMD3<Double> = switch Int(hp) % 6 {
        case 0: [c, x, 0]
        case 1: [x, c, 0]
        case 2: [0, c, x]
        case 3: [0, x, c]
        case 4: [x, 0, c]
        default: [c, 0, x]
        }
        return sector + SIMD3(repeating: l - c / 2)
    }

    /// A one-row buffer of `pixels`.
    static func row(_ pixels: [RGBA]) throws -> PixelBuffer {
        var b = try PixelBuffer(width: pixels.count, height: 1)
        for (x, p) in pixels.enumerated() { try b.setPixel(x: x, y: 0, p) }
        return b
    }

    static func pixels(_ b: PixelBuffer) throws -> [RGBA] {
        try (0..<b.height).flatMap { y in try (0..<b.width).map { try b.pixel(x: $0, y: y) } }
    }

    /// Seeded sRGB bytes; alpha seeded too unless `opaque`.
    static func seeded(width: Int, height: Int, seed: UInt64, opaque: Bool = false) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        let bytes = (0..<width * height * 4).map { i in opaque && i % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: rng.next()) }
        return try PixelBuffer(rgba8: bytes, width: width, height: height)
    }

    /// `op` keeps every pixel's alpha and passes an alpha-0 pixel through untouched.
    static func expectAlphaKept(_ name: String, _ op: (PixelBuffer) throws -> PixelBuffer) throws {
        let input = [pixel([0.8, 0.3, 0.2], a: 0.5), pixel([0.1, 0.6, 0.9], a: 0.25), RGBA.clear]
        let out = try pixels(op(row(input)))
        #expect(out.map(\.a) == input.map(\.a), "\(name)")
        #expect(out.last == RGBA.clear, "\(name)")
    }
}

@Suite struct ColorAdjustTests {
    /// Hue/saturation as TP-3 defines it (lead note on #432): the standard HSL
    /// rotate/scale/blend on the encoded values; hue rotates, saturation scales
    /// by 1 + s/100, and lightness blends toward white (positive) or black
    /// (negative). `hueSaturationHandValues` pins it to hand-computed pixels.
    static func hueSaturationReference(_ p: RGBA, hue: Double, saturation: Double, lightness: Double) -> RGBA {
        guard p.a > 0 else { return p }
        var (h, s, l) = ToneCheck.hsl(ToneCheck.encoded(p))
        h = (h + hue + 360).truncatingRemainder(dividingBy: 360)
        s = min(1, max(0, s * (1 + saturation / 100)))
        l = lightness >= 0 ? l + (1 - l) * lightness / 100 : l * (1 + lightness / 100)
        return ToneCheck.pixel(ToneCheck.rgb(h: h, s: s, l: l), a: p.a)
    }

    @Test func neutralIsIdentity() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xA1)
        #expect(try b.vibrance(0) == b)
        #expect(try b.hueSaturation(hue: 0, saturation: 0, lightness: 0) == b)
        #expect(try b.hsl(HSLAdjustment()) == b)
    }

    @Test func lowSaturationMovesMost() throws {
        func gain(_ c: ToneFixtures.Reference) throws -> Double {
            let out = try ToneCheck.pixels(ToneCheck.row([c.pixel]).vibrance(100))
            return ToneCheck.hsl(ToneCheck.encoded(out[0])).s - Double(c.saturation)
        }
        let low = try gain(ToneFixtures.saturated10), high = try gain(ToneFixtures.saturated90)
        #expect(low > 0)
        #expect(low > high)
    }

    /// The skin tone (hue 20°) against a colour of the same HSL saturation and
    /// lightness at hue 200°: its linear chroma grows half as much.
    @Test func skinMovesHalf() throws {
        let skin = ToneFixtures.skinTone.pixel, other = ToneCheck.pixel([0.5, 0.7, 0.8])
        let out = try ToneCheck.pixels(ToneCheck.row([skin, other]).vibrance(50))
        func chroma(_ p: RGBA) -> Float {
            let y = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
            return ((p.r - y) * (p.r - y) + (p.g - y) * (p.g - y) + (p.b - y) * (p.b - y)).squareRoot()
        }
        let boostSkin = chroma(out[0]) / chroma(skin) - 1, boostOther = chroma(out[1]) / chroma(other) - 1
        #expect(boostOther > 0)
        #expect(abs(boostSkin / boostOther - 0.5) <= 0.05)
    }

    @Test func hueSaturationMatchesHSLReference() throws {
        let b = try ToneCheck.seeded(width: 40, height: 25, seed: 0xA2)
        let input = try ToneCheck.pixels(b)
        for (h, s, l) in [(30.0, 25.0, -10.0), (-120, -60, 40), (170, 100, 0)] {
            let out = try ToneCheck.pixels(b.hueSaturation(hue: Float(h), saturation: Float(s), lightness: Float(l)))
            for (p, q) in zip(input, out) {
                let r = Self.hueSaturationReference(p, hue: h, saturation: s, lightness: l)
                #expect(ToneCheck.gap(q, r) <= 1e-6, "\(p) at \(h), \(s), \(l)")
            }
        }
    }

    @Test func blueRangeGreysBlueOnly() throws {
        let green = ToneCheck.pixel([0, 1, 0])
        let input = [ToneFixtures.pureBlue.pixel, ToneFixtures.pureRed.pixel, green]
        let out = try ToneCheck.pixels(ToneCheck.row(input).hsl(HSLAdjustment(blues: HSLShift(saturation: -100))))
        #expect(ToneCheck.spread(ToneCheck.encoded(out[0])) <= 1e-6)
        for (p, q) in zip(input.dropFirst(), out.dropFirst()) {
            #expect(ToneCheck.gap(q, p) <= 1e-6)
        }
    }

    /// Every range at lightness -50 halves every saturated pixel's HSL
    /// lightness, exactly as one range alone would: the weights sum to 1
    /// (a sum above 1 darkens more, below 1 less). Greys pass through.
    @Test func rangeWeightsSumToOne() throws {
        let dark = HSLShift(lightness: -50)
        let all = HSLAdjustment(reds: dark, oranges: dark, yellows: dark, greens: dark, aquas: dark, blues: dark,
                                purples: dark, magentas: dark)
        let b = try ToneCheck.seeded(width: 32, height: 16, seed: 0xA3, opaque: true)
        let input = try ToneCheck.pixels(b)
        let single = try ToneCheck.pixels(b.hueSaturation(hue: 0, saturation: 0, lightness: -50))
        for (i, q) in try ToneCheck.pixels(b.hsl(all)).enumerated() {
            let grey = ToneCheck.spread(ToneCheck.encoded(input[i])) == 0
            #expect(ToneCheck.gap(q, grey ? input[i] : single[i]) <= 1e-5, "\(input[i])")
        }
    }

    /// Hand-computed pixels, independent of the formula's code: hue +120 turns
    /// pure red pure green; hue leaves mid grey alone; saturation -100 greys red
    /// at its HSL lightness 0.5; lightness +-50 blends red toward white or black.
    @Test func hueSaturationHandValues() throws {
        let red = ToneCheck.pixel([1, 0, 0]), grey = ToneCheck.pixel([0.5, 0.5, 0.5])
        let cases: [(RGBA, Float, Float, Float, SIMD3<Double>)] = [
            (red, 120, 0, 0, [0, 1, 0]), (grey, 90, 0, 0, [0.5, 0.5, 0.5]), (red, 0, -100, 0, [0.5, 0.5, 0.5]),
            (red, 0, 0, 50, [1, 0.5, 0.5]), (red, 0, 0, -50, [0.5, 0, 0]), (red, -60, 0, 0, [1, 0, 1]),
        ]
        for (p, h, s, l, want) in cases {
            let out = try ToneCheck.pixels(ToneCheck.row([p]).hueSaturation(hue: h, saturation: s, lightness: l))
            #expect(ToneCheck.gap(ToneCheck.encoded(out[0]), want) <= 1e-5, "\(p) at \(h), \(s), \(l)")
        }
    }

    /// An `HSLShift` hue of 100 is a 30 degree turn, the same as `hueSaturation(hue: 30)`.
    @Test func hslHueIsPercentOfThirtyDegrees() throws {
        let red = try ToneCheck.row([ToneFixtures.pureRed.pixel])
        let ranged = try ToneCheck.pixels(red.hsl(HSLAdjustment(reds: HSLShift(hue: 100))))
        let turned = try ToneCheck.pixels(red.hueSaturation(hue: 30, saturation: 0, lightness: 0))
        #expect(ToneCheck.gap(ranged[0], turned[0]) <= 1e-5)
    }

    /// Reds hue 100 turns pure red to hue 30; reds lightness 50 lifts pure red
    /// to HSL lightness 0.75 and leaves a mid grey (no hue) alone.
    @Test func rangeHueAndLightness() throws {
        let red = ToneFixtures.pureRed.pixel, grey = ToneCheck.pixel([0.5, 0.5, 0.5])
        let turned = try ToneCheck.pixels(ToneCheck.row([red]).hsl(HSLAdjustment(reds: HSLShift(hue: 100))))
        #expect(abs(ToneCheck.hsl(ToneCheck.encoded(turned[0])).h - 30) <= 1e-4)
        let lifted = try ToneCheck.pixels(ToneCheck.row([red, grey]).hsl(HSLAdjustment(reds: HSLShift(lightness: 50))))
        #expect(abs(ToneCheck.hsl(ToneCheck.encoded(lifted[0])).l - 0.75) <= 1e-4)
        #expect(lifted[1] == grey)
    }

    /// vibrance -100 is grey at linear luma; vibrance 100 keeps every in-gamut
    /// straight channel in 0...1.
    @Test func vibranceNegativeAndCapped() throws {
        let b = try ToneCheck.seeded(width: 32, height: 16, seed: 0xA6, opaque: true)
        for p in try ToneCheck.pixels(b.vibrance(-100)) {
            let y = 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b
            #expect(max(abs(p.r - y), abs(p.g - y), abs(p.b - y)) <= 1e-6, "\(p)")
        }
        for p in try ToneCheck.pixels(b.vibrance(100)) {
            let s = p.unpremultiplied()
            #expect([s.r, s.g, s.b].allSatisfy { (-1e-6...(1 + 1e-6)).contains($0) }, "\(s)")
        }
    }

    @Test func alphaKept() throws {
        try ToneCheck.expectAlphaKept("vibrance") { try $0.vibrance(60) }
        try ToneCheck.expectAlphaKept("hueSaturation") { try $0.hueSaturation(hue: 40, saturation: 30, lightness: 10) }
        try ToneCheck.expectAlphaKept("hsl") { try $0.hsl(HSLAdjustment(reds: HSLShift(hue: 20, saturation: 30, lightness: 10))) }
    }

    /// An alpha-0 pixel with stored colour (not `RGBA.clear`) passes through
    /// every op untouched: the shared alpha-0 guard skips it rather than
    /// unpremultiplying it to zero and writing that back.
    @Test func alphaZeroKeepsStoredColor() throws {
        let hidden = RGBA(r: 0.4, g: 0.2, b: 0.7, a: 0)
        let b = try ToneCheck.row([ToneCheck.pixel([0.8, 0.3, 0.2]), hidden])
        let outs = [("vibrance", try b.vibrance(60)),
                    ("hueSaturation", try b.hueSaturation(hue: 40, saturation: 30, lightness: 10)),
                    ("hsl", try b.hsl(HSLAdjustment(reds: HSLShift(hue: 20, saturation: 30, lightness: 10))))]
        for (name, out) in outs {
            #expect(try out.pixel(x: 1, y: 0) == hidden, "\(name)")
        }
    }

    @Test func nanThrows() throws {
        let b = try ToneCheck.seeded(width: 2, height: 2, seed: 0xA4)
        #expect(throws: RasterError.self) { try b.vibrance(.nan) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: .nan, saturation: 0, lightness: 0) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 0, saturation: .nan, lightness: 0) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 0, saturation: 0, lightness: .nan) }
        #expect(throws: RasterError.self) { try b.hsl(HSLAdjustment(greens: HSLShift(hue: .nan))) }
        let error = #expect(throws: RasterError.self) { try b.hsl(HSLAdjustment(blues: HSLShift(hue: .nan))) }
        guard case .invalid(let why) = error else { return }
        #expect(why.contains("blues"), "\(why)")
    }

    /// The documented policy: vibrance and hueSaturation throw out of range,
    /// hsl clamps (reds saturation 150 acts as 100).
    @Test func outOfRangePolicyIsDocumented() throws {
        let b = try ToneCheck.seeded(width: 4, height: 4, seed: 0xA7, opaque: true)
        #expect(throws: RasterError.self) { try b.vibrance(101) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 181, saturation: 0, lightness: 0) }
        let over = try b.hsl(HSLAdjustment(reds: HSLShift(saturation: 150)))
        #expect(over == (try b.hsl(HSLAdjustment(reds: HSLShift(saturation: 100)))))
    }

    /// Out-of-range sliders throw; an `HSLShift` component is clamped to -100...100.
    @Test func rangesCheckedOrClamped() throws {
        let b = try ToneCheck.seeded(width: 4, height: 4, seed: 0xA5, opaque: true)
        #expect(throws: RasterError.self) { try b.vibrance(101) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 181, saturation: 0, lightness: 0) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 0, saturation: -101, lightness: 0) }
        let over = try b.hsl(HSLAdjustment(greens: HSLShift(hue: 150, saturation: -300, lightness: 120)))
        #expect(over == (try b.hsl(HSLAdjustment(greens: HSLShift(hue: 100, saturation: -100, lightness: 100)))))
    }
}
