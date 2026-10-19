// Samples+Effect.swift: the parity samples and golden pack of `RenderOp.effect` (effects-engine
// FX-8): every `LayerEffect` case once or more through `applying` (box and motion blur, denoise,
// clarity, outer and inner glow, drop and inner shadow, a stroke outside, inside and centred),
// then a layer style of shadow, stroke and glow applied in turn. The inputs are the 9x7 edge-case
// buffers the other families use (random, alpha 0 with color left, subnormal alpha, opaque rows).
// An effect keeps the size, so every result is 9x7 and the pack stacks one width. Parameters are
// small literals; colors are linear premultiplied like the buffers.
import CoreRaster

/// The parity inputs of `RenderOp.effect`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum EffectSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws {
            let names = ["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]
            let alphas: [Float?] = [nil, 0, 1e-45, nil]
            let s = try names.indices.map {
                try ParityHarness.seeded(9, 7, seed: 0xEF00 + UInt64($0), alpha: alphas[$0], opaqueRows: $0 == 3)
            }
            let warm = RGBA(r: 0.9, g: 0.6, b: 0.1, a: 1), dusk = RGBA(r: 0.1, g: 0.05, b: 0.3, a: 0.8)
            let shade = RGBA(r: 0, g: 0, b: 0, a: 0.7), line = RGBA(r: 0.2, g: 0.4, b: 0.8, a: 1)
            let sample = { (name: String, effects: [LayerEffect], source: PixelBuffer) in
                ParitySample(name: name, call: .applied(effects), source: source, backdrop: nil)
            }
            return [
                sample("box-blur", [.boxBlur(radius: 1.5)], s[0]),
                sample("motion-blur", [.motionBlur(degrees: 30, distance: 3)], s[3]),
                sample("denoise", [.denoise(strength: 0.6, detail: 0.3)], s[0]),
                sample("clarity", [.clarity(amount: 40, radius: 2)], s[3]),
                sample("glow-outer", [.glow(color: warm, radius: 2, intensity: 0.75, inner: false)], s[3]),
                sample("glow-inner", [.glow(color: warm, radius: 1.5, intensity: 0.5, inner: true)], s[0]),
                sample("shadow-drop", [.shadow(color: shade, dx: 2, dy: 1.5, blur: 1.5, inner: false)], s[3]),
                sample("shadow-inner", [.shadow(color: dusk, dx: -1, dy: 1, blur: 1, inner: true)], s[1]),
                sample("stroke-outside", [.stroke(color: line, width: 1.5, position: .outside)], s[3]),
                sample("stroke-inside", [.stroke(color: line, width: 1, position: .inside)], s[0]),
                sample("stroke-center", [.stroke(color: line, width: 2, position: .center)], s[2]),
                sample("style-stack", [.shadow(color: shade, dx: 1, dy: 1, blur: 1, inner: false),
                                       .stroke(color: line, width: 1, position: .outside),
                                       .glow(color: warm, radius: 1.5, intensity: 0.6, inner: false)], s[3]),
            ]
        }
    }

    /// The one packed golden, Golden/effect/effect.rgba8; blurs and separable blends.
    static let packs = [ParityPack(.effect, tolerance: .standard)]
}
