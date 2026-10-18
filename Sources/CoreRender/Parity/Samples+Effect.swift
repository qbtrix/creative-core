// Samples+Effect.swift: the parity samples and golden packs of `RenderOp.effect`, empty until
// the `effects-engine` feature adds samples and checks in their CPU goldens.

/// The parity inputs of `RenderOp.effect`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum EffectSamples {
    /// Every sample, in golden band order; throws as building a sample's buffers may.
    static var all: [ParitySample] {
        get throws { [] }
    }

    /// The packed goldens that hold the samples; empty until they are checked in.
    static let packs: [ParityPack] = []
}
