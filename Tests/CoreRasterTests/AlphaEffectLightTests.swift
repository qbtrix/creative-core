// AlphaEffectLightTests.swift: effects-engine FX-6's glow and shadow
// acceptance: a drop shadow's centroid moves by (dx, dy), +y down; an inner
// shadow or glow never paints outside the layer's alpha; an outer glow or
// shadow never changes an opaque pixel; intensity 0 and a clear shadow are
// identity; intensity scales the glow; the glow reaches its radius; an offset
// pulls in blur past the edge; bad inputs throw naming the field, a huge offset
// reads as off the canvas, a buffer too large to pad names the effect, and
// seeded fuzz never crashes.
@testable import CoreRaster
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
            // A clear shadow colour has opacity 0: nothing changes either.
            let clear = RGBA(r: 0, g: 0, b: 0, a: 0)
            #expect(try disc.shadowed(color: clear, dx: 3, dy: 4, blur: 6, inner: inner) == disc)
        }
    }

    @Test func intensityScalesGlow() throws {
        // Outside the layer the glow's alpha is linear in the intensity.
        let disc = try EffectFixtures.disc(size: 32, radius: 10)
        let half = try addedAlpha(disc.glowing(color: gold, radius: 8, intensity: 0.5, inner: false), over: disc)
        let full = try addedAlpha(disc.glowing(color: gold, radius: 8, intensity: 1, inner: false), over: disc)
        var lit = 0
        for y in 0..<32 {
            for x in 0..<32 where try disc.pixel(x: x, y: y).a == 0 {
                let h = try half.pixel(x: x, y: y).a, f = try full.pixel(x: x, y: y).a
                if f > 0 { lit += 1 }
                #expect(abs(h - f / 2) <= 1e-5, "(\(x), \(y)): \(h) at 0.5, \(f) at 1")
            }
        }
        #expect(lit > 0)
    }

    @Test func glowReachesItsRadius() throws {
        // The radius-5 disc covers columns and rows 27...36 (centre 31.5). A
        // glow of radius 12 adds alpha 11.5 px past that edge and none from 13 px on.
        let disc = try EffectFixtures.disc(size: 64, radius: 5)
        let added = try addedAlpha(disc.glowing(color: gold, radius: 12, intensity: 1, inner: false), over: disc)
        for (x, y) in [(48, 31), (48, 32), (15, 31), (15, 32), (31, 48), (32, 48), (31, 15), (32, 15)] {
            #expect(try added.pixel(x: x, y: y).a > 0, "no glow at (\(x), \(y))")
        }
        for y in 0..<64 {
            for x in 0..<64 where max(abs(Double(x) - 31.5), abs(Double(y) - 31.5)) - 5 >= 13 {
                #expect(try added.pixel(x: x, y: y).a == 0, "glow at (\(x), \(y))")
            }
        }
    }

    @Test func offsetPullsInBlurPastTheEdge() throws {
        // An opaque square on the right edge, its shadow pulled 10 px left:
        // the column left of the square shows blur that spilled past the
        // edge, the same as on a buffer padded 20 px and cropped back.
        var layer = try PixelBuffer(width: 32, height: 32)
        for y in 12..<20 { for x in 24..<32 { try layer.setPixel(x: x, y: y, EffectFixtures.white) } }
        let out = try layer.shadowed(color: shade, dx: -10, dy: 0, blur: 6, inner: false)
        let big = try layer.padded(width: 72, height: 72, anchor: .center)
        let reference = try big.shadowed(color: shade, dx: -10, dy: 0, blur: 6, inner: false)
            .cropped(x: 20, y: 20, width: 32, height: 32)
        var lit = 0
        for y in 0..<32 {
            let a = try out.pixel(x: 23, y: y).a, want = try reference.pixel(x: 23, y: y).a
            if want > 0 { lit += 1 }
            #expect(abs(a - want) <= 1e-5, "row \(y): \(a), padded \(want)")
        }
        #expect(lit > 0)
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

    /// A valid buffer whose padded work copy passes `maxPixels` throws naming
    /// the effect, its parameter, the padded size and the fix, not a size the
    /// caller never passed.
    @Test func tooLargeToPadNamesTheEffect() throws {
        // 132,000 x 1 is small, but a 1,000 px blur and offset pad it 1,002 px a side.
        let strip = try PixelBuffer(width: 132_000, height: 1)
        // The offset is within the blur + 3, so the offset alone sets the padding.
        #expect(throws: RasterError.invalid("shadow at offset (1000.0, 0.0) on 132000x1: padded work "
            + "buffer 134004x2005 exceeds 268435456 pixels; reduce the offset or the buffer")) {
            try strip.shadowed(color: shade, dx: 1_000, dy: 0, blur: 1_000, inner: false)
        }
        // A glow pads 2 px a side, a stroke 1: at the largest square buffer both pass the limit.
        let side = 16_384
        let glow = PixelBuffer.lightWork(effect: "glow", reachName: "radius", reach: 1_000, dx: 0, dy: 0)
        #expect(throws: RasterError.invalid("glow on 16384x16384: padded work buffer 16388x16388 "
            + "exceeds 268435456 pixels; reduce the buffer")) {
            try PixelBuffer.paddedWorkSize(width: side, height: side, pad: glow.pad, cause: glow.cause, remedy: glow.remedy)
        }
        #expect(throws: RasterError.invalid("stroke width 4.0 on 16384x16384: padded work buffer 16386x16386 "
            + "exceeds 268435456 pixels; reduce the buffer")) {
            try PixelBuffer.paddedWorkSize(width: side, height: side, pad: 1, cause: "stroke width 4.0", remedy: nil)
        }
        let fits = try PixelBuffer.paddedWorkSize(width: 100, height: 50, pad: 2, cause: "glow", remedy: "radius")
        #expect(fits.width == 104 && fits.height == 54)
    }

    /// A glow's padding is fixed, so its too-large error is the same at any
    /// radius and never tells the caller to reduce it; a shadow names the
    /// blur only when the blur, not the offset, sets the padding.
    @Test func tooLargeNamesOnlyWhatSetsThePadding() throws {
        let side = 16_384
        func message(_ work: (pad: Int, cause: String, remedy: String?)) -> String {
            do {
                _ = try PixelBuffer.paddedWorkSize(width: side, height: side, pad: work.pad, cause: work.cause,
                                                   remedy: work.remedy)
                return ""
            } catch { return "\(error)" }
        }
        let wide = PixelBuffer.lightWork(effect: "glow", reachName: "radius", reach: 1_000, dx: 0, dy: 0)
        let narrow = PixelBuffer.lightWork(effect: "glow", reachName: "radius", reach: 1, dx: 0, dy: 0)
        #expect(wide.pad == 2 && narrow.pad == 2)
        #expect(message(wide) == message(narrow) && message(wide).contains("16388x16388"))
        #expect(!message(wide).contains("radius"))
        let farOff = PixelBuffer.lightWork(effect: "shadow", reachName: "blur", reach: 10, dx: -2_000, dy: 5)
        #expect(farOff.pad == 15 && farOff.remedy == "blur, the offset")
        #expect(farOff.cause == "shadow blur 10.0 at offset (-2000.0, 5.0)")
        let near = PixelBuffer.lightWork(effect: "shadow", reachName: "blur", reach: 10, dx: 4, dy: -13)
        #expect(near.pad == 15 && near.remedy == "offset" && near.cause == "shadow at offset (4.0, -13.0)")
    }

    @Test func hugeOffsetFallsOffTheCanvas() throws {
        let disc = try EffectFixtures.disc(size: 16, radius: 4)
        #expect(try disc.shadowed(color: shade, dx: 1e300, dy: -1e300, blur: 3, inner: false) == disc)
        // Inner: the offset inverse alpha reads as fully covered, so the whole shape is shaded.
        let inner = try disc.shadowed(color: shade, dx: -1e300, dy: 1e300, blur: 3, inner: true)
        let centre = try inner.pixel(x: 8, y: 8)
        #expect(abs(centre.r - 0.4) < 1e-6 && centre.a == 1)
    }

    @Test func fuzzNeverCrashes() throws {
        var rng = SplitMix64(seed: 0xF6_F022)
        let glyph = try EffectFixtures.glyphMask()
        for i in 0..<200 {
            let reach = EffectFuzz.value(&rng, in: 0...1_000), intensity = EffectFuzz.value(&rng, in: 0...1)
            // Offsets: mostly within the glyph's reach, else past it by up to
            // 1,000 px, NaN or infinite (a huge finite offset has its own test).
            let dx = EffectFuzz.value(&rng, in: -64...64), dy = EffectFuzz.value(&rng, in: -64...64)
            let inner = i % 2 == 0
            try EffectFuzz.expectThrowsOrKeepsSize(glyph) {
                try $0.glowing(color: gold, radius: reach, intensity: intensity, inner: inner)
            }
            try EffectFuzz.expectThrowsOrKeepsSize(glyph) {
                try $0.shadowed(color: shade, dx: dx, dy: dy, blur: reach, inner: inner)
            }
        }
    }
}
