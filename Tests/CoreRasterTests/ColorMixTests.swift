// ColorMixTests.swift: tone-pack TP-4's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md): blackAndWhite, channelMixer and
// colorBalance. Disabled until TP-4 lands. Grays and luma are on the encoded
// values, as ToneFixtures states them.
import CoreRaster
import Testing

@Suite struct ColorMixTests {
    let identity = ChannelMatrix(red: [1, 0, 0, 0], green: [0, 1, 0, 0], blue: [0, 0, 1, 0], monochrome: false)

    @Test(.disabled("waits on TP-4")) func neutralIsIdentity() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB1)
        #expect(try b.channelMixer(identity) == b)
        #expect(try b.colorBalance(ToneBalance(shadows: .zero, midtones: .zero, highlights: .zero,
                                               preserveLuminosity: false)) == b)
    }

    /// Default mix: pure red is the reds weight (40%), pure blue the blues weight (20%).
    @Test(.disabled("waits on TP-4")) func redWeightIsForty() throws {
        for c in [ToneFixtures.pureRed, ToneFixtures.pureBlue] {
            let gray = ToneCheck.encoded(try ToneCheck.pixels(ToneCheck.row([c.pixel]).blackAndWhite(GrayMix()))[0])
            #expect(abs(gray.x - Double(c.grayDefault ?? -1)) <= 1e-5, "\(c.name)")
            #expect(ToneCheck.spread(gray) <= 1e-6, "\(c.name)")
        }
    }

    @Test(.disabled("waits on TP-4")) func monochromeWritesOneGray() throws {
        let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xB2, opaque: true)
        let m = ChannelMatrix(red: [0.3, 0.6, 0.1, 0], green: [1, 0, 0, 0], blue: [0, 0, 1, 0], monochrome: true)
        for (p, q) in zip(try ToneCheck.pixels(b), try ToneCheck.pixels(b.channelMixer(m))) {
            #expect(q.r == q.g && q.g == q.b, "\(q)")
            #expect(abs(q.r - (0.3 * p.r + 0.6 * p.g + 0.1 * p.b)) <= 1e-6, "\(p)")
        }
    }

    @Test(.disabled("waits on TP-4")) func whiteUnmovedByShadows() throws {
        let balance = ToneBalance(shadows: [100, 0, 0], midtones: .zero, highlights: .zero, preserveLuminosity: false)
        let input = [ToneCheck.pixel([1, 1, 1]), ToneCheck.pixel([0.95, 0.95, 0.95]), ToneCheck.pixel([0.1, 0.1, 0.1])]
        let out = try ToneCheck.pixels(ToneCheck.row(input).colorBalance(balance))
        for (p, q) in zip(input.prefix(2), out.prefix(2)) {
            #expect(ToneCheck.gap(q, p) <= 1e-6)
        }
        let dark = ToneCheck.encoded(out[2])
        #expect(dark.x > dark.y + 1e-3)
    }

    @Test(.disabled("waits on TP-4")) func preserveKeepsLuma() throws {
        var rng = SplitMix64(seed: 0xB3)
        let input = (0..<64).map { _ in
            ToneCheck.pixel(SIMD3((0..<3).map { _ in Double.random(in: 0.2...0.8, using: &rng) }))
        }
        let balance = ToneBalance(shadows: [30, -10, 0], midtones: [0, 20, -20], highlights: [-15, 0, 25],
                                  preserveLuminosity: true)
        let out = try ToneCheck.pixels(ToneCheck.row(input).colorBalance(balance))
        for (p, q) in zip(input, out) {
            #expect(abs(ToneCheck.luma(ToneCheck.encoded(q)) - ToneCheck.luma(ToneCheck.encoded(p))) <= 1e-5, "\(p)")
        }
        #expect(zip(input, out).contains { abs($0.r - $1.r) > 1e-3 })
    }

    @Test(.disabled("waits on TP-4")) func alphaKept() throws {
        let tint = GrayMix(tint: RGBA(r: 0.9, g: 0.6, b: 0.3, a: 0.5))
        let mix = ChannelMatrix(red: [0.8, 0.2, 0, 0], green: [0, 1, 0, 0.05], blue: [0.1, 0, 0.9, 0], monochrome: false)
        let balance = ToneBalance(shadows: [20, 0, -20], midtones: [0, 10, 0], highlights: [0, 0, 30], preserveLuminosity: true)
        try ToneCheck.expectAlphaKept("blackAndWhite") { try $0.blackAndWhite(tint) }
        try ToneCheck.expectAlphaKept("channelMixer") { try $0.channelMixer(mix) }
        try ToneCheck.expectAlphaKept("colorBalance") { try $0.colorBalance(balance) }
    }

    @Test(.disabled("waits on TP-4")) func nanThrows() throws {
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
}
