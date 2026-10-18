// TextStyleCommandsTests.swift: the text style family's registry ids and undo steps. A new
// text style command adds its id to `expectedIDs` and its random steps to
// `undoSteps` here; CommandRegistryTests and UndoPropertyTests read both, so
// neither shared test file changes.
import FlareCore
import Testing

@Suite struct TextStyleCommandsTests {
    /// Every id in `TextStyleCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = []

    /// Random text style steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TextStyleCommands.all.map { $0.id } == Self.expectedIDs)
    }
}
