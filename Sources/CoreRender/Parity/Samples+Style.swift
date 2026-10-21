// Samples+Style.swift: the parity samples and golden pack of `RenderOp.style` (layer-style-engine
// LE-5): every `StyleOp` case once or more through `styled` (drop and inner shadow, outer and inner
// glow, a stroke outside, inside and centred in a colour and a gradient, colour and gradient
// overlays, a bevel in each of the four shapes and three techniques), then a fill opacity under 1,
// a disabled entry beside an enabled one, and a whole stack listed out of paint order. The inputs
// are the 9x7 edge-case buffers the other families use (random, alpha 0 with color left, subnormal
// alpha, opaque rows). A style keeps the size, so every result is 9x7 and the pack stacks one
// width. Parameters are small literals; colors are linear premultiplied like the buffers, gradient
// stops straight. Invariants: names are unique, and every sample changes its input.
import CoreRaster

/// The parity inputs of `RenderOp.style`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum StyleSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws {
            let names = ["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]
            let alphas: [Float?] = [nil, 0, 1e-45, nil]
            let s = try names.indices.map {
                try ParityHarness.seeded(9, 7, seed: 0x57E0 + UInt64($0), alpha: alphas[$0], opaqueRows: $0 == 3)
            }
            let warm = RGBA(r: 0.9, g: 0.6, b: 0.1, a: 1), shade = RGBA(r: 0, g: 0, b: 0, a: 0.7)
            let line = RGBA(r: 0.2, g: 0.4, b: 0.8, a: 1), white = RGBA(r: 1, g: 1, b: 1, a: 1)
            let ramp = StyleFill.gradient(stops: [RasterGradientStop(offset: 0, color: line),
                                                  RasterGradientStop(offset: 1, color: white)],
                                          shape: .linear, from: Mask.Point(x: 0, y: 0), to: Mask.Point(x: 0, y: 7))
            let bevel = { (shape: BevelShape, technique: BevelTechnique, up: Bool) in
                StyleOp.bevel(Bevel(shape: shape, technique: technique, depth: 2, up: up, size: 3, soften: 0.5,
                                    angle: 120, altitude: 30, highlight: white, highlightMode: .screen, highlightOpacity: 0.75,
                                    shadow: shade, shadowMode: .multiply, shadowOpacity: 0.75))
            }
            let drop = StyleOp.dropShadow(color: shade, dx: 2, dy: 1.5, spread: 0.2, blur: 1.5)
            let glow = StyleOp.outerGlow(color: warm, spread: 0, size: 2)
            let sample = { (name: String, entries: [StyleEntry], fillOpacity: Float, source: PixelBuffer) in
                ParitySample(name: name, call: .styled(LayerStyleStack(entries: entries, fillOpacity: fillOpacity)),
                             source: source, backdrop: nil)
            }
            let one = { (name: String, op: StyleOp, mode: BlendMode, source: PixelBuffer) in
                sample(name, [StyleEntry(op: op, mode: mode, opacity: 0.8)], 1, source)
            }
            return [
                one("drop-shadow", drop, .multiply, s[3]),
                one("inner-shadow", .innerShadow(color: shade, dx: -1, dy: 1, spread: 0, blur: 1), .normal, s[0]),
                one("outer-glow", glow, .screen, s[3]),
                one("inner-glow", .innerGlow(color: warm, spread: 0.5, size: 2), .normal, s[0]),
                one("stroke-outside", .stroke(fill: .color(line), width: 1.5, position: .outside), .normal, s[3]),
                one("stroke-inside", .stroke(fill: ramp, width: 1, position: .inside), .normal, s[0]),
                one("stroke-center", .stroke(fill: .color(line), width: 2, position: .center), .normal, s[2]),
                one("overlay-color", .overlay(.color(line)), .multiply, s[3]),
                one("overlay-gradient", .overlay(ramp), .normal, s[0]),
                one("bevel-inner", bevel(.innerBevel, .smooth, true), .normal, s[3]),
                one("bevel-outer", bevel(.outerBevel, .chiselHard, true), .normal, s[3]),
                one("bevel-emboss", bevel(.emboss, .chiselSoft, false), .normal, s[0]),
                one("bevel-pillow", bevel(.pillowEmboss, .smooth, true), .normal, s[3]),
                sample("fill-opacity", [StyleEntry(op: glow)], 0.4, s[3]),
                sample("alpha-zero-fill", [StyleEntry(op: drop)], 0.5, s[1]),
                sample("disabled-entry", [StyleEntry(op: glow, isEnabled: false), StyleEntry(op: drop, mode: .multiply)], 1, s[3]),
                sample("whole-stack", [StyleEntry(op: .stroke(fill: .color(line), width: 1, position: .inside)),
                                       StyleEntry(op: bevel(.innerBevel, .smooth, true), opacity: 0.6),
                                       StyleEntry(op: .overlay(ramp), mode: .multiply, opacity: 0.5),
                                       StyleEntry(op: glow, mode: .screen),
                                       StyleEntry(op: drop, mode: .multiply, opacity: 0.6)], 0.75, s[3]),
            ]
        }
    }

    /// The one packed golden, Golden/style/style.rgba8; blurs and separable blends.
    static let packs = [ParityPack(.style, tolerance: .standard)]
}
