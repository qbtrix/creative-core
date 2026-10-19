// ColorMapTests.swift: tone-pack TP-5's acceptance for the maps, written first
// (TP-1 of docs/blueprints/core/features/tone-pack.md): gradientMap,
// posterized, thresholded and inverted.
import CoreRaster
import Testing

@Suite struct ColorMapTests {
    let black = RGBA(r: 0, g: 0, b: 0, a: 1), white = RGBA(r: 1, g: 1, b: 1, a: 1)

    @Test func blackToWhiteIsLuma() throws {
        let refs = ToneFixtures.references
        let map = [GradientMapStop(offset: 0, color: black), GradientMapStop(offset: 1, color: white)]
        let out = try ToneCheck.pixels(ToneCheck.row(refs.map(\.pixel)).gradientMap(map))
        for (c, q) in zip(refs, out) {
            let e = ToneCheck.encoded(q)
            #expect(abs(e.x - Double(c.luma)) <= 1e-5, "\(c.name)")
            #expect(ToneCheck.spread(e) <= 1e-5, "\(c.name)")
        }
    }

    /// Interpolation between arbitrary stops, the end colours held outside
    /// the first and last stop, and a hard edge where two offsets are equal.
    @Test func threeStopsInterpolateAndHold() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1), green = RGBA(r: 0, g: 1, b: 0, a: 1), blue = RGBA(r: 0, g: 0, b: 1, a: 1)
        let map = [GradientMapStop(offset: 0.25, color: red), GradientMapStop(offset: 0.5, color: green),
                   GradientMapStop(offset: 0.75, color: blue)]
        let greys: [Double] = [0.1, 0.9, 0.375]
        let out = try ToneCheck.pixels(ToneCheck.row(greys.map { ToneCheck.pixel(SIMD3(repeating: $0)) }).gradientMap(map))
        let want: [SIMD3<Double>] = [[1, 0, 0], [0, 0, 1], [0.5, 0.5, 0]]
        for (q, w) in zip(out, want) { #expect(ToneCheck.gap(ToneCheck.encoded(q), w) <= 1e-5, "\(q)") }

        let edge = [GradientMapStop(offset: 0, color: black), GradientMapStop(offset: 0.5, color: black),
                    GradientMapStop(offset: 0.5, color: white), GradientMapStop(offset: 1, color: white)]
        let sides = try ToneCheck.pixels(ToneCheck.row([0.49, 0.51].map { ToneCheck.pixel(SIMD3(repeating: $0)) })
            .gradientMap(edge)).map(ToneCheck.encoded)
        #expect(ToneCheck.gap(sides[0], [0, 0, 0]) <= 1e-6)
        #expect(ToneCheck.gap(sides[1], [1, 1, 1]) <= 1e-6)
    }

    /// Two levels give only 0 and 1, rounding to the nearer; four give thirds.
    @Test func posterizeTwoLevels() throws {
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

    /// Greys at 0.5 and 0.499 and a green of luma 0.5042 pin the split at luma 0.5, inclusive.
    @Test func thresholdOnLuma() throws {
        let green = ToneCheck.pixel([0, 1, 0])
        let input = [ToneFixtures.pureRed.pixel, green, ToneFixtures.saturated10.pixel, ToneFixtures.skinTone.pixel,
                     ToneCheck.pixel([0.5, 0.5, 0.5]), ToneCheck.pixel(SIMD3(repeating: 0.5 - 1e-3)),
                     ToneCheck.pixel([0, 0.705, 0])]
        let out = try ToneCheck.pixels(ToneCheck.row(input).thresholded(0.5)).map(ToneCheck.encoded)
        #expect(out.count == input.count)
        for (e, bright) in zip(out, [false, true, false, true, true, false, true]) {
            #expect(ToneCheck.gap(e, SIMD3(repeating: bright ? 1 : 0)) <= 1e-6, "\(e)")
        }
    }

    /// The level is Rec. 709 luma of the sRGB-encoded values, not linear
    /// luminance: a grey at linear 0.2 (encoded about 0.48) is white at 0.4
    /// and black at 0.5; a linear-luminance threshold would make it black at 0.4.
    @Test func thresholdIsOnEncodedLuma() throws {
        let grey = try ToneCheck.row([RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1)])
        let at40 = try ToneCheck.pixels(grey.thresholded(0.4)).map(ToneCheck.encoded)
        let at50 = try ToneCheck.pixels(grey.thresholded(0.5)).map(ToneCheck.encoded)
        #expect(at40.count == 1 && at50.count == 1)
        for e in at40 { #expect(ToneCheck.gap(e, [1, 1, 1]) <= 1e-6, "\(e)") }
        for e in at50 { #expect(ToneCheck.gap(e, [0, 0, 0]) <= 1e-6, "\(e)") }
    }

    /// Components on a 1/256 grid, so 1 − (1 − x) is exact in Float.
    @Test func invertTwiceIsIdentity() throws {
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

    /// a − c can overflow a finite pixel; the result stays finite.
    @Test func invertStaysFinite() throws {
        let out = try ToneCheck.pixels(ToneCheck.row([RGBA(r: -3e38, g: 0, b: 0, a: 3e38)]).inverted())
        #expect(out.allSatisfy { $0.r.isFinite && $0.g.isFinite && $0.b.isFinite && $0.a.isFinite }, "\(out)")
        #expect(out.first?.r == Float.greatestFiniteMagnitude)
    }

    /// An alpha-0 pixel passes through untouched, even with stored colour.
    @Test func invertLeavesAlphaZero() throws {
        let input = try ToneCheck.row([RGBA(r: 0.3, g: 0.2, b: 0.1, a: 0)])
        #expect(input.inverted() == input)
    }

    @Test func alphaKept() throws {
        let map = [GradientMapStop(offset: 0, color: black), GradientMapStop(offset: 1, color: white)]
        try ToneCheck.expectAlphaKept("gradientMap") { try $0.gradientMap(map) }
        try ToneCheck.expectAlphaKept("posterized") { try $0.posterized(levels: 3) }
        try ToneCheck.expectAlphaKept("thresholded") { try $0.thresholded(0.4) }
        try ToneCheck.expectAlphaKept("inverted") { $0.inverted() }
    }

    @Test func invalidParametersThrow() throws {
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
