// MaskCommandsTests.swift: the mask family's registry ids and undo steps. A new
// mask command adds its id to `expectedIDs` and its random steps to
// `undoSteps` here; CommandRegistryTests and UndoPropertyTests read both, so
// neither shared test file changes.
import FlareCore
import Testing

@Suite struct MaskCommandsTests {
    /// Every id in `MaskCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = []

    /// Random mask steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(MaskCommands.all.map { $0.id } == Self.expectedIDs)
    }
}
