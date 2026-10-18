// TextStyleCommandsTests.swift: the text style family's registry ids, registry samples and
// undo steps. A new text style command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes.
import FlareCore
import Testing

@Suite struct TextStyleCommandsTests {
    /// Every id in `TextStyleCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = []

    /// One sample of every text style command, each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] { [] }

    /// Random text style steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TextStyleCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs)
    }
}
