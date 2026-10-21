// BevelTests.swift: bevel and emboss (layer-style-engine LE-3): which side
// the light falls on, `up`, an overhead light, size 0, the outer bevel's
// reach, soften, the flat top past `size`, every shape and technique, and
// out-of-range parameters. The disc fixture is centred on (32, 32) with radius 16.
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

    @Test func overheadLightCastsNoShadow() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(altitude: 90))
        #expect(try EffectFixtures.alphaSum(lit.shadow) < 1e-3)
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
