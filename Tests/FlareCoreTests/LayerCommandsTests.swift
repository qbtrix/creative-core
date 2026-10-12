// LayerCommandsTests.swift: ReorderLayer moves a layer within its scene, undo
// restores the order, and bad params throw without changing the document. The
// layer list commands edit a symbol's layers too, with exact undo.
import FlareCore
import Testing

@Suite struct LayerCommandsTests {
    static func ids(_ engine: CommandEngine) -> [String] {
        engine.document.scenes.first?.layers.map(\.id) ?? []
    }

    static func threeLayers() throws -> CommandEngine {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(AddLayer(owner: .scene(Fixtures.sceneID), layer: Layer(id: "fg", name: "Foreground")))
        return engine
    }

    @Test func moveFirstToLastAndBack() throws {
        var engine = try Self.threeLayers()
        let s = Fixtures.sceneID
        #expect(Self.ids(engine) == ["bg", "ball", "fg"])

        try engine.perform(ReorderLayer(owner: .scene(s), layerID: "bg", toIndex: 2))
        #expect(Self.ids(engine) == ["ball", "fg", "bg"])
        try engine.perform(ReorderLayer(owner: .scene(s), layerID: "bg", toIndex: 0))
        #expect(Self.ids(engine) == ["bg", "ball", "fg"])

        try engine.undo()
        #expect(Self.ids(engine) == ["ball", "fg", "bg"])
        #expect(engine.undoActionName == "Undo Reorder Layer")
        try engine.undo()
        #expect(Self.ids(engine) == ["bg", "ball", "fg"])
        try engine.redo()
        #expect(Self.ids(engine) == ["ball", "fg", "bg"])
    }

    @Test func undoRestoresMiddleMove() throws {
        var engine = try Self.threeLayers()
        let before = engine.document
        try engine.perform(ReorderLayer(owner: .scene(Fixtures.sceneID), layerID: "fg", toIndex: 1))
        #expect(Self.ids(engine) == ["bg", "fg", "ball"])
        try engine.undo()
        #expect(engine.document == before)
    }

    @Test(arguments: [-1, 3, Int.max, Int.min])
    func outOfRangeThrowsWithoutChanges(index: Int) throws {
        var engine = try Self.threeLayers()
        let before = engine.document
        #expect(throws: CommandError.invalidIndex(index)) {
            try engine.perform(ReorderLayer(owner: .scene(Fixtures.sceneID), layerID: "bg", toIndex: index))
        }
        #expect(engine.document == before)
    }

    @Test func missingLayerOrSceneThrows() throws {
        var engine = try Self.threeLayers()
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.perform(ReorderLayer(owner: .scene(Fixtures.sceneID), layerID: "nope", toIndex: 0))
        }
        #expect(throws: CommandError.sceneNotFound("nope")) {
            try engine.perform(ReorderLayer(owner: .scene("nope"), layerID: "bg", toIndex: 0))
        }
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        #expect(throws: CommandError.notExecuted) {
            try ReorderLayer(owner: .scene(Fixtures.sceneID), layerID: "bg", toIndex: 0).undo(&doc)
        }
    }

    @Test func layerListCommandsEditSymbolLayers() throws {
        let sym = LayerOwner.symbol("sym")
        var engine = CommandEngine(document: Fixtures.withSymbol())
        let commands: [any Command] = [
            AddLayer(owner: sym, layer: Layer(id: "fin", name: "Fin"), index: 1),
            RenameLayer(owner: sym, layerID: "fin", name: "Dorsal"),
            ReorderLayer(owner: sym, layerID: "wing", toIndex: 2),
            SetLayerFlags(owner: sym, layerID: "tail", isLocked: true),
            RemoveLayer(owner: sym, layerID: "fin"),
        ]
        var states = [engine.document]
        for command in commands {
            try engine.perform(command)
            states.append(engine.document)
        }
        let layers = try #require(engine.document.layers(of: sym))
        #expect(layers.map(\.id) == ["tail", "wing"])
        #expect(layers.map(\.isLocked) == [true, false])
        #expect(states[2].symbols[0].layers.map(\.name) == ["Wing", "Dorsal", "Tail"])
        #expect(states[3].symbols[0].layers.map(\.id) == ["fin", "tail", "wing"])
        #expect(engine.document.scenes == Fixtures.document().scenes)
        #expect(throws: CommandError.duplicateID("wing")) {
            try engine.perform(AddLayer(owner: sym, layer: Layer(id: "wing", name: "W")))
        }

        for state in states.dropLast().reversed() {
            try engine.undo()
            #expect(engine.document == state)
        }
    }
}
