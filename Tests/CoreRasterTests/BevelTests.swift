// BevelTests.swift: bevel and emboss (layer-style-engine LE-3): which side
// the light falls on, `up`, an overhead light, size 0, the outer bevel's
// reach and clip, soften (and nothing painted past `size` outside under it),
// chisel soft's 1 px blur, the half-pixel edge, the flat top past `size`,
// every shape and technique, and out-of-range parameters. The disc fixture is centred on (32, 32) with radius 16.
import CoreRaster
import Testing

@Suite struct BevelTests {
    /// The x of the pixel in row `y` with the most alpha.
    private func brightestColumn(_ b: PixelBuffer, row y: Int) throws -> Int {
        var (best, alpha) = (0, Float(-1))
        for x in 0..<b.width where try b.pixel(x: x, y: y).a > alpha { (best, alpha) = (x, try b.pixel(x: x, y: y).a) }
        return best
    }

    @Test func lightFromZeroLightsThePlusXEdge() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(angle: 0))
        #expect(try brightestColumn(lit.highlight, row: 32) > 32)
        #expect(try brightestColumn(lit.shadow, row: 32) < 32)
    }

    @Test func lightFromBelowAtNinety() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(angle: 90))
        #expect(try lit.highlight.pixel(x: 32, y: 46).a > lit.highlight.pixel(x: 32, y: 18).a)
    }

    @Test func downSwapsTheLight() throws {
        let disc = try StyleFixtures.disc()
        let up = try disc.beveled(StyleFixtures.bevel(angle: 0))
        let down = try disc.beveled(StyleFixtures.bevel(angle: 0, up: false))
        #expect(try brightestColumn(down.highlight, row: 32) == brightestColumn(up.shadow, row: 32))
    }

    /// Altitude 90 leans no normal toward the light: every shape paints exactly nothing in either layer.
    @Test func overheadLightCastsNoShadow() throws {
        for shape in BevelShape.allCases {
            let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(shape: shape, altitude: 90))
            #expect(try EffectFixtures.alphaSum(lit.shadow) == 0 && EffectFixtures.alphaSum(lit.highlight) == 0, "\(shape)")
        }
    }

    @Test func sizeZeroIsIdentity() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(size: 0))
        #expect(try EffectFixtures.alphaSum(lit.highlight) + EffectFixtures.alphaSum(lit.shadow) == 0)
    }

    @Test func outerBevelPaintsOnlyOutsideWithinSize() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(shape: .outerBevel, angle: 0))
        #expect(try lit.highlight.pixel(x: 32, y: 32).a == 0)
        #expect(try lit.highlight.pixel(x: 60, y: 32).a == 0 && lit.shadow.pixel(x: 4, y: 32).a == 0)
    }

    /// Lit from either side, an outer bevel leaves every fully opaque pixel unlit: it is clipped to 1 - alpha.
    @Test func outerBevelLeavesTheOpaqueShapeUnlit() throws {
        let disc = try StyleFixtures.disc()
        for angle in [0.0, 180] {
            let lit = try disc.beveled(StyleFixtures.bevel(shape: .outerBevel, angle: angle))
            var painted: Float = 0
            for y in 0..<disc.height {
                for x in 0..<disc.width where try disc.pixel(x: x, y: y).a == 1 {
                    painted += try lit.highlight.pixel(x: x, y: y).a + lit.shadow.pixel(x: x, y: y).a
                }
            }
            #expect(painted == 0, "angle \(angle)")
        }
    }

    /// Soften blurs the height past `size` outside the edge; nothing is painted there all the same.
    /// The disc's edge is at x 16 and 48 on row 32, so x 0..<9 and 55..<64 are more than 5 px out.
    @Test func softenedBevelPaintsNothingPastSizeOutside() throws {
        let disc = try StyleFixtures.disc()
        for shape in [BevelShape.outerBevel, .emboss, .pillowEmboss] {
            let lit = try disc.beveled(StyleFixtures.bevel(shape: shape, size: 5, angle: 0, soften: 8))
            var past: Float = 0
            for x in Array(0..<9) + Array(55..<64) {
                past += try lit.highlight.pixel(x: x, y: 32).a + lit.shadow.pixel(x: x, y: 32).a
            }
            #expect(past == 0, "\(shape) paints \(past) past size")
        }
    }

    /// Chisel soft is chisel hard blurred 1 px: the same as chisel hard with soften 1 (radius 1/3), not soften 0.
    @Test func chiselSoftBlursOnePixel() throws {
        let disc = try StyleFixtures.disc()
        func lit(_ technique: BevelTechnique, soften: Double) throws -> (highlight: PixelBuffer, shadow: PixelBuffer) {
            var bevel = StyleFixtures.bevel(angle: 0, soften: soften)
            bevel.technique = technique
            return try disc.beveled(bevel)
        }
        let soft = try lit(.chiselSoft, soften: 0), hard = try lit(.chiselHard, soften: 0)
        let blurred = try lit(.chiselHard, soften: 1)
        #expect(soft.highlight == blurred.highlight && soft.shadow == blurred.shadow)
        #expect(soft.highlight != hard.highlight)
    }

    /// The edge sits half a pixel in, between the last opaque and first clear pixel, so a chisel hard emboss's
    /// ramp runs straight across it: the three pixels each side of a hard vertical edge light the same.
    @Test func edgeSitsBetweenPixels() throws {
        var half = try PixelBuffer(width: 32, height: 32)
        for y in 0..<32 { for x in 0..<16 { try half.setPixel(x: x, y: y, RGBA(r: 1, g: 1, b: 1, a: 1)) } }
        var bevel = StyleFixtures.bevel(shape: .emboss, size: 8, angle: 0)
        bevel.technique = .chiselHard
        let lit = try half.beveled(bevel)
        let ramp = try (13..<19).map { try lit.highlight.pixel(x: $0, y: 16).a }
        #expect(ramp[0] > 0)
        for (x, a) in zip(13..., ramp) { #expect(abs(a - ramp[0]) < 1e-6, "x \(x): \(a) vs \(ramp[0])") }
    }

    @Test func softenLowersThePeak() throws {
        let disc = try StyleFixtures.disc()
        let sharp = try disc.beveled(StyleFixtures.bevel(angle: 0))
        let soft = try disc.beveled(StyleFixtures.bevel(angle: 0, soften: 4))
        let peak = { (b: PixelBuffer) throws -> Float in try b.pixel(x: self.brightestColumn(b, row: 32), y: 32).a }
        #expect(try peak(soft.highlight) < peak(sharp.highlight))
    }

    @Test func flatPastSize() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(size: 5, angle: 0))
        #expect(try lit.highlight.pixel(x: 32, y: 32).a == 0 && lit.shadow.pixel(x: 32, y: 32).a == 0)
    }

    @Test func everyShapeAndTechniqueLightsTheEdgeOnly() throws {
        let disc = try StyleFixtures.disc()
        for shape in BevelShape.allCases {
            for technique in BevelTechnique.allCases {
                var bevel = StyleFixtures.bevel(shape: shape, angle: 0)
                bevel.technique = technique
                let lit = try disc.beveled(bevel)
                #expect(try EffectFixtures.alphaSum(lit.highlight) > 1, "\(shape) \(technique)")
                #expect(try lit.highlight.pixel(x: 32, y: 32).a == 0 && lit.highlight.pixel(x: 2, y: 32).a == 0)
            }
        }
    }

    @Test func outOfRangeParametersThrow() throws {
        let disc = try StyleFixtures.disc()
        let bad: [@Sendable (inout Bevel) -> Void] = [
            { $0.size = .nan }, { $0.size = -1 }, { $0.size = 251 }, { $0.depth = 0 }, { $0.depth = .infinity },
            { $0.soften = 17 }, { $0.angle = .infinity }, { $0.altitude = 91 }, { $0.altitude = -1 },
            { $0.highlightOpacity = 2 }, { $0.shadowOpacity = .nan }, { $0.highlight.r = .infinity },
        ]
        for edit in bad {
            var bevel = StyleFixtures.bevel()
            edit(&bevel)
            #expect(throws: RasterError.self) { try disc.beveled(bevel) }
        }
    }
}
