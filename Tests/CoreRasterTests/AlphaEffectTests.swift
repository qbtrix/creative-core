// AlphaEffectTests.swift: effects-engine FX-5's stroke acceptance, written first
// (FX-1), on since FX-5 built `stroked`: a 4 px stroke of a radius-16 disc
// covers 16...20 outside, 12...16 inside, 14...18 centred, area within 1%. Glow
// and shadow are FX-6's own suite, `AlphaEffectLightTests`.
import CoreRaster
import Testing

@Suite struct AlphaEffectTests {
    let blue = RGBA(r: 0, g: 0, b: 1, a: 1)

    /// The stroke's visible area: a white layer has r == b, a blue stroke adds
    /// only to b, so b - r is the stroke's coverage left showing at a pixel.
    func strokePaint(_ b: PixelBuffer) throws -> Double {
        var sum = 0.0
        for y in 0..<b.height { for x in 0..<b.width { sum += Double(try b.pixel(x: x, y: y).b - b.pixel(x: x, y: y).r) } }
        return sum
    }

    /// The 4 px `position` stroke of a radius-16 disc shows over the ring
    /// `inner...outer` (area within 1%) and leaves every pixel whose layer
    /// alpha passes `untouched` exactly as it was.
    func expectRing(_ position: StrokePosition, inner: Double, outer: Double, untouched: (Float) -> Bool) throws {
        let disc = try EffectFixtures.disc(size: 64, radius: 16)
        let out = try disc.stroked(color: blue, width: 4, position: position)
        let painted = try strokePaint(out), ring = EffectFixtures.ringArea(inner: inner, outer: outer)
        #expect(abs(painted - ring) / ring <= 0.01, "\(position): \(painted) px against \(ring)")
        for y in 0..<64 {
            for x in 0..<64 where untouched(try disc.pixel(x: x, y: y).a) {
                #expect(try out.pixel(x: x, y: y) == disc.pixel(x: x, y: y), "\(position) stroke shows at (\(x), \(y))")
            }
        }
    }

    @Test func outsideStrokeIsOutside() throws {
        try expectRing(.outside, inner: 16, outer: 20) { $0 == 1 }
        // The far side is a one-pixel smoothstep ramp, not a hard step: some
        // pixels about 20 px from the centre are partly covered.
        let out = try EffectFixtures.disc(size: 64, radius: 16).stroked(color: blue, width: 4, position: .outside)
        var partial = 0
        for y in 0..<64 {
            for x in 0..<64 {
                let r = ((Double(x) - 31.5) * (Double(x) - 31.5) + (Double(y) - 31.5) * (Double(y) - 31.5)).squareRoot()
                let cover = try out.pixel(x: x, y: y).b
                if abs(r - 20) < 0.5, cover > 0.05, cover < 0.95 { partial += 1 }
            }
        }
        #expect(partial >= 8, "\(partial) partly covered pixels on the far edge")
    }

    /// The stroke measures to the anti-aliased edge, not to pixel centres: a
    /// vertical edge column of alpha 0.75 sits a quarter pixel further out
    /// than one of 0.25 by half a pixel each way, so a 4 px outside stroke
    /// 4 px past that column covers about 0.84 and 0.16 (smoothstep of
    /// 4.5 - 3.75 and 4.5 - 4.25), where a pixel-centre field gives 0.5 and 0.
    @Test func strokeMeasuresAntiAliasedEdge() throws {
        for (edgeAlpha, want) in [(Float(0.75), Float(0.84375)), (0.25, 0.15625)] {
            var b = try PixelBuffer(width: 24, height: 24)
            for y in 0..<24 {
                for x in 0..<8 { try b.setPixel(x: x, y: y, RGBA(r: 1, g: 1, b: 1, a: 1)) }
                try b.setPixel(x: 8, y: y, RGBA(r: edgeAlpha, g: edgeAlpha, b: edgeAlpha, a: edgeAlpha))
            }
            let cover = try b.stroked(color: blue, width: 4, position: .outside).pixel(x: 12, y: 12).b
            #expect(abs(cover - want) < 0.02, "edge alpha \(edgeAlpha): cover \(cover)")
        }
    }

    /// The anti-aliased edge measure holds off-axis too, through the edge
    /// offset's corner branches: the half-plane x + y <= 24.5 (pixel area
    /// coordinates) gives its two diagonal edge rows alpha 0.125 and 0.875,
    /// and a pixel whose centre is a distance d from the line has outside
    /// stroke cover smoothstep(w + 0.5 - d). Pixel centres or the linear
    /// branch alone miss it by more than 0.02.
    @Test func strokeMeasuresDiagonalAntiAliasedEdge() throws {
        let k = 24.5, size = 40
        var b = try PixelBuffer(width: size, height: size)
        for y in 0..<size {
            for x in 0..<size {
                // Area of the unit pixel [x, x + 1] x [y, y + 1] with X + Y <= k.
                let t = k - Double(x + y)
                let a = t <= 0 ? 0 : t <= 1 ? t * t / 2 : t <= 2 ? 1 - (2 - t) * (2 - t) / 2 : 1
                let f = Float(a)
                try b.setPixel(x: x, y: y, RGBA(r: f, g: f, b: f, a: f))
            }
        }
        #expect(try b.pixel(x: 12, y: 12).a == 0.125 && b.pixel(x: 12, y: 11).a == 0.875)
        for w in [3.0, 3.5, 4.0, 4.5] {
            let out = try b.stroked(color: blue, width: w, position: .outside)
            var probed = 0
            for x in 12...16 {
                for y in 12...24 {
                    let d = (Double(x + y) + 1 - k) / 2.0.squareRoot()
                    let t = min(max(w + 0.5 - d, 0), 1), want = t * t * (3 - 2 * t)
                    guard want > 0.05, want < 0.95 else { continue }
                    probed += 1
                    let cover = try out.pixel(x: x, y: y).b
                    #expect(abs(Double(cover) - want) < 0.02, "width \(w) at (\(x), \(y)): cover \(cover), want \(want)")
                }
            }
            #expect(probed > 0, "width \(w): no pixel on the ramp")
        }
    }

    /// A radius is not the same reach everywhere (`LayerEffect`'s doc): box
    /// blur's is per pass, so a 1 px dot spreads past 25 px at radius 10,
    /// while a glow of radius 10 reaches only about 10 px.
    @Test func boxBlurRadiusIsPerPassGlowRadiusIsReach() throws {
        var dot = try PixelBuffer(width: 81, height: 81)
        try dot.setPixel(x: 40, y: 40, RGBA(r: 1, g: 1, b: 1, a: 1))
        #expect(try dot.boxBlurred(radius: 10).pixel(x: 65, y: 40).a > 0)
        let glow = try dot.glowing(color: blue, radius: 10, intensity: 1, inner: false)
        #expect(try glow.pixel(x: 65, y: 40).a == 0 && glow.pixel(x: 45, y: 40).a > 0)
    }

    @Test func insideStrokeIsInside() throws { try expectRing(.inside, inner: 12, outer: 16) { $0 == 0 } }

    @Test func centerStrokeStraddlesEdge() throws { try expectRing(.center, inner: 14, outer: 18) { _ in false } }

    @Test func zeroWidthIsIdentity() throws {
        let disc = try EffectFixtures.disc(size: 32, radius: 8)
        for position: StrokePosition in [.outside, .inside, .center] {
            #expect(try disc.stroked(color: blue, width: 0, position: position) == disc)
        }
    }

    @Test func badWidthThrows() throws {
        let disc = try EffectFixtures.disc(size: 16, radius: 4)
        for bad in [2_000.0, 1_000.5, -1, .nan, .infinity] { #expect(throws: RasterError.self) { try disc.stroked(color: blue, width: bad, position: .outside) } }
    }

    @Test func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0x57_80CE)
        let glyph = try EffectFixtures.glyphMask()
        let positions: [StrokePosition] = [.outside, .inside, .center]
        for i in 0..<200 {
            let width = EffectFuzz.value(&rng, in: 0...1_000)
            try EffectFuzz.expectThrowsOrKeepsSize(glyph) { try $0.stroked(color: blue, width: width, position: positions[i % 3]) }
        }
    }
}
