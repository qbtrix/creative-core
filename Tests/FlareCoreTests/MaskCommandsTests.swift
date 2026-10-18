// MaskCommandsTests.swift: the mask family's registry ids, registry samples and
// undo steps. A new mask command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes.
import FlareCore
import Testing

@Suite struct MaskCommandsTests {
    /// Every id in `MaskCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = []

    /// One sample of every mask command, each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] { [] }

    /// Random mask steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(MaskCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs)
    }
}
