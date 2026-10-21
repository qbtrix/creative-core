// StyleCompositeCoverageTests.swift: the layer style stack's invariants that
// only the CPU golden guarded (layer-style-engine LE-3, LE-4): every term of
// `reach`, the paint order of every neighbouring rank pair, the inner spread,
// the clipped hole under a faded fill, the clip at a partly covered edge, the
// bevel layers' modes and opacity, the stroke placements, and the bevel's
// opacity, emboss clip, per-shape rise and smooth profile. Each test names the planted bug in
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

    /// `styled` composites each entry as it draws it; the result equals the
    /// earlier way, every layer drawn first, then the under-layers, the layer
    /// added at the fill opacity, and the rest in order, bit for bit, on a
    /// stack with every op twice plus a centre stroke, at two fill opacities.
    @Test func streamedEqualsEveryLayerDrawnFirst() throws {
        let badge = try StyleFixtures.badge()
        var entries = StyleFixtures.everyOp().entries
        entries += entries.reversed() + [StyleEntry(op: Self.stroke(1.5, .center), opacity: 0.8)]
        for fill: Float in [1, 0.4] {
            let stack = LayerStyleStack(entries: entries, fillOpacity: fill)
            let sorted = stack.entries.enumerated().sorted { ($0.element.op.paintRank, $0.offset) < ($1.element.op.paintRank, $1.offset) }
            let layers = try sorted.flatMap { try badge.styleLayers($0.element) }
            var canvas = try PixelBuffer(width: badge.width, height: badge.height)
            for under in layers where under.placement == .under {
                try canvas.composite(under.source, x: 0, y: 0, mode: under.mode, opacity: under.opacity)
            }
            let (src, under) = (badge.components, canvas.components)
            canvas = PixelBuffer(checkedWidth: badge.width, height: badge.height,
                                 storage: under.indices.map { under[$0] + src[$0] * fill })
            for layer in layers where layer.placement != .under {
                if layer.placement == .clipped {
                    try canvas.compositeClipped(layer, clip: badge)
                } else {
                    try canvas.composite(layer.source, x: 0, y: 0, mode: layer.mode, opacity: layer.opacity)
                }
            }
            #expect(try badge.styled(stack) == canvas, "fill \(fill)")
        }
    }

    /// At an edge pixel half covered by the layer, over an opaque drop
    /// shadow, a colour overlay takes only the layer's share (the clip
    /// alpha) and the canvas past the clip is kept: the result is the clip
    /// alpha times red plus the rest of the canvas's straight colour.
    @Test func clippedOverlayKeepsTheCanvasPastAPartialClip() throws {
        let badge = try StyleFixtures.badge(pad: 7.5)
        let shadow = StyleEntry(op: .dropShadow(color: Self.black, dx: 0, dy: 0, spread: 1, blur: 2))
        let red = StyleEntry(op: .overlay(.color(RGBA(r: 1, g: 0, b: 0, a: 1))))
        let (clip, under) = try (badge.pixel(x: 7, y: 16).a, badge.styled(LayerStyleStack(entries: [shadow])).pixel(x: 7, y: 16))
        #expect(clip > 0.4 && clip < 0.6 && under.a > clip + 0.3)
        let out = try badge.styled(LayerStyleStack(entries: [shadow, red])).pixel(x: 7, y: 16)
        let rest = under.a - clip
        #expect(abs(out.r - (clip + rest * under.r / under.a)) < 1e-4, "\(out)")
        #expect(abs(out.g - rest * under.g / under.a) < 1e-4 && out.g > 0.1, "\(out)")
        #expect(abs(out.a - under.a) < 1e-5)
    }

    /// A bevel's two layers draw over the layer, shadow first, each in its own
    /// mode and both at the entry's opacity.
    @Test func bevelLayersTakeTheirModesAndTheEntryOpacity() throws {
        let entry = StyleEntry(op: .bevel(StyleFixtures.bevel()), mode: .difference, opacity: 0.6)
        let layers = try StyleFixtures.disc().styleLayers(entry)
        #expect(layers.map(\.mode) == [.multiply, .screen])
        #expect(layers.map(\.opacity) == [0.6, 0.6] && layers.map(\.placement) == [.over, .over])
    }

    /// An outside stroke goes under the layer, an inside one is clipped to it
    /// and a centre one draws over it as it is, so it paints past the edge.
    @Test func strokePlacementFollowsThePosition() throws {
        let badge = try StyleFixtures.badge()
        let placements = try StrokePosition.allCases.map { try badge.styleLayers(StyleEntry(op: Self.stroke(4, $0)))[0].placement }
        #expect(Dictionary(uniqueKeysWithValues: zip(StrokePosition.allCases, placements)) == [.outside: .under, .inside: .clipped, .center: .over])
        let centre = try badge.styled(LayerStyleStack(entries: [StyleEntry(op: Self.stroke(4, .center))]))
        #expect(try badge.pixel(x: 7, y: 16).a == 0 && centre.pixel(x: 7, y: 16).a > 0.9)
    }
}
