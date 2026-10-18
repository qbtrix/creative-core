// ColorAdjustTests.swift: tone-pack TP-3's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md): vibrance, hueSaturation and hsl.
// Disabled until TP-3 lands. `ToneCheck` holds the helpers the tone suites
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
    /// Hue/saturation as TP-3 defines it (lead note on #432): standard HSL on
    /// the encoded values; hue rotates, saturation scales by 1 + s/100, and
    /// lightness blends toward white (positive) or black (negative).
    static func hueSaturationReference(_ p: RGBA, hue: Double, saturation: Double, lightness: Double) -> RGBA {
        guard p.a > 0 else { return p }
        var (h, s, l) = ToneCheck.hsl(ToneCheck.encoded(p))
        h = (h + hue + 360).truncatingRemainder(dividingBy: 360)
        s = min(1, max(0, s * (1 + saturation / 100)))
        l = lightness >= 0 ? l + (1 - l) * lightness / 100 : l * (1 + lightness / 100)
        return ToneCheck.pixel(ToneCheck.rgb(h: h, s: s, l: l), a: p.a)
    }

    @Test(.disabled("waits on TP-3")) func neutralIsIdentity() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xA1)
        #expect(try b.vibrance(0) == b)
        #expect(try b.hueSaturation(hue: 0, saturation: 0, lightness: 0) == b)
        #expect(try b.hsl(HSLAdjustment()) == b)
    }

    @Test(.disabled("waits on TP-3")) func lowSaturationMovesMost() throws {
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
    @Test(.disabled("waits on TP-3")) func skinMovesHalf() throws {
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

    @Test(.disabled("waits on TP-3")) func hueSaturationMatchesReference() throws {
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

    @Test(.disabled("waits on TP-3")) func blueRangeGreysBlueOnly() throws {
        let green = ToneCheck.pixel([0, 1, 0])
        let input = [ToneFixtures.pureBlue.pixel, ToneFixtures.pureRed.pixel, green]
        let out = try ToneCheck.pixels(ToneCheck.row(input).hsl(HSLAdjustment(blues: HSLShift(saturation: -100))))
        #expect(ToneCheck.spread(ToneCheck.encoded(out[0])) <= 1e-6)
        for (p, q) in zip(input.dropFirst(), out.dropFirst()) {
            #expect(ToneCheck.gap(q, p) <= 1e-6)
        }
    }

    /// Every range at -100 saturation greys every hue: the weights sum to 1.
    @Test(.disabled("waits on TP-3")) func rangeWeightsSumToOne() throws {
        let grey = HSLShift(saturation: -100)
        let all = HSLAdjustment(reds: grey, oranges: grey, yellows: grey, greens: grey, aquas: grey, blues: grey,
                                purples: grey, magentas: grey)
        for p in try ToneCheck.pixels(ToneCheck.seeded(width: 32, height: 16, seed: 0xA3, opaque: true).hsl(all)) {
            #expect(ToneCheck.spread(ToneCheck.encoded(p)) <= 1e-5, "\(p)")
        }
    }

    @Test(.disabled("waits on TP-3")) func alphaKept() throws {
        try ToneCheck.expectAlphaKept("vibrance") { try $0.vibrance(60) }
        try ToneCheck.expectAlphaKept("hueSaturation") { try $0.hueSaturation(hue: 40, saturation: 30, lightness: 10) }
        try ToneCheck.expectAlphaKept("hsl") { try $0.hsl(HSLAdjustment(reds: HSLShift(hue: 20, saturation: 30, lightness: 10))) }
    }

    @Test(.disabled("waits on TP-3")) func nanThrows() throws {
        let b = try ToneCheck.seeded(width: 2, height: 2, seed: 0xA4)
        #expect(throws: RasterError.self) { try b.vibrance(.nan) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: .nan, saturation: 0, lightness: 0) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 0, saturation: .nan, lightness: 0) }
        #expect(throws: RasterError.self) { try b.hueSaturation(hue: 0, saturation: 0, lightness: .nan) }
        #expect(throws: RasterError.self) { try b.hsl(HSLAdjustment(greens: HSLShift(hue: .nan))) }
    }
}
