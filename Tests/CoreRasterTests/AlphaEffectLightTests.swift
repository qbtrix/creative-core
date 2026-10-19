// AlphaEffectLightTests.swift: effects-engine FX-6's glow and shadow
// acceptance: a drop shadow's centroid moves by (dx, dy), +y down; an inner
// shadow or glow never paints outside the layer's alpha; an outer glow or
// shadow never changes an opaque pixel; intensity 0 is identity; bad inputs
// throw naming the field, and a huge offset reads as off the canvas.
import CoreRaster
import Testing

@Suite struct AlphaEffectLightTests {
    let shade = RGBA(r: 0, g: 0, b: 0, a: 0.6)
    let gold = RGBA(r: 0.8, g: 0.6, b: 0, a: 0.8)

    /// The shadow alone: the alpha the effect added at each pixel.
    func addedAlpha(_ out: PixelBuffer, over layer: PixelBuffer) throws -> PixelBuffer {
        var added = try PixelBuffer(width: layer.width, height: layer.height)
        for y in 0..<layer.height {
            for x in 0..<layer.width {
                let a = try out.pixel(x: x, y: y).a - layer.pixel(x: x, y: y).a
                try added.setPixel(x: x, y: y, RGBA(r: 0, g: 0, b: 0, a: a))
            }
        }
        return added
    }

    /// Every pixel of `layer` passing `untouched` is exactly the same in `out`,
    /// and `out` differs from `layer` somewhere.
    func expectOnly(_ out: PixelBuffer, _ layer: PixelBuffer, _ label: String, untouched: (Float) -> Bool) throws {
        #expect(out != layer, "\(label) painted nothing")
        for y in 0..<layer.height {
            for x in 0..<layer.width where untouched(try layer.pixel(x: x, y: y).a) {
                #expect(try out.pixel(x: x, y: y) == layer.pixel(x: x, y: y), "\(label) paints at (\(x), \(y))")
            }
        }
    }

    @Test func shadowMovesDown() throws {
        // A radius-5 disc and a shadow at least 14 px away never overlap, so
        // the added alpha is the whole shadow and its centroid is the disc's
        // moved by the offset.
        let disc = try EffectFixtures.disc(size: 64, radius: 5)
        var rng = SplitMix64(seed: 0xF6_5AD0)
        var offsets: [(Double, Double)] = [(0, 14), (10, 12), (-11.5, 10.25)]
        for _ in 0..<4 {
            let sx: Double = Bool.random(using: &rng) ? 1 : -1, sy: Double = Bool.random(using: &rng) ? 1 : -1
            offsets.append((sx * .random(in: 10...14, using: &rng), sy * .random(in: 10...14, using: &rng)))
        }
        for (dx, dy) in offsets {
            let out = try disc.shadowed(color: shade, dx: dx, dy: dy, blur: 2, inner: false)
            let c = try #require(try EffectFixtures.centroid(addedAlpha(out, over: disc)))
            #expect(abs(c.x - (31.5 + dx)) < 0.01 && abs(c.y - (31.5 + dy)) < 0.01, "(\(dx), \(dy)) -> \(c)")
        }
    }

    @Test func innerStaysInside() throws {
        let disc = try EffectFixtures.disc(size: 64, radius: 16), glyph = try EffectFixtures.glyphMask()
        for layer in [disc, glyph] {
            try expectOnly(layer.shadowed(color: shade, dx: 3, dy: 4, blur: 4, inner: true), layer, "inner shadow") { $0 == 0 }
            try expectOnly(layer.glowing(color: gold, radius: 5, intensity: 1, inner: true), layer, "inner glow") { $0 == 0 }
        }
    }

    @Test func outerNeverCoversOpaque() throws {
        let glyph = try EffectFixtures.glyphMask()
        try expectOnly(glyph.glowing(color: gold, radius: 6, intensity: 1, inner: false), glyph, "outer glow") { $0 == 1 }
        try expectOnly(glyph.shadowed(color: shade, dx: 2, dy: 3, blur: 3, inner: false), glyph, "drop shadow") { $0 == 1 }
    }

    @Test func intensityZeroIsIdentity() throws {
        let disc = try EffectFixtures.disc(size: 32, radius: 10)
        for inner in [false, true] {
            #expect(try disc.glowing(color: gold, radius: 8, intensity: 0, inner: inner) == disc)
        }
    }

    @Test func glowAndShadowStayInTheirRanges() throws {
        let disc = try EffectFixtures.disc(size: 32, radius: 10)
        let out = try disc.glowing(color: gold, radius: 1_000, intensity: 1, inner: false)
        #expect(out.width == 32 && out.height == 32)
        // A glow is a convex mix: alpha never passes 1.
        for y in 0..<32 { for x in 0..<32 { #expect(try (0...1.0001).contains(out.pixel(x: x, y: y).a)) } }
    }

    @Test func badInputsThrowNamingTheField() throws {
        let disc = try EffectFixtures.disc(size: 16, radius: 4)
        #expect(throws: RasterError.invalid("glow radius 1001.0: must be finite and in 0...1000")) {
            try disc.glowing(color: gold, radius: 1_001, intensity: 1, inner: false)
        }
        #expect(throws: RasterError.invalid("glow intensity 1.5: must be finite and in 0...1")) {
            try disc.glowing(color: gold, radius: 2, intensity: 1.5, inner: true)
        }
        #expect(throws: RasterError.invalid("glow intensity nan: must be finite and in 0...1")) {
            try disc.glowing(color: gold, radius: 2, intensity: .nan, inner: true)
        }
        #expect(throws: RasterError.invalid("shadow blur -1.0: must be finite and in 0...1000")) {
            try disc.shadowed(color: shade, dx: 1, dy: 1, blur: -1, inner: false)
        }
        #expect(throws: RasterError.invalid("shadow offset (inf, 0.0): dx and dy must be finite")) {
            try disc.shadowed(color: shade, dx: .infinity, dy: 0, blur: 1, inner: false)
        }
        let bad = RGBA(r: .nan, g: 0, b: 0, a: 1)
        #expect(throws: RasterError.self) { try disc.glowing(color: bad, radius: 2, intensity: 1, inner: false) }
        #expect(throws: RasterError.self) { try disc.shadowed(color: bad, dx: 0, dy: 0, blur: 2, inner: true) }
    }

    @Test func hugeOffsetFallsOffTheCanvas() throws {
        let disc = try EffectFixtures.disc(size: 16, radius: 4)
        #expect(try disc.shadowed(color: shade, dx: 1e300, dy: -1e300, blur: 3, inner: false) == disc)
        // Inner: the offset inverse alpha reads as fully covered, so the whole shape is shaded.
        let inner = try disc.shadowed(color: shade, dx: -1e300, dy: 1e300, blur: 3, inner: true)
        let centre = try inner.pixel(x: 8, y: 8)
        #expect(abs(centre.r - 0.4) < 1e-6 && centre.a == 1)
    }
}
