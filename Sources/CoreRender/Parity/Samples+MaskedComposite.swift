// Samples+MaskedComposite.swift: the parity samples and golden pack of `RenderOp.maskedComposite`
// (masks-mattes MM-5): the four 9x7 edge-case sources at (1, 1) through a 6 px feathered ellipse;
// that mask off each edge of the 11x8 backdrop; a luminance matte in multiply, an inverted alpha
// matte in screen, a full mask at opacity 1 on the opaque rows (the unmasked fast path) and an
// empty mask (the backdrop back). Every result is the 11x8 backdrop, so the pack is 11 wide.
// Modes are separable, so the pack is cut at `.standard`.
import CoreRaster

/// The parity inputs of `RenderOp.maskedComposite`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum MaskedCompositeSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws {
            let names = ["random", "alpha-zero", "alpha-subnormal", "opaque-rows"]
            let alphas: [Float?] = [nil, 0, 1e-45, nil]
            let s = try names.indices.map {
                try ParityHarness.seeded(9, 7, seed: 0x3A50 + UInt64($0), alpha: alphas[$0], opaqueRows: $0 == 3)
            }
            let backdrop = try ParityHarness.seeded(11, 8, seed: 0x3ABD, alpha: nil, opaqueRows: true)
            let matte = try ParityHarness.seeded(10, 6, seed: 0x3A3A, alpha: nil, opaqueRows: false)
            let ellipse = try Mask.ellipse(width: 9, height: 7, centerX: 4.5, centerY: 3.5, radiusX: 3.5, radiusY: 2.5)
                .feathered(radius: 6)
            let call = { (x: Int, y: Int, mode: BlendMode, opacity: Float, mask: Mask, maskX: Int, maskY: Int) in
                ParityCall.maskedComposite(x: x, y: y, mode: mode, opacity: opacity, mask: mask, maskX: maskX, maskY: maskY)
            }
            let onto = { (name: String, call: ParityCall, source: PixelBuffer) in
                ParitySample(name: name, call: call, source: source, backdrop: backdrop)
            }
            // The mask's top-left in the backdrop, off each edge; the source stays at (1, 1).
            let edges = [("mask-off-left", -5, 1), ("mask-off-top", 1, -4), ("mask-off-right", 7, 1), ("mask-off-bottom", 1, 6)]
            return zip(names, s).map { onto($0, call(1, 1, .normal, 0.8, ellipse, 1, 1), $1) }
                + edges.map { onto($0.0, call(1, 1, .normal, 0.8, ellipse, $0.1, $0.2), s[0]) }
                + [
                    onto("luma-matte-multiply", call(0, 1, .multiply, 1, try Mask(from: matte, .luminance), 1, 2), s[0]),
                    onto("inverted-alpha-screen", call(2, 0, .screen, 0.6, try Mask(from: matte, .alpha, inverted: true), 0, 0), s[2]),
                    onto("full-mask-opaque", call(1, 1, .normal, 1, try Mask(width: 9, height: 7, fill: 1), 1, 1), s[3]),
                    onto("empty-mask", call(1, 1, .normal, 1, try Mask(width: 9, height: 7), 1, 1), s[0]),
                ]
        }
    }

    /// The one packed golden, Golden/maskedComposite/maskedComposite.rgba8; separable blends.
    static let packs = [ParityPack(.maskedComposite, tolerance: .standard)]
}
