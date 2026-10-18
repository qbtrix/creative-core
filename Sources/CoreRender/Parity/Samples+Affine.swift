// Samples+Affine.swift: the parity samples and golden packs of `RenderOp.affine`, empty until
// the `affine-composite` feature adds samples and checks in their CPU goldens.

/// The parity inputs of `RenderOp.affine`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum AffineSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws { [] }
    }

    /// The packed goldens that hold the samples; empty until they are checked in.
    static let packs: [ParityPack] = []
}
