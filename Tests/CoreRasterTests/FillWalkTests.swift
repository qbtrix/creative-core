// FillWalkTests.swift: KJ-FT, the fill-tools key journey (FT-7), end to end
// on the 2000 x 1500 `FillScene`: a flood fill at tolerance 0.1 from region B
// takes B and gives its anti-aliased border the soft edge; a global fill takes
// B's twin too; a colour range on C at fuzziness 0.2 covers C and fades across
// its border; a radial gradient for B's mask matches its analytic value at
// five radii. No masked composite is on `dev` yet (masks-mattes), so the
// gradient is checked as the buffer alone, at points B's mask covers fully.
// Coverage is read over B, C and their rings plus a row and a column through
// the seeds, not every pixel, so the debug run stays a few seconds.
import CoreRaster
import Testing

@Suite struct FillWalkTests {
    /// The packet's soft edge for a rejected pixel at distance `d`, tolerance `t`.
    private static func softEdge(_ d: Double, _ t: Double) -> Double { min(max(1 - (d - t) / t, 0), 1) }

    @Test func walk() throws {
        let scene = try FillScene(width: 2000, height: 1500)
        let image = scene.buffer, (b, twin, c) = (scene.regionB, scene.twinB, scene.regionC)
        let row = (0..<image.width).map { (x: $0, y: scene.seedB.y) }
        let column = (0..<image.height).map { (x: scene.seedB.x, y: $0) }

        // 1. Flood fill from B at 0.1: B fully, its ring by the soft edge, nothing else.
        let flood = try image.floodMask(from: scene.seedB, tolerance: .within(0.1))
        for p in FillCheck.pixels(b) { #expect(try flood.coverage(x: p.x, y: p.y) == 1) }
        let ringD = try FillCheck.distance(FillScene.border(FillScene.colorB), FillScene.colorB)
        let edge = Self.softEdge(ringD, 0.1)
        #expect(edge > 0 && edge < 1, "ring at distance \(ringD) gets \(edge)")
        for p in FillCheck.edgeRing(b) {
            #expect(abs(Double(try flood.coverage(x: p.x, y: p.y)) - edge) < 1e-3, "(\(p.x), \(p.y))")
        }
        for p in row + column where !b.contains(x: p.x, y: p.y) && !b.ringContains(x: p.x, y: p.y) {
            #expect(try flood.coverage(x: p.x, y: p.y) == 0, "(\(p.x), \(p.y))")
        }
        for p in FillCheck.pixels(twin) where p.y == scene.seedB.y { #expect(try flood.coverage(x: p.x, y: p.y) == 0) }

        // 2. The same fill, global: B's twin is taken too, the same way.
        let global = try image.floodMask(from: scene.seedB, tolerance: .within(0.1), contiguous: false)
        for p in FillCheck.pixels(twin) { #expect(try global.coverage(x: p.x, y: p.y) == 1) }
        for p in FillCheck.pixels(b) where p.y == scene.seedB.y { #expect(try global.coverage(x: p.x, y: p.y) == 1) }
        let hardLocal = try image.floodMask(from: scene.seedB, tolerance: .within(0.1), antiAlias: false)
        let hardGlobal = try image.floodMask(from: scene.seedB, tolerance: .within(0.1), contiguous: false, antiAlias: false)
        #expect(hardLocal.area == Double(b.width * b.height))
        #expect(hardGlobal.area == 2 * hardLocal.area)

        // 3. Colour range on C's sampled colour at 0.2: C fully, its ring faded, A and B out.
        let sampled = try image.sampledColor(at: scene.seedC, radius: 2)
        #expect(sampled == FillScene.colorC)
        let range = try image.colorRangeMask(around: sampled, fuzziness: 0.2)
        for p in FillCheck.pixels(c) { #expect(try range.coverage(x: p.x, y: p.y) == 1) }
        for p in FillCheck.edgeRing(c) {
            let v = try range.coverage(x: p.x, y: p.y)
            #expect(v > 0 && v < 0.1, "C's ring at (\(p.x), \(p.y)) is \(v)")
        }
        for p in [scene.seedA, scene.seedB, (x: c.x - 2, y: scene.seedC.y)] {
            #expect(try range.coverage(x: p.x, y: p.y) == 0, "(\(p.x), \(p.y))")
        }

        // 4. A radial ramp from B's centre, radius 200 px, in linear light without
        // dither so each pixel's red is its `t`; read at five radii inside B's mask.
        let centre = Mask.Point(x: Double(scene.seedB.x) + 0.5, y: Double(scene.seedB.y) + 0.5)
        let rim = Mask.Point(x: centre.x + 200, y: centre.y)
        let ramp = [RasterGradientStop(offset: 0, color: RGBA(r: 0, g: 0, b: 0, a: 1)),
                    RasterGradientStop(offset: 1, color: RGBA(r: 1, g: 1, b: 1, a: 1))]
        let gradient = try PixelBuffer.gradient(width: image.width, height: image.height, shape: .radial,
                                                from: centre, to: rim, stops: ramp, space: .linear, dither: false)
        #expect(gradient.width == image.width && gradient.height == image.height)
        for (dx, dy) in [(0, 0), (50, 0), (0, -100), (-90, 120), (200, 0)] {
            let (x, y) = (scene.seedB.x + dx, scene.seedB.y + dy)
            #expect(try flood.coverage(x: x, y: y) == 1, "(\(x), \(y)) is inside B")
            let p = Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
            let want = FillFixtures.analyticT(.radial, at: p, from: centre, to: rim)
            #expect(abs(want - Double((dx * dx + dy * dy)).squareRoot() / 200) < 1e-9)
            #expect(abs(Double(try gradient.pixel(x: x, y: y).r) - want) < 1e-6, "radius at (\(dx), \(dy))")
        }
    }
}
