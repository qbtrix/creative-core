// AlphaEffectTests.swift: effects-engine FX-5's stroke acceptance, written first
// (FX-1), disabled until FX-5 builds `stroked`: a 4 px stroke of a radius-16 disc
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

    @Test(.disabled("waits on FX-5")) func outsideStrokeIsOutside() throws { try expectRing(.outside, inner: 16, outer: 20) { $0 == 1 } }

    @Test(.disabled("waits on FX-5")) func insideStrokeIsInside() throws { try expectRing(.inside, inner: 12, outer: 16) { $0 == 0 } }

    @Test(.disabled("waits on FX-5")) func centerStrokeStraddlesEdge() throws { try expectRing(.center, inner: 14, outer: 18) { _ in false } }

    @Test(.disabled("waits on FX-5")) func zeroWidthIsIdentity() throws {
        let disc = try EffectFixtures.disc(size: 32, radius: 8)
        for position: StrokePosition in [.outside, .inside, .center] {
            #expect(try disc.stroked(color: blue, width: 0, position: position) == disc)
        }
    }

    @Test(.disabled("waits on FX-5")) func badWidthThrows() throws {
        let disc = try EffectFixtures.disc(size: 16, radius: 4)
        for bad in [2_000.0, 1_000.5, -1, .nan, .infinity] { #expect(throws: RasterError.self) { try disc.stroked(color: blue, width: bad, position: .outside) } }
    }

    @Test(.disabled("waits on FX-5")) func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0x57_80CE)
        let glyph = try EffectFixtures.glyphMask()
        let positions: [StrokePosition] = [.outside, .inside, .center]
        for i in 0..<200 {
            let width = EffectFuzz.value(&rng, in: 0...1_000)
            try EffectFuzz.expectThrowsOrKeepsSize(glyph) { try $0.stroked(color: blue, width: width, position: positions[i % 3]) }
        }
    }
}
