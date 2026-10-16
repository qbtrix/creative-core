// SymbolCommandsTests.swift: AddSymbol, RemoveSymbol and ConvertToSymbol
// (RenameSymbol has RenameSymbolTests). Add,
// undo and redo restore the document exactly; removing a symbol an instance
// still uses throws symbolInUse and changes nothing; converting layers moves
// them into a new symbol and one undo restores the original.
import FlareCore
import Testing

@Suite struct SymbolCommandsTests {
    static let fan = Symbol(id: "fan", name: "Fan", durationFrames: 12)

    /// The fixture document with "fan", placed by an instance on layer "ball".
    static func documentUsingFan() -> Document {
        var doc = Fixtures.document()
        doc.symbols = [fan]
        doc.scenes[0].layers[1].instances = [Instance(symbolID: "fan")]
        return doc
    }

    @Test func addUndoRedo() throws {
        let start = Fixtures.document()
        var engine = CommandEngine(document: start)
        try engine.perform(AddSymbol(symbol: Self.fan))
        let added = engine.document
        #expect(added.symbols == [Self.fan])
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == added)
    }

    @Test func addInsertsAtClampedIndex() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(AddSymbol(symbol: Self.fan))
        try engine.perform(AddSymbol(symbol: Symbol(id: "a", name: "A"), index: -5))
        try engine.perform(AddSymbol(symbol: Symbol(id: "z", name: "Z"), index: 99))
        #expect(engine.document.symbols.map(\.id) == ["a", "fan", "z"])
    }

    @Test func addRejectsInvalidSymbols() throws {
        var engine = CommandEngine(document: Self.documentUsingFan())
        let before = engine.document
        #expect(throws: CommandError.duplicateID("fan")) { try engine.perform(AddSymbol(symbol: Self.fan)) }
        #expect(throws: CommandError.invalidDuration(-1)) {
            try engine.perform(AddSymbol(symbol: Symbol(id: "neg", name: "Neg", durationFrames: -1)))
        }
        let dangling = Layer(id: "l", name: "L", instances: [Instance(symbolID: "ghost")])
        #expect(throws: CommandError.symbolNotFound("ghost")) {
            try engine.perform(AddSymbol(symbol: Symbol(id: "s", name: "S", layers: [dangling])))
        }
        #expect(engine.document == before)
    }

    @Test func removeUndoRedo() throws {
        var start = Fixtures.document()
        start.symbols = [Symbol(id: "a", name: "A"), Self.fan, Symbol(id: "b", name: "B")]
        var engine = CommandEngine(document: start)
        try engine.perform(RemoveSymbol(symbolID: "fan"))
        let removed = engine.document
        #expect(removed.symbols.map(\.id) == ["a", "b"])
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == removed)
    }

    @Test func removingInUseSymbolThrowsWithoutChanges() throws {
        var engine = CommandEngine(document: Self.documentUsingFan())
        let before = engine.document
        #expect(throws: CommandError.symbolInUse("fan")) { try engine.perform(RemoveSymbol(symbolID: "fan")) }
        #expect(engine.document == before)
        #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
    }

    @Test func instanceInsideAnotherSymbolCountsAsUse() throws {
        var doc = Fixtures.document()
        let host = Symbol(id: "host", name: "Host",
                          layers: [Layer(id: "l", name: "L", instances: [Instance(symbolID: "fan")])])
        doc.symbols = [Self.fan, host]
        var engine = CommandEngine(document: doc)
        #expect(throws: CommandError.symbolInUse("fan")) { try engine.perform(RemoveSymbol(symbolID: "fan")) }
        try engine.perform(RemoveSymbol(symbolID: "host"))
        try engine.perform(RemoveSymbol(symbolID: "fan"))
        #expect(engine.document.symbols.isEmpty)
    }

    @Test func removeMissingSymbolThrows() {
        var engine = CommandEngine(document: Fixtures.document())
        #expect(throws: CommandError.symbolNotFound("nope")) { try engine.perform(RemoveSymbol(symbolID: "nope")) }
    }

    @Test func convertTwoLayersAndUndo() throws {
        let start = Fixtures.document()
        var engine = CommandEngine(document: start)
        try engine.perform(ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: ["ball", "bg"],
                                           symbolID: "group", name: "Group"))
        let converted = engine.document
        let scene = converted.scenes[0]
        #expect(scene.layers.map(\.id) == ["bg"])
        #expect(scene.layers.first?.name == "Group")
        #expect(scene.layers.first?.instances == [Instance(symbolID: "group")])
        #expect(converted.symbols == [Symbol(id: "group", name: "Group", durationFrames: 48,
                                             layers: start.scenes[0].layers)])
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == converted)
    }

    @Test func convertKeepsUnconvertedLayersInPlace() throws {
        var start = Fixtures.document()
        start.scenes[0].layers.append(Layer(id: "top", name: "Top"))
        var engine = CommandEngine(document: start)
        try engine.perform(ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: ["top", "ball"],
                                           symbolID: "g", name: "G"))
        #expect(engine.document.scenes[0].layers.map(\.id) == ["bg", "ball"])
        #expect(engine.document.symbols.first?.layers.map(\.id) == ["ball", "top"])
    }

    @Test func convertRejectsInvalidParamsWithoutChanges() throws {
        var engine = CommandEngine(document: Self.documentUsingFan())
        let before = engine.document
        let s = Fixtures.sceneID
        #expect(throws: CommandError.layerNotFound("ghost")) {
            try engine.perform(ConvertToSymbol(sceneID: s, layerIDs: ["bg", "ghost"], symbolID: "g", name: "G"))
        }
        #expect(throws: CommandError.layerNotFound("bg")) {
            try engine.perform(ConvertToSymbol(sceneID: s, layerIDs: ["bg", "bg"], symbolID: "g", name: "G"))
        }
        #expect(throws: CommandError.invalidIndex(0)) {
            try engine.perform(ConvertToSymbol(sceneID: s, layerIDs: [], symbolID: "g", name: "G"))
        }
        #expect(throws: CommandError.duplicateID("fan")) {
            try engine.perform(ConvertToSymbol(sceneID: s, layerIDs: ["bg"], symbolID: "fan", name: "G"))
        }
        #expect(throws: CommandError.sceneNotFound("nope")) {
            try engine.perform(ConvertToSymbol(sceneID: "nope", layerIDs: ["bg"], symbolID: "g", name: "G"))
        }
        #expect(engine.document == before)
        #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
    }

    /// One sample of each symbol command, valid on `CommandRegistryTests.sampleDocument()`.
    static func registrySamples() -> [any Command] {
        [
            AddSymbol(symbol: Symbol(id: "new", name: "New", durationFrames: 4), index: 0),
            RemoveSymbol(symbolID: "spark"),
            RenameSymbol(symbolID: "spark", name: "Flash"),
            ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: ["ball"], symbolID: "wrap", name: "Wrap"),
        ]
    }

    /// A symbol of the document, or "missing", so steps hit both valid and invalid params.
    static func anySymbol(_ e: CommandEngine, _ rng: inout SplitMix64) -> String {
        (e.document.symbols.map(\.id) + ["missing"]).randomElement(using: &rng) ?? "missing"
    }

    static let undoSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let id = Bool.random(using: &rng) ? anySymbol(e, &rng) : "Y\(nextID)"
            // Sometimes the new symbol places another one, which makes that one in use.
            let instances = Bool.random(using: &rng) ? [Instance(symbolID: anySymbol(e, &rng))] : []
            let symbol = Symbol(id: id, name: "Symbol \(nextID)", durationFrames: Int.random(in: -1...30, using: &rng),
                                layers: [Layer(id: "l", name: "L", instances: instances)])
            try e.perform(AddSymbol(symbol: symbol, index: Int.random(in: -2...5, using: &rng)))
        },
        { e, rng, _ in
            try e.perform(RemoveSymbol(symbolID: anySymbol(e, &rng)))
        },
        { e, rng, nextID in
            nextID += 1
            try e.perform(RenameSymbol(symbolID: anySymbol(e, &rng), name: Bool.random(using: &rng) ? "" : "R\(nextID)"))
        },
        { e, rng, nextID in
            nextID += 1
            let ids = (e.document.scenes.first?.layers.map(\.id) ?? []) + ["missing"]
            let picked = (0..<Int.random(in: 0...2, using: &rng)).compactMap { _ in ids.randomElement(using: &rng) }
            let symbolID = Bool.random(using: &rng) ? anySymbol(e, &rng) : "C\(nextID)"
            try e.perform(ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: picked, symbolID: symbolID, name: "C"))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: Self.documentUsingFan())
    }
}
