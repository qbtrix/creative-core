// Samples+Color.swift: the parity samples and golden packs of `RenderOp.color`, empty until
// the colour-adjustments feature adds samples and checks in their CPU goldens.

/// The parity inputs of `RenderOp.color`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum ColorSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws { [] }
    }

    /// The packed goldens that hold the samples; empty until they are checked in.
    static let packs: [ParityPack] = []
}
