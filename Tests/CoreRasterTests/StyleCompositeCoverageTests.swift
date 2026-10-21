// StyleCompositeCoverageTests.swift: the layer style stack's invariants that
// only the CPU golden guarded (layer-style-engine LE-3, LE-4): every term of
// `reach`, the paint order of every neighbouring rank pair, the inner spread,
// the clipped hole under a faded fill, and the bevel's opacity, emboss clip,
// per-shape rise and smooth profile. Each test names the planted bug in
// Tests/mutations/CoreRaster.StyleComposite.json or CoreRaster.Bevel.json
// that it catches.
@testable import CoreRaster
import Testing

@Suite struct StyleCompositeCoverageTests {
    private static let black = StyleFixtures.black
    private static func glow(_ size: Double) -> StyleOp { .outerGlow(color: StyleFixtures.white, spread: 0, size: size) }
    private static func stroke(_ width: Double, _ position: StrokePosition) -> StyleOp {
        .stroke(fill: .color(black), width: width, position: position)
    }

    /// One row per term of `reach`, plus a disabled entry, a NaN and a value past the cap.
    @Test func reachCountsEveryOuterTerm() {
        let shadow = StyleEntry(op: .dropShadow(color: Self.black, dx: 6, dy: 6, spread: 0, blur: 12))
        let rows: [(String, [StyleEntry], Int)] = [
            ("outer glow", [StyleEntry(op: Self.glow(10))], 10),
            ("outside stroke", [StyleEntry(op: Self.stroke(4, .outside))], 4),
            ("centre stroke", [StyleEntry(op: Self.stroke(5, .center))], 3),
            ("inside stroke", [StyleEntry(op: Self.stroke(9, .inside))], 0),
            ("inner glow", [StyleEntry(op: .innerGlow(color: Self.black, spread: 0, size: 9))], 0),
            ("inner shadow", [StyleEntry(op: .innerShadow(color: Self.black, dx: 9, dy: 9, spread: 0, blur: 9))], 0),
            ("overlay", [StyleEntry(op: .overlay(.color(Self.black)))], 0),
            ("inner bevel", [StyleEntry(op: .bevel(StyleFixtures.bevel(shape: .innerBevel, size: 8)))], 0),
            ("outer bevel", [StyleEntry(op: .bevel(StyleFixtures.bevel(shape: .outerBevel, size: 8)))], 8),
            ("emboss", [StyleEntry(op: .bevel(StyleFixtures.bevel(shape: .emboss, size: 8)))], 8),
            ("pillow emboss", [StyleEntry(op: .bevel(StyleFixtures.bevel(shape: .pillowEmboss, size: 8)))], 8),
            ("disabled glow", [StyleEntry(op: Self.glow(50), isEnabled: false), shadow], 21),
            ("NaN", [StyleEntry(op: Self.glow(.nan))], 0),
            ("NaN beside a glow", [StyleEntry(op: Self.glow(.nan)), StyleEntry(op: Self.glow(3))], 3),
            ("past the cap", [StyleEntry(op: Self.glow(2e6))], 1_000_000),
        ]
        for (name, entries, reach) in rows {
            #expect(LayerStyleStack(entries: entries).reach == reach, "\(name)")
        }
    }

    /// The ops in paint order, bottom up, each opaque in its own colour and
    /// covering the probe: (x 5, y 16) outside the badge for the under-layers,
    /// (x 9, y 16) one pixel inside its left edge for the rest.
    private static func ranked() -> [(op: StyleOp, color: RGBA, probe: Int)] {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1), green = RGBA(r: 0, g: 1, b: 0, a: 1)
        let blue = RGBA(r: 0, g: 0, b: 1, a: 1), yellow = RGBA(r: 1, g: 1, b: 0, a: 1)
        let cyan = RGBA(r: 0, g: 1, b: 1, a: 1), magenta = RGBA(r: 1, g: 0, b: 1, a: 1)
        let gradient = StyleFill.gradient(stops: [RasterGradientStop(offset: 0, color: cyan), RasterGradientStop(offset: 1, color: cyan)],
                                          shape: .linear, from: Mask.Point(x: 0, y: 0), to: Mask.Point(x: 48, y: 0))
        var bevel = StyleFixtures.bevel(size: 5, angle: 180, altitude: 0)
        (bevel.depth, bevel.highlight, bevel.shadow) = (10, black, black)
        (bevel.highlightMode, bevel.shadowMode, bevel.highlightOpacity, bevel.shadowOpacity) = (.normal, .normal, 1, 1)
        return [
            (.dropShadow(color: red, dx: 0, dy: 0, spread: 1, blur: 4), red, 5),
            (.outerGlow(color: green, spread: 1, size: 4), green, 5),
            (.stroke(fill: .color(blue), width: 4, position: .outside), blue, 5),
            (.overlay(gradient), cyan, 9),
            (.overlay(.color(yellow)), yellow, 9),
            (.innerGlow(color: magenta, spread: 1, size: 4), magenta, 9),
            (.innerShadow(color: red, dx: 0, dy: 0, spread: 1, blur: 4), red, 9),
            (.bevel(bevel), black, 9),
            (.stroke(fill: .color(green), width: 4, position: .inside), green, 9),
            (.stroke(fill: .color(blue), width: 4, position: .center), blue, 9),
        ]
    }

    /// For every neighbouring pair of ranks, both list orders draw the same
    /// image, and the probe pixel takes the colour of the higher rank.
    @Test func paintOrderIsFixedForEveryRank() throws {
        let badge = try StyleFixtures.badge(), ops = Self.ranked()
        #expect(Set(ops.map(\.op.paintRank)) == Set(0..<10))
        for i in 0..<(ops.count - 1) {
            let (low, high) = (StyleEntry(op: ops[i].op), StyleEntry(op: ops[i + 1].op))
            let up = try badge.styled(LayerStyleStack(entries: [low, high]))
            let down = try badge.styled(LayerStyleStack(entries: [high, low]))
            #expect(up == down, "ranks \(i), \(i + 1)")
            let pixel = try up.pixel(x: ops[i + 1].probe, y: 16), want = ops[i + 1].color
            let off = max(abs(pixel.r - want.r), abs(pixel.g - want.g), abs(pixel.b - want.b), abs(pixel.a - want.a))
            #expect(off < 0.05, "ranks \(i), \(i + 1): \(pixel) is not \(want)")
        }
    }

    /// An inner spread pulls the edge in by the choke: a pixel two in from the
    /// edge is cleared, the centre is kept; an outer spread grows by a hard
    /// pixel up to the choke and stops past it.
    @Test func innerSpreadChokesInward() throws {
        let badge = try StyleFixtures.badge()
        let inner = try badge.spreadAlpha(choke: 3, inner: true)
        #expect(try inner.pixel(x: 9, y: 16).a == 0 && inner.pixel(x: 24, y: 16).a == 1)
        let outer = try badge.spreadAlpha(choke: 2, inner: false)
        #expect(try outer.pixel(x: 6, y: 16).a == 1 && outer.pixel(x: 5, y: 16).a == 0)
    }

    /// At fill opacity 0 the layer leaves its shape uncovered, so an inner
    /// glow shows through on its own there, at its entry's opacity.
    @Test func clippedEffectShowsThroughAFadedFill() throws {
        let badge = try StyleFixtures.badge()
        let full = StyleEntry(op: .innerGlow(color: StyleFixtures.white, spread: 1, size: 4))
        var half = full
        half.opacity = 0.5
        let shown = try badge.styled(LayerStyleStack(entries: [full], fillOpacity: 0)).pixel(x: 9, y: 16)
        let faded = try badge.styled(LayerStyleStack(entries: [half], fillOpacity: 0)).pixel(x: 9, y: 16)
        #expect(shown.a > 0.99 && abs(faded.a - 0.5) < 0.01)
    }

    /// Half the highlight and shadow opacity is half the light.
    @Test func bevelOpacityScalesTheLight() throws {
        let disc = try StyleFixtures.disc()
        var bevel = StyleFixtures.bevel(angle: 0)
        (bevel.highlightOpacity, bevel.shadowOpacity) = (1, 1)
        let full = try disc.beveled(bevel)
        (bevel.highlightOpacity, bevel.shadowOpacity) = (0.5, 0.5)
        let half = try disc.beveled(bevel)
        for (a, b) in [(full.highlight, half.highlight), (full.shadow, half.shadow)] {
            let (whole, part) = try (EffectFixtures.alphaSum(a), EffectFixtures.alphaSum(b))
            #expect(whole > 1 && abs(part - whole / 2) < 1e-3 * whole)
        }
    }

    /// Emboss and pillow emboss straddle the edge, so they light pixels just
    /// outside the disc as well as inside it; an inner bevel lights none outside.
    @Test func embossLightsBothSidesOfTheEdge() throws {
        let disc = try StyleFixtures.disc()
        func light(_ shape: BevelShape, x: Int) throws -> Float {
            let lit = try disc.beveled(StyleFixtures.bevel(shape: shape, angle: 0))
            return try lit.highlight.pixel(x: x, y: 32).a + lit.shadow.pixel(x: x, y: 32).a
        }
        for shape in [BevelShape.emboss, .pillowEmboss] {
            #expect(try light(shape, x: 49) > 0.01 && light(shape, x: 46) > 0.01, "\(shape)")
        }
        #expect(try light(.innerBevel, x: 49) == 0)
    }

    /// Each shape's rise at a quarter size inside and outside the edge, and
    /// each technique's profile at half the rise.
    @Test func riseAndProfilePerShapeAndTechnique() {
        let rows: [(BevelShape, Double, Double)] = [
            (.innerBevel, 0.25, 0.25), (.innerBevel, -0.25, 0), (.outerBevel, -0.25, 0.75), (.outerBevel, 0.25, 1),
            (.emboss, 0.25, 0.75), (.emboss, -0.25, 0.25), (.pillowEmboss, 0.25, 0.5), (.pillowEmboss, -0.25, 0.5),
        ]
        for (shape, t, r) in rows {
            #expect(PixelBuffer.rise(t, shape) == r, "\(shape) at \(t)")
        }
        #expect(PixelBuffer.profile(0.5, .smooth) == 0.75)
        #expect(PixelBuffer.profile(0.5, .chiselHard) == 0.5 && PixelBuffer.profile(0.5, .chiselSoft) == 0.5)
    }
}
