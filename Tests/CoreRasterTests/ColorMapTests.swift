// ColorMapTests.swift: tone-pack TP-5's acceptance for the maps, written first
// (TP-1 of docs/blueprints/core/features/tone-pack.md): gradientMap,
// posterized, thresholded and inverted. Disabled until TP-5 lands.
import CoreRaster
import Testing

@Suite struct ColorMapTests {
    let black = RGBA(r: 0, g: 0, b: 0, a: 1), white = RGBA(r: 1, g: 1, b: 1, a: 1)

    @Test(.disabled("waits on TP-5")) func blackToWhiteIsLuma() throws {
        let refs = ToneFixtures.references
        let map = [GradientMapStop(offset: 0, color: black), GradientMapStop(offset: 1, color: white)]
        let out = try ToneCheck.pixels(ToneCheck.row(refs.map(\.pixel)).gradientMap(map))
        for (c, q) in zip(refs, out) {
            let e = ToneCheck.encoded(q)
            #expect(abs(e.x - Double(c.luma)) <= 1e-5, "\(c.name)")
            #expect(ToneCheck.spread(e) <= 1e-5, "\(c.name)")
        }
    }

    /// Two levels give only 0 and 1, rounding to the nearer; four give thirds.
    @Test(.disabled("waits on TP-5")) func posterizeTwoLevels() throws {
        let input = [ToneCheck.pixel([0.4, 0.6, 0.1]), ToneCheck.pixel([0.9, 0.25, 0.75])]
        let out = try ToneCheck.pixels(ToneCheck.row(input).posterized(levels: 2)).map(ToneCheck.encoded)
        #expect(ToneCheck.gap(out[0], [0, 1, 0]) <= 1e-5)
        #expect(ToneCheck.gap(out[1], [1, 0, 1]) <= 1e-5)
        for levels in [2, 4] {
            let steps = (0..<levels).map { Double($0) / Double(levels - 1) }
            let b = try ToneCheck.seeded(width: 16, height: 8, seed: 0xC1, opaque: true).posterized(levels: levels)
            for p in try ToneCheck.pixels(b) {
                let e = ToneCheck.encoded(p)
                for v in [e.x, e.y, e.z] { #expect(steps.contains { abs($0 - v) <= 1e-5 }, "\(v) at \(levels)") }
            }
        }
    }

    @Test(.disabled("waits on TP-5")) func thresholdOnLuma() throws {
        let green = ToneCheck.pixel([0, 1, 0])
        let input = [ToneFixtures.pureRed.pixel, green, ToneFixtures.saturated10.pixel, ToneFixtures.skinTone.pixel]
        let out = try ToneCheck.pixels(ToneCheck.row(input).thresholded(0.5)).map(ToneCheck.encoded)
        for (e, bright) in zip(out, [false, true, false, true]) {
            #expect(ToneCheck.gap(e, SIMD3(repeating: bright ? 1 : 0)) <= 1e-6, "\(e)")
        }
    }

    /// Components on a 1/256 grid, so 1 − (1 − x) is exact in Float.
    @Test(.disabled("waits on TP-5")) func invertTwiceIsIdentity() throws {
        var rng = SplitMix64(seed: 0xC2)
        let input = try ToneCheck.row((0..<64).map { _ in
            let a = Float(Int.random(in: 1...256, using: &rng)) / 256
            func c() -> Float { Float(Int.random(in: 0...256, using: &rng)) / 256 * a }
            return RGBA(r: c(), g: c(), b: c(), a: a)
        })
        #expect(input.inverted().inverted() == input)
        let red = ToneCheck.encoded(try ToneCheck.pixels(ToneCheck.row([ToneFixtures.pureRed.pixel]).inverted())[0])
        #expect(ToneCheck.gap(red, [0, 1, 1]) <= 1e-6)
    }

    @Test(.disabled("waits on TP-5")) func alphaKept() throws {
        let map = [GradientMapStop(offset: 0, color: black), GradientMapStop(offset: 1, color: white)]
        try ToneCheck.expectAlphaKept("gradientMap") { try $0.gradientMap(map) }
        try ToneCheck.expectAlphaKept("posterized") { try $0.posterized(levels: 3) }
        try ToneCheck.expectAlphaKept("thresholded") { try $0.thresholded(0.4) }
        try ToneCheck.expectAlphaKept("inverted") { $0.inverted() }
    }

    @Test(.disabled("waits on TP-5")) func invalidParametersThrow() throws {
        let b = try ToneCheck.seeded(width: 2, height: 2, seed: 0xC3)
        let low = GradientMapStop(offset: 0, color: black), high = GradientMapStop(offset: 1, color: white)
        #expect(throws: RasterError.self) { try b.thresholded(.nan) }
        #expect(throws: RasterError.self) { try b.posterized(levels: 1) }
        #expect(throws: RasterError.self) { try b.posterized(levels: 256) }
        #expect(throws: RasterError.self) { try b.gradientMap([low]) }
        #expect(throws: RasterError.self) { try b.gradientMap([high, low]) }
        #expect(throws: RasterError.self) { try b.gradientMap([GradientMapStop(offset: .nan, color: black), high]) }
    }
}
