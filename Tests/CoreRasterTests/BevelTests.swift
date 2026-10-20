// BevelTests.swift: bevel and emboss (layer-style-engine LE-3). Every check
// waits on LE-3, which builds `beveled(_:)`; they compile now so the contract
// holds. The disc fixture is centred on (32, 32) with radius 16.
import CoreRaster
import Testing

@Suite struct BevelTests {
    /// The x of the pixel in row `y` with the most alpha.
    private func brightestColumn(_ b: PixelBuffer, row y: Int) throws -> Int {
        var (best, alpha) = (0, Float(-1))
        for x in 0..<b.width where try b.pixel(x: x, y: y).a > alpha { (best, alpha) = (x, try b.pixel(x: x, y: y).a) }
        return best
    }

    @Test(.disabled("waits on LE-3")) func lightFromZeroLightsThePlusXEdge() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(angle: 0))
        #expect(try brightestColumn(lit.highlight, row: 32) > 32)
        #expect(try brightestColumn(lit.shadow, row: 32) < 32)
    }

    @Test(.disabled("waits on LE-3")) func lightFromBelowAtNinety() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(angle: 90))
        #expect(try lit.highlight.pixel(x: 32, y: 46).a > lit.highlight.pixel(x: 32, y: 18).a)
    }

    @Test(.disabled("waits on LE-3")) func downSwapsTheLight() throws {
        let disc = try StyleFixtures.disc()
        let up = try disc.beveled(StyleFixtures.bevel(angle: 0))
        let down = try disc.beveled(StyleFixtures.bevel(angle: 0, up: false))
        #expect(try brightestColumn(down.highlight, row: 32) == brightestColumn(up.shadow, row: 32))
    }

    @Test(.disabled("waits on LE-3")) func overheadLightCastsNoShadow() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(altitude: 90))
        #expect(try EffectFixtures.alphaSum(lit.shadow) < 1e-3)
    }

    @Test(.disabled("waits on LE-3")) func sizeZeroIsIdentity() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(size: 0))
        #expect(try EffectFixtures.alphaSum(lit.highlight) + EffectFixtures.alphaSum(lit.shadow) == 0)
    }

    @Test(.disabled("waits on LE-3")) func outerBevelPaintsOnlyOutsideWithinSize() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(shape: .outerBevel, angle: 0))
        #expect(try lit.highlight.pixel(x: 32, y: 32).a == 0)
        #expect(try lit.highlight.pixel(x: 60, y: 32).a == 0 && lit.shadow.pixel(x: 4, y: 32).a == 0)
    }

    @Test(.disabled("waits on LE-3")) func softenLowersThePeak() throws {
        let disc = try StyleFixtures.disc()
        let sharp = try disc.beveled(StyleFixtures.bevel(angle: 0))
        let soft = try disc.beveled(StyleFixtures.bevel(angle: 0, soften: 4))
        let peak = { (b: PixelBuffer) throws -> Float in try b.pixel(x: self.brightestColumn(b, row: 32), y: 32).a }
        #expect(try peak(soft.highlight) < peak(sharp.highlight))
    }

    @Test(.disabled("waits on LE-3")) func flatPastSize() throws {
        let lit = try StyleFixtures.disc().beveled(StyleFixtures.bevel(size: 5, angle: 0))
        #expect(try lit.highlight.pixel(x: 32, y: 32).a == 0 && lit.shadow.pixel(x: 32, y: 32).a == 0)
    }
}
