// MetalDistanceTests.swift: layer-style-engine LE-8. The Metal jump-flood field is within 1 px of CoreRaster's
// `DistanceField` at every pixel, outside and inside (infinite where it is), on the style fixtures (a rounded-rect
// badge, a disc, a 1 px line, a glyph with a hole), an empty and a full buffer and a seeded multi-tile alpha; the
// Metal box blur is within 1 level of `boxBlurred` on the GPU's pixels at whole and fractional radii, radius 0 is
// the identity; a bad level or radius throws CoreRaster's error and leaves the backend healthy. Skipped without a
// device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

@Suite struct MetalDistanceTests {
    /// A white mask of `width` x `height` whose coverage of `inside` (in pixel units) is 4 x 4 supersampled.
    static func mask(_ width: Int, _ height: Int, _ inside: (Double, Double) -> Bool) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let samples = (0..<16).filter { inside(Double(x) + (Double($0 % 4) + 0.5) / 4, Double(y) + (Double($0 / 4) + 0.5) / 4) }
                let k = Float(samples.count) / 16
                try buffer.setPixel(x: x, y: y, RGBA(r: k, g: k, b: k, a: k))
            }
        }
        return buffer
    }

    /// The style fixtures, plus the field's edge cases, by name.
    static func fixtures() throws -> [(String, PixelBuffer)] {
        let badge = try mask(48, 32) { px, py in
            let cx = min(max(px, 12), 36), cy = min(max(py, 12), 20)
            return px >= 8 && px <= 40 && py >= 8 && py <= 24 && (px - cx) * (px - cx) + (py - cy) * (py - cy) <= 16
        }
        let disc = try mask(64, 64) { px, py in (px - 32) * (px - 32) + (py - 32) * (py - 32) <= 256 }
        let line = try mask(32, 16) { px, _ in px >= 16 && px < 17 }
        let glyph = try mask(40, 40) { px, py in
            let r = ((px - 18) * (px - 18) + (py - 18) * (py - 18)).squareRoot()
            return (r >= 6 && r <= 12) || (px >= 27 && px <= 31 && py >= 6 && py <= 34)
        }
        return [("badge", badge), ("disc", disc), ("line", line), ("glyph", glyph),
                ("empty", try PixelBuffer(width: 20, height: 12)),
                ("full", try PixelBuffer(width: 20, height: 12, fill: RGBA(r: 1, g: 1, b: 1, a: 1))),
                ("seeded", try PixelBuffer.seeded(width: 300, height: 270, seed: 0xD15F))]
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func fieldMatchesTheCPUWithinAPixel() throws {
        let metal = try MetalBackend.onDefaultDevice()
        for (name, buffer) in try Self.fixtures() {
            let source = try metal.surface(buffer)
            defer { metal.release(source) }
            let held = try metal.read(source)
            let want = try DistanceField(alpha: held, level: 0.5)
            let got = try metal.distanceField(source, level: 0.5)
            var worst: Float = 0
            for y in 0..<held.height {
                for x in 0..<held.width {
                    let at = y * held.width + x
                    for (g, w) in [(got.outside[at], want.outside(x: x, y: y)), (got.inside[at], want.inside(x: x, y: y))] {
                        worst = max(worst, g == w ? 0 : abs(g - w))
                    }
                }
            }
            #expect(worst <= 1, "\(name): the jump-flood field is \(worst) px from DistanceField")
            #expect(try metal.read(source) == held, "\(name): the source is unchanged")
        }
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func boxBlurMatchesTheCPUWithinALevel() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let oneLevel = ParityTolerance(bytes: 1, linear: 1.0 / 255)
        let samples = try Self.fixtures().filter { ["badge", "line", "seeded"].contains($0.0) }
        for (name, buffer) in samples {
            let source = try metal.surface(buffer)
            defer { metal.release(source) }
            let held = try metal.read(source)
            for radius in [0, 0.5, 1, 2.5, 4, 12] {
                let got = try metal.boxBlurred(source, radius: radius)
                let want = try held.boxBlurred(radius: radius)
                if radius == 0 { #expect(got == held, "\(name): radius 0 is the identity") }
                let result = try ParityHarness.compare(got, want, tolerance: oneLevel)
                #expect(result.passed, "\(name) radius \(radius): \(result)")
            }
            #expect(try metal.read(source) == held, "\(name): the source is unchanged")
        }
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func badParametersThrowTheCPUError() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let buffer = try PixelBuffer.seeded(width: 6, height: 4, seed: 0xD1)
        let source = try metal.surface(buffer)
        for radius in [-1, -0.001, .nan, .infinity, 1_000.5] {
            do {
                _ = try buffer.boxBlurred(radius: radius)
                Issue.record("the CPU accepts radius \(radius)")
            } catch let expected as RasterError {
                #expect(throws: RenderError(expected)) { try metal.boxBlurred(source, radius: radius) }
            }
        }
        for level in [Float.nan, .infinity, -.infinity] {
            do {
                _ = try DistanceField(alpha: buffer, level: level)
                Issue.record("the CPU accepts level \(level)")
            } catch let expected as RasterError {
                #expect(throws: RenderError(expected)) { try metal.distanceField(source, level: level) }
            }
        }
        #expect(metal.isHealthy, "a bad parameter does not fail the backend")
    }
}
#endif
