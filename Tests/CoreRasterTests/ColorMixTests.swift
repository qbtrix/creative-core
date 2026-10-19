// ColorMixTests.swift: tone-pack TP-4's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md): blackAndWhite, channelMixer and
// colorBalance. Grays and luma are on the encoded
// values, as ToneFixtures states them.
import CoreRaster
import Testing

@Suite struct ColorMixTests {
    let identity = ChannelMatrix(red: [1, 0, 0, 0], green: [0, 1, 0, 0], blue: [0, 0, 1, 0], monochrome: false)

    @Test func neutralIsIdentity() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB1)
        #expect(try b.channelMixer(identity) == b)
        #expect(try b.colorBalance(ToneBalance(shadows: .zero, midtones: .zero, highlights: .zero,
                                               preserveLuminosity: false)) == b)
    }

    /// Default mix: pure red is the reds weight (40%), pure blue the blues weight (20%).
    @Test func redWeightIsForty() throws {
        for c in [ToneFixtures.pureRed, ToneFixtures.pureBlue] {
            let gray = ToneCheck.encoded(try ToneCheck.pixels(ToneCheck.row([c.pixel]).blackAndWhite(GrayMix()))[0])
            #expect(abs(gray.x - Double(c.grayDefault ?? -1)) <= 1e-5, "\(c.name)")
            #expect(ToneCheck.spread(gray) <= 1e-6, "\(c.name)")
        }
    }

    @Test func monochromeWritesOneGray() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB2, opaque: true)
        let m = ChannelMatrix(red: [0.3, 0.6, 0.1, 0], green: [1, 0, 0, 0], blue: [0, 0, 1, 0], monochrome: true)
        for (p, q) in zip(try ToneCheck.pixels(b), try ToneCheck.pixels(b.channelMixer(m))) {
            #expect(q.r == q.g && q.g == q.b, "\(q)")
            #expect(abs(q.r - (0.3 * p.r + 0.6 * p.g + 0.1 * p.b)) <= 1e-6, "\(p)")
        }
    }

    @Test func whiteUnmovedByShadows() throws {
        let balance = ToneBalance(shadows: [100, 0, 0], midtones: .zero, highlights: .zero, preserveLuminosity: false)
        let input = [ToneCheck.pixel([1, 1, 1]), ToneCheck.pixel([0.95, 0.95, 0.95]), ToneCheck.pixel([0.1, 0.1, 0.1])]
        let out = try ToneCheck.pixels(ToneCheck.row(input).colorBalance(balance))
        for (p, q) in zip(input.prefix(2), out.prefix(2)) {
            #expect(ToneCheck.gap(q, p) <= 1e-6)
        }
        let dark = ToneCheck.encoded(out[2])
        #expect(dark.x > dark.y + 1e-3)
    }

    /// Inputs span the whole 0...1 range, channels at 1 included, where the
    /// scaled result would leave 0...1 and a plain clamp would lose luma.
    @Test func preserveKeepsLuma() throws {
        var rng = SplitMix64(seed: 0xB3)
        var colors: [SIMD3<Double>] = (0..<64).map { _ in SIMD3((0..<3).map { _ in Double.random(in: 0...1, using: &rng) }) }
        colors += (0..<16).map { i in
            var c = SIMD3((0..<3).map { _ in Double.random(in: 0...1, using: &rng) })
            c[i % 3] = 1
            return c
        }
        colors += [[1, 1, 0.2], [1, 1, 1], [0, 0, 0]]
        let input = colors.map { ToneCheck.pixel($0) }
        let balances = [
            ToneBalance(shadows: [30, -10, 0], midtones: [0, 20, -20], highlights: [-15, 0, 25], preserveLuminosity: true),
            ToneBalance(shadows: .zero, midtones: .zero, highlights: [0, 0, -100], preserveLuminosity: true),
        ]
        for balance in balances {
            let out = try ToneCheck.pixels(ToneCheck.row(input).colorBalance(balance))
            for (p, q) in zip(input, out) {
                #expect(abs(ToneCheck.luma(ToneCheck.encoded(q)) - ToneCheck.luma(ToneCheck.encoded(p))) <= 1e-5, "\(p)")
            }
            #expect(zip(input, out).contains { abs($0.b - $1.b) > 1e-3 })
        }
    }

    /// One zone's shift of `d` on a grey of encoded value `v`, from the
    /// documented formula: s = weight × d / 200, toward 1 by s × (1 − v) when
    /// positive, toward 0 by |s| × v when negative.
    static func zoneShift(_ v: Double, _ d: Double, zone: (Double) -> Double) -> Double {
        let s = zone(v) * d / 200
        return v + s * (s > 0 ? 1 - v : v)
    }

    static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    @Test func highlightsAndMidtonesByZone() throws {
        let grays: [Double] = [0, 0.1, 0.5, 0.95, 1]
        let input = grays.map { ToneCheck.pixel(SIMD3(repeating: $0)) }
        func red(_ balance: ToneBalance) throws -> [Double] {
            try ToneCheck.pixels(ToneCheck.row(input).colorBalance(balance)).map { ToneCheck.encoded($0).x }
        }
        let high: (Double) -> Double = { Self.smoothstep(0.66, 1, $0) }
        let shadow: (Double) -> Double = { 1 - Self.smoothstep(0, 0.33, $0) }
        let mid: (Double) -> Double = { 1 - shadow($0) - high($0) }
        let highlit = try red(ToneBalance(shadows: .zero, midtones: .zero, highlights: [100, 0, 0], preserveLuminosity: false))
        let midtoned = try red(ToneBalance(shadows: .zero, midtones: [100, 0, 0], highlights: .zero, preserveLuminosity: false))
        let shadowed = try red(ToneBalance(shadows: [-100, 0, 0], midtones: .zero, highlights: .zero, preserveLuminosity: false))
        for (i, v) in grays.enumerated() {
            #expect(abs(highlit[i] - Self.zoneShift(v, 100, zone: high)) <= 1e-5, "highlights at \(v)")
            #expect(abs(midtoned[i] - Self.zoneShift(v, 100, zone: mid)) <= 1e-5, "midtones at \(v)")
            #expect(abs(shadowed[i] - Self.zoneShift(v, -100, zone: shadow)) <= 1e-5, "shadows at \(v)")
        }
        #expect(abs(highlit[0]) <= 1e-6 && highlit[3] > 0.95 + 1e-3)
        #expect(abs(midtoned[2] - 0.75) <= 1e-5 && abs(midtoned[0]) <= 1e-6 && abs(midtoned[4] - 1) <= 1e-6)
        #expect(shadowed[1] < 0.1 - 1e-3 && shadowed[1] > 0)
    }

    @Test func matrixRowsAndConstant() throws {
        let m = ChannelMatrix(red: [0.5, 0.5, 0, 0.1], green: [0, 0, 1, 0], blue: [0, 1, 0, 0], monochrome: false)
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB5, opaque: true)
        for (p, q) in zip(try ToneCheck.pixels(b), try ToneCheck.pixels(b.channelMixer(m))) {
            let v = SIMD4(p.r, p.g, p.b, 1)
            for (row, got) in [(m.red, q.r), (m.green, q.g), (m.blue, q.b)] {
                #expect(abs(got - min(max((row * v).sum(), 0), 1)) <= 1e-6, "\(p)")
            }
        }
        let bright = try ToneCheck.pixels(ToneCheck.row([RGBA(r: 1, g: 1, b: 0, a: 1)]).channelMixer(m))[0]
        #expect(bright.r == 1)
    }

    @Test func betweenRangesAndTint() throws {
        // Hue 30 sits halfway between reds (40%) and yellows (60%): w = 0.5 on max − min = 1.
        let orange = ToneCheck.pixel([1, 0.5, 0])
        let gray = ToneCheck.encoded(try ToneCheck.pixels(ToneCheck.row([orange]).blackAndWhite(GrayMix()))[0])
        #expect(abs(gray.x - 0.5) <= 1e-5 && ToneCheck.spread(gray) <= 1e-6)

        // W3C soft-light B(cb, cs).
        func softLight(_ cb: Double, _ cs: Double) -> Double {
            if cs <= 0.5 { return cb - (1 - 2 * cs) * cb * (1 - cb) }
            let d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : cb.squareRoot()
            return cb + (2 * cs - 1) * (d - cb)
        }
        let grey = try ToneCheck.row([ToneCheck.pixel([0.5, 0.5, 0.5])])
        let tint: SIMD3<Double> = [0.9, 0.6, 0.3]
        for a in [1.0, 0.5] {
            let mix = GrayMix(tint: RGBA(r: Float(tint.x), g: Float(tint.y), b: Float(tint.z), a: Float(a)))
            let out = ToneCheck.encoded(try ToneCheck.pixels(grey.blackAndWhite(mix))[0])
            let want = SIMD3((0..<3).map { 0.5 + (softLight(0.5, tint[$0]) - 0.5) * a })
            #expect(ToneCheck.gap(out, want) <= 1e-5, "alpha \(a)")
            #expect(out.x > out.y + 1e-3 && out.y > out.z + 1e-3, "alpha \(a)")
        }

        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB6, opaque: true)
        #expect(try b.blackAndWhite(GrayMix(reds: 500)) == b.blackAndWhite(GrayMix(reds: 300)))
    }

    @Test func alphaKept() throws {
        let tint = GrayMix(tint: RGBA(r: 0.9, g: 0.6, b: 0.3, a: 0.5))
        let mix = ChannelMatrix(red: [0.8, 0.2, 0, 0], green: [0, 1, 0, 0.05], blue: [0.1, 0, 0.9, 0], monochrome: false)
        let balance = ToneBalance(shadows: [20, 0, -20], midtones: [0, 10, 0], highlights: [0, 0, 30], preserveLuminosity: true)
        try ToneCheck.expectAlphaKept("blackAndWhite") { try $0.blackAndWhite(tint) }
        try ToneCheck.expectAlphaKept("channelMixer") { try $0.channelMixer(mix) }
        try ToneCheck.expectAlphaKept("colorBalance") { try $0.colorBalance(balance) }
    }

    @Test func nanThrows() throws {
        let b = try ToneCheck.seeded(width: 2, height: 2, seed: 0xB4)
        let nan = Float.nan
        #expect(throws: RasterError.self) { try b.blackAndWhite(GrayMix(reds: nan)) }
        #expect(throws: RasterError.self) {
            try b.channelMixer(ChannelMatrix(red: [nan, 0, 0, 0], green: [0, 1, 0, 0], blue: [0, 0, 1, 0], monochrome: false))
        }
        #expect(throws: RasterError.self) {
            try b.colorBalance(ToneBalance(shadows: [nan, 0, 0], midtones: .zero, highlights: .zero, preserveLuminosity: false))
        }
    }

    /// A non-finite parameter's error names its field.
    @Test func nanNamesField() throws {
        let b = try ToneCheck.seeded(width: 2, height: 2, seed: 0xB4)
        let nan = Float.nan
        func message(_ op: () throws -> PixelBuffer) -> String {
            do { _ = try op() } catch let RasterError.invalid(why) { return why } catch { return "\(error)" }
            return ""
        }
        #expect(message {
            try b.channelMixer(ChannelMatrix(red: [1, 0, 0, 0], green: [0, nan, 0, 0], blue: [0, 0, 1, 0], monochrome: false))
        }.contains("green"))
        #expect(message {
            try b.colorBalance(ToneBalance(shadows: .zero, midtones: .zero, highlights: [0, nan, 0], preserveLuminosity: false))
        }.contains("highlights"))
        #expect(message { try b.blackAndWhite(GrayMix(yellows: nan)) }.contains("yellows"))
    }
}
