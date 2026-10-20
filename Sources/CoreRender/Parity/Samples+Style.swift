// Samples+Style.swift: the parity samples and golden pack of `RenderOp.style`. Empty until
// layer-style-engine LE-5 fills them with layer style stacks through `styled`.

/// The parity inputs of `RenderOp.style`, read by `ParityHarness.sampleSet(for:)` and `ParityPack.all`.
enum StyleSamples {
    /// Every sample, in golden band order: none yet.
    static var all: [ParitySample] {
        get throws { [] }
    }
}
