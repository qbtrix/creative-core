// TrackCommandsTests.swift: the track family's registry ids, registry samples and
// undo steps. A new track command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes.
import FlareCore
import Testing

@Suite struct TrackCommandsTests {
    /// Every id in `TrackCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = [
        "colorKey.set", "colorKey.remove", "colorKey.move", "shapeKey.set", "shapeKey.remove",
    ]

    /// The ids whose commands are still stubs that throw "not built"; each
    /// leaves this set when its task builds it and adds a registry sample.
    static let notBuiltIDs: Set<String> = Set(expectedIDs)

    /// One sample of every built track command (not in `notBuiltIDs`), each
    /// valid on `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    /// The shared tests execute every sample, so a stub gets one when it is built.
    static func registrySamples() -> [any Command] { [] }

    /// Random track steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = []

    @Test func familyListsExactlyItsIDs() {
        #expect(TrackCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs.filter { !Self.notBuiltIDs.contains($0) })
    }
}
