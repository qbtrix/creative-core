// DuplicateLayerTests.swift: DuplicateLayer puts a copy just above the layer
// with a fresh id and "<name> copy", undo removes exactly that copy, and a
// missing layer throws without changing the document, in a scene or a symbol.
import FlareCore
import Testing

@Suite struct DuplicateLayerTests {
    static let scene = LayerOwner.scene(Fixtures.sceneID)

    /// The fixture with a text and an instance on "ball", so the copy check covers every field.
    static func richDocument() -> Document {
        var doc = Fixtures.withSymbol()
        doc.scenes[0].layers[1].texts = [TextShape(string: "Hi", fontFamily: "Sans", fontSize: 12, position: Point(x: 1, y: 2))]
        doc.scenes[0].layers[1].instances = [Instance(symbolID: "sym")]
        return doc
    }

    @Test func copySitsAboveWithFreshIDAndSameContent() throws {
        var engine = CommandEngine(document: Self.richDocument())
        let original = engine.document
        try engine.perform(DuplicateLayer(owner: Self.scene, layerID: "ball"))
        let layers = try #require(engine.document.layers(of: Self.scene))
        #expect(layers.map(\.id) == ["bg", "ball", "ball-copy"])
        let ball = layers[1], copy = layers[2]
        #expect(copy.name == "Ball copy")
        #expect(copy.shapes == ball.shapes)
        #expect(copy.tracks == ball.tracks)
        #expect(copy.instances == ball.instances)
        #expect(copy.texts == ball.texts)
        #expect(copy.isVisible == ball.isVisible && copy.isLocked == ball.isLocked)
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func repeatedDuplicatesGetDistinctIDs() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        for _ in 0..<3 { try engine.perform(DuplicateLayer(owner: Self.scene, layerID: "ball")) }
        let ids = try #require(engine.document.layers(of: Self.scene)).map(\.id)
        #expect(ids == ["bg", "ball", "ball-copy-3", "ball-copy-2", "ball-copy"])
        #expect(Set(ids).count == ids.count)
        while engine.canUndo { try engine.undo() }
        #expect(engine.document == original)
    }

    @Test func missingLayerThrowsAndChangesNothing() {
        var engine = CommandEngine(document: Fixtures.withSymbol())
        let original = engine.document
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.perform(DuplicateLayer(owner: Self.scene, layerID: "nope"))
        }
        #expect(throws: CommandError.symbolNotFound("nope")) {
            try engine.perform(DuplicateLayer(owner: .symbol("nope"), layerID: "wing"))
        }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func fullLayerListRejectsTheCopy() {
        var doc = Fixtures.document()
        let filler = (doc.scenes[0].layers.count..<FlareFormat.maxLayersPerScene).map { Layer(id: "f\($0)", name: "F") }
        doc.scenes[0].layers += filler
        var engine = CommandEngine(document: doc)
        #expect(throws: CommandError.self) { try engine.perform(DuplicateLayer(owner: Self.scene, layerID: "bg")) }
        #expect(engine.document == doc)
    }

    @Test func worksInsideASymbol() throws {
        var engine = CommandEngine(document: Fixtures.withSymbol())
        let original = engine.document
        let sym = LayerOwner.symbol("sym")
        try engine.perform(DuplicateLayer(owner: sym, layerID: "wing"))
        let layers = try #require(engine.document.layers(of: sym))
        #expect(layers.map(\.id) == ["wing", "wing-copy", "tail"])
        #expect(layers[1].name == "Wing copy")
        #expect(layers[1].tracks == layers[0].tracks)
        #expect(engine.document.scenes == original.scenes)
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func undoThrowsRatherThanRemoveAnotherLayer() throws {
        var doc = Fixtures.document()
        var cmd = DuplicateLayer(owner: Self.scene, layerID: "bg")
        try cmd.execute(&doc)
        #expect(doc.scenes[0].layers.map(\.id) == ["bg", "bg-copy", "ball"])
        // Something else moved the copy away from index + 1.
        doc.scenes[0].layers.swapAt(1, 2)
        let moved = doc
        #expect(throws: CommandError.invalidDocument("layer bg-copy: the duplicate is no longer at index 1")) {
            try cmd.undo(&doc)
        }
        #expect(doc == moved)
        // Something else removed the copy: no layer has its id.
        doc.scenes[0].layers.removeAll { $0.id == "bg-copy" }
        let removed = doc
        #expect(throws: CommandError.layerNotFound("bg-copy")) { try cmd.undo(&doc) }
        #expect(doc == removed)
    }
}
