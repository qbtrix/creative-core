// TextStyleCommandsTests.swift: the text style family's registry ids, registry samples and
// undo steps. A new text style command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes.
import FlareCore
import Testing

@Suite struct TextStyleCommandsTests {
    /// Every id in `TextStyleCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = [
        "text.applyStyle", "text.clearStyle", "text.editString", "text.setParagraph", "text.setOnPath",
    ]

    /// The ids whose commands are still stubs that throw "not built"; each
    /// leaves this set when its task builds it and adds a registry sample.
    static let notBuiltIDs: Set<String> = Set(expectedIDs)

    /// One sample of every built text style command (not in `notBuiltIDs`), each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] { [] }

    /// Random text style steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TextStyleCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs.filter { !Self.notBuiltIDs.contains($0) })
    }
}
