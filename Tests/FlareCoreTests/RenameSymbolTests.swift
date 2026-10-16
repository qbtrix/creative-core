// RenameSymbolTests.swift: RenameSymbol renames a symbol and one undo restores
// the old name exactly; an empty name throws emptyName and a missing id throws
// symbolNotFound, both without changes; the command is registered, sampled and
// in the symbol undo steps.
import FlareCore
import Testing

@Suite struct RenameSymbolTests {
    static func start() -> Document {
        var doc = Fixtures.document()
        doc.symbols = [Symbol(id: "a", name: "A"), SymbolCommandsTests.fan]
        return doc
    }

    @Test func renameUndoRedoExact() throws {
        let start = Self.start()
        var engine = CommandEngine(document: start)
        try engine.perform(RenameSymbol(symbolID: "fan", name: "Propeller"))
        let renamed = engine.document
        #expect(renamed.symbols.map(\.name) == ["A", "Propeller"])
        try engine.undo()
        #expect(engine.document == start)
        #expect(engine.document.symbols.map(\.name) == ["A", "Fan"])
        try engine.redo()
        #expect(engine.document == renamed)
    }

    @Test func emptyNameThrowsWithoutChanges() {
        var engine = CommandEngine(document: Self.start())
        #expect(throws: CommandError.emptyName) { try engine.perform(RenameSymbol(symbolID: "fan", name: "")) }
        #expect(engine.document == Self.start())
        #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
    }

    @Test func missingSymbolThrowsWithoutChanges() {
        var engine = CommandEngine(document: Self.start())
        #expect(throws: CommandError.symbolNotFound("ghost")) {
            try engine.perform(RenameSymbol(symbolID: "ghost", name: "G"))
        }
        #expect(engine.document == Self.start())
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.start()
        #expect(throws: CommandError.notExecuted) { try RenameSymbol(symbolID: "fan", name: "X").undo(&doc) }
    }

    @Test func registeredSampledAndStepped() {
        #expect(SymbolCommands.all.contains { $0.id == RenameSymbol.id })
        #expect(CommandRegistryTests.expectedIDs.contains("symbol.rename"))
        #expect(SymbolCommandsTests.registrySamples().contains { $0 is RenameSymbol })
        #expect(SymbolCommandsTests.undoSteps.count == 4)
    }
}
