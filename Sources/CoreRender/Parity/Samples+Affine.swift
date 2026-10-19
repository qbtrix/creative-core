// Samples+Affine.swift: the parity samples and golden pack of `RenderOp.affine` (affine-composite
// AC-7): `transformed` through a rotate-scale, a shear, the identity and a non-square shrink,
// with bilinear and lanczos3; `flipped` on each axis; and the composite through a matrix in a
// separable non-normal mode below full opacity. The inputs are 9x7 seeded buffers: random,
// fully opaque (every pixel its own color, so hard edges everywhere and lanczos3's ringing
// differs from bilinear in the lanczos3 composite), subnormal alpha and opaque rows. A pack
// stacks one width, so every result is 9 wide: outputs are 9 wide and the backdrop is 9x8.
// Matrices are literals and arithmetic, no trig, so the inputs match bit for bit everywhere.
import CoreRaster

/// The parity inputs of `RenderOp.affine`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum AffineSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws {
            let names = ["random", "opaque", "alpha-subnormal", "opaque-rows"]
            let alphas: [Float?] = [nil, 1, 1e-45, nil]
            let s = try names.indices.map {
                try ParityHarness.seeded(9, 7, seed: 0xAF00 + UInt64($0), alpha: alphas[$0], opaqueRows: $0 == 3)
            }
            let backdrop = try ParityHarness.seeded(9, 8, seed: 0xAFBD, alpha: nil, opaqueRows: true)
            // Linear part (a, b, c, d) about the 9x7 source's centre (4.5, 3.5).
            let centred = { (a: Double, b: Double, c: Double, d: Double) in
                AffineMatrix(a: a, b: b, c: c, d: d, tx: 4.5 - (a * 4.5 + c * 3.5), ty: 3.5 - (b * 4.5 + d * 3.5))
            }
            let rotateScale = centred(0.6928, 0.4, -0.4, 0.6928)  // about 30 degrees at 0.8
            let shear = centred(1, 0, 0.45, 1)
            let shrink = AffineMatrix(a: 1, b: 0, c: 0, d: 4.0 / 7.0, tx: 0, ty: 0)
            let through = AffineMatrix(a: 0.866, b: 0.5, c: -0.5, d: 0.866, tx: 3.25, ty: -1.5)
            let sample = { (name: String, call: ParityCall, source: PixelBuffer) in
                ParitySample(name: name, call: call, source: source, backdrop: nil)
            }
            let onto = { (name: String, call: ParityCall, source: PixelBuffer) in
                ParitySample(name: name, call: call, source: source, backdrop: backdrop)
            }
            return [
                sample("identity", .transformed(.identity, width: 9, height: 7, filter: .bilinear), s[2]),
                sample("rotate-scale-bilinear", .transformed(rotateScale, width: 9, height: 7, filter: .bilinear), s[0]),
                sample("rotate-scale-lanczos3", .transformed(rotateScale, width: 9, height: 7, filter: .lanczos3), s[3]),
                sample("shear-bilinear", .transformed(shear, width: 9, height: 7, filter: .bilinear), s[2]),
                sample("shear-lanczos3", .transformed(shear, width: 9, height: 7, filter: .lanczos3), s[0]),
                sample("non-square-9x4", .transformed(shrink, width: 9, height: 4, filter: .lanczos3), s[3]),
                sample("flip-horizontal", .flipped(.horizontal), s[0]),
                sample("flip-vertical", .flipped(.vertical), s[3]),
                onto("through-multiply-bilinear",
                     .compositeThrough(through, mode: .multiply, opacity: 0.6, filter: .bilinear), s[0]),
                onto("through-screen-lanczos3",
                     .compositeThrough(through, mode: .screen, opacity: 0.5, filter: .lanczos3), s[1]),  // opaque
            ]
        }
    }

    /// The one packed golden, Golden/affine/affine.rgba8; separable sampling and blends.
    static let packs = [ParityPack(.affine, tolerance: .standard)]
}
