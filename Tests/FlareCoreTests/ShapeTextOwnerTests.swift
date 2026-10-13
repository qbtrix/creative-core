// ShapeTextOwnerTests.swift: the shape and text commands take an owner, so they
// edit a symbol's layers as well as a scene's, each with an exact undo. Shape
// drags under different owners never merge, even when the layer ids match.
@testable import FlareCore
import Testing

@Suite struct ShapeTextOwnerTests {
    static let sym = LayerOwner.symbol("sym")
    static let tri = Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 0, y: 4)])

    /// `Fixtures.withSymbol()` with `tri` and a text on the symbol's "wing".
    static func document(locked: Bool = false) -> Document {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers[0].shapes = [tri]
        doc.symbols[0].layers[0].texts = [TextCommandsTests.hello]
        doc.symbols[0].layers[0].isLocked = locked
        return doc
    }

    /// Each shape and text command on "wing", with what it must leave there.
    static func edits() -> [(any Command, @Sendable (Layer) -> Bool)] {
        [(AddShape(owner: sym, layerID: "wing", shape: tri), { $0.shapes == [tri, tri] }),
         (RemoveShape(owner: sym, layerID: "wing", index: 0), { $0.shapes.isEmpty }),
         (SetShapeFill(owner: sym, layerID: "wing", index: 0, fill: .solid(.white)), { $0.shapes[0].fill == .solid(.white) }),
         (TranslateShape(owner: sym, layerID: "wing", index: 0, dx: 10, dy: -1),
          { $0.shapes[0].points == [Point(x: 10, y: -1), Point(x: 14, y: -1), Point(x: 10, y: 3)] }),
         (AddTextShape(owner: sym, layerID: "wing", text: TextCommandsTests.hello), { $0.texts.count == 2 }),
         (RemoveTextShape(owner: sym, layerID: "wing", index: 0), { $0.texts.isEmpty }),
         (SetTextString(owner: sym, layerID: "wing", index: 0, string: "Bye"), { $0.texts.map(\.string) == ["Bye"] }),
         (SetTextFont(owner: sym, layerID: "wing", index: 0, family: "Courier", size: 12),
          { $0.texts.map { "\($0.fontFamily) \($0.fontSize)" } == ["Courier 12.0"] })]
    }

    @Test func eachEditsTheSymbolLayerAndUndoesExactly() throws {
        for (edit, check) in Self.edits() {
            let command = edit
            var engine = CommandEngine(document: Self.document())
            try engine.perform(command)
            #expect(try check(#require(engine.document.symbols.first?.layers.first)), "\(type(of: command).id)")
            #expect(engine.document.scenes == Self.document().scenes)
            try engine.undo()
            #expect(engine.document == Self.document(), "\(type(of: command).id)")
        }
    }

    @Test func lockedSymbolLayerAndMissingSymbolThrowWithoutChanges() {
        var engine = CommandEngine(document: Self.document(locked: true))
        for (edit, _) in Self.edits() {
            let command = edit
            #expect(throws: CommandError.layerLocked("wing"), "\(type(of: command).id)") { try engine.perform(command) }
        }
        let ghost = AddShape(owner: .symbol("ghost"), layerID: "wing", shape: Self.tri)
        #expect(throws: CommandError.symbolNotFound("ghost")) { try engine.perform(ghost) }
        #expect(engine.document == Self.document(locked: true))
        #expect(!engine.canUndo)
    }

    @Test func dragInsideASymbolMergesAndNeverMergesWithTheScene() throws {
        // "sym" gets a copy of "ball" and the scene's shape sits where the drag ends: only the owners differ.
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers.append(doc.scenes[0].layers[1])
        let start = try #require(doc.scenes[0].layers[1].shapes.first)
        doc.scenes[0].layers[1].shapes[0] = start.translated(dx: 10, dy: 0)
        var engine = CommandEngine(document: doc)
        for _ in 0..<10 {
            try engine.perform(TranslateShape(owner: Self.sym, layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "drag")
        }
        try engine.perform(TranslateShape(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, dx: 0, dy: 5),
                           coalesceKey: "drag")
        let commands = try #require(engine.undoStack.last?.commands)
        #expect(commands.count == 2 && (commands.first as? TranslateShape)?.dx == 10)
        try engine.undo()
        #expect(engine.document == doc)
        #expect(!engine.canUndo)
    }
}
