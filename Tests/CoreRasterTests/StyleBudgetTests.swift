// StyleBudgetTests.swift: the layer-style-engine CPU budget (LE-10): the KJ-LE walk's stack on a 2,000 x 2,000
// layer takes at most 250 ms, the median of three runs. Release-only and reported (debug skips it, so no clock
// can flake the gate; the walk proves the result). The Metal row is held with LE-9b.
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

@Suite(.serialized) struct StyleBudgetTests {
    /// The walk's stack for a `side` x `side` layer (StyleWalkTests' stack; that target cannot be imported here).
    static func walkStack(side: Int) -> LayerStyleStack {
        let (black, white) = (RGBA(r: 0, g: 0, b: 0, a: 1), RGBA(r: 1, g: 1, b: 1, a: 1))
        let crimson = RGBA(r: 0.716, g: 0.007, b: 0.045, a: 1), blue = RGBA(r: 0, g: 0, b: 1, a: 1)
        let ramp = [RasterGradientStop(offset: 0, color: blue), RasterGradientStop(offset: 1, color: white)]
        let bevel = Bevel(shape: .innerBevel, technique: .smooth, depth: 1, up: true, size: 8, soften: 0, angle: 120, altitude: 30,
                          highlight: white, highlightMode: .screen, highlightOpacity: 0.75,
                          shadow: black, shadowMode: .multiply, shadowOpacity: 0.75)
        let x = Double(side) / 2
        return LayerStyleStack(entries: [
            StyleEntry(op: .dropShadow(color: black, dx: 6, dy: 6, spread: 0, blur: 12), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .outerGlow(color: RGBA(r: 1, g: 0.79, b: 0.3, a: 1), spread: 0, size: 10), mode: .screen, opacity: 0.75),
            StyleEntry(op: .stroke(fill: .color(crimson), width: 4, position: .outside)),
            StyleEntry(op: .overlay(.gradient(stops: ramp, shape: .linear, from: Mask.Point(x: x, y: 0),
                                              to: Mask.Point(x: x, y: Double(side)))), opacity: 0.6),
            StyleEntry(op: .innerShadow(color: black, dx: 3, dy: 3, spread: 0, blur: 6), mode: .multiply, opacity: 0.5),
            StyleEntry(op: .bevel(bevel)),
        ])
    }

    @Test(.enabled(if: optimized, "a release budget: debug skips it"))
    func walkStackOn4MPUnder250ms() throws {
        let layer = try EffectBudgetTests.styleLayer(side: 2000), stack = Self.walkStack(side: 2000)
        let clock = ContinuousClock()
        var out: PixelBuffer?, wall: [Duration] = []
        for _ in 0..<3 {
            out = nil
            wall.append(try clock.measure { out = try layer.styled(stack) })
        }
        #expect(out?.width == 2000 && out != layer)
        let median = wall.sorted()[1], ms = Double(median.components.attoseconds) / 1e15 + Double(median.components.seconds) * 1e3
        print("budget style walk stack 2000x2000: \((ms * 1000).rounded() / 1000) ms (budget 250 ms)")
        #expect(median <= .milliseconds(250), "style walk stack median \(median)")
    }
}
