// TrackCommandsTests.swift: the track family's registry ids and undo steps. A new
// track command adds its id to `expectedIDs` and its random steps to
// `undoSteps` here; CommandRegistryTests and UndoPropertyTests read both, so
// neither shared test file changes.
import FlareCore
import Testing

@Suite struct TrackCommandsTests {
    /// Every id in `TrackCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = []

    /// Random track steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TrackCommands.all.map { $0.id } == Self.expectedIDs)
    }
}
