// ShapeTextOwnerTests.swift: shape and text commands on a symbol's layers (Q5d):
// exact undo, locked layers, and drags that merge only within one owner.
@testable import FlareCore
import Testing

@Suite struct ShapeTextOwnerTests {
    static let sym = LayerOwner.symbol("sym")

    /// One of each shape and text command on `layerID`, which holds a shape and a text.
    static func edits(_ owner: LayerOwner, layerID: String) -> [any Command] {
        [
            AddShape(owner: owner, layerID: layerID, shape: Shape(points: [Point(x: 1, y: 2)])),
            SetShapeFill(owner: owner, layerID: layerID, index: 0, fill: .solid(.white)),
            TranslateShape(owner: owner, layerID: layerID, index: 0, dx: 3, dy: -2),
            RemoveShape(owner: owner, layerID: layerID, index: 0),
            AddTextShape(owner: owner, layerID: layerID, text: TextCommandsTests.hello),
            SetTextString(owner: owner, layerID: layerID, index: 0, string: "Bye"),
            SetTextFont(owner: owner, layerID: layerID, index: 0, family: "Courier", size: 9),
            RemoveTextShape(owner: owner, layerID: layerID, index: 0),
        ]
    }

    /// `Fixtures.withSymbol()` with the scene ball's shape and a text on "wing".
    static func start() -> Document {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers[0].shapes = doc.scenes[0].layers[1].shapes
        doc.symbols[0].layers[0].texts = [TextCommandsTests.hello]
        return doc
    }

    @Test func shapeAndTextEditsInSymbolUndoExactlyAndLockedLayerThrows() throws {
        var e = CommandEngine(document: Self.start())
        var wings: [Layer] = []
        for command in Self.edits(Self.sym, layerID: "wing") {
            let before = e.document
            try e.perform(command)
            #expect(e.document.scenes == before.scenes, "\(command.label) touched the scene")
            try e.undo()
            #expect(e.document == before, "\(command.label)")
            try e.redo()
            wings.append(e.document.symbols[0].layers[0])
        }
        var moved = Self.start().symbols[0].layers[0].shapes[0].translated(dx: 3, dy: -2)
        moved.fill = .solid(.white)
        #expect(wings[2].shapes == [moved, Shape(points: [Point(x: 1, y: 2)])])
        #expect(wings[6].texts.map { "\($0.string) \($0.fontFamily) \($0.fontSize)" }
            == ["Bye Courier 9.0", "Hello Helvetica 24.0"])
        // A locked symbol layer rejects every one of them.
        try e.perform(SetLayerFlags(owner: Self.sym, layerID: "wing", isLocked: true))
        let locked = e.document
        for command in Self.edits(Self.sym, layerID: "wing") {
            #expect(throws: CommandError.layerLocked("wing"), "\(command.label)") { try e.perform(command) }
            #expect(e.document == locked)
        }
    }

    @Test func dragMergesOnlyWithinOneOwner() throws {
        // Symbol and layer ids match the scene's, and the drag ends on its shape.
        var start = Fixtures.withSymbol()
        let ball = start.scenes[0].layers[1].shapes[0]
        (start.symbols[0].id, start.symbols[0].layers[0].id) = (Fixtures.sceneID, "ball")
        start.symbols[0].layers[0].shapes = [ball.translated(dx: -3, dy: 0)]
        var e = CommandEngine(document: start)
        let s = Fixtures.sceneID
        for _ in 0..<3 {
            try e.perform(TranslateShape(owner: .symbol(s), layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "drag")
        }
        #expect(e.undoStack.first?.commands.count == 1)
        try e.perform(TranslateShape(owner: .scene(s), layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "drag")
        #expect(e.undoStack.first?.commands.count == 2)
        #expect(e.document.scenes[0].layers[1].shapes == [ball.translated(dx: 1, dy: 0)])
        try e.undo()
        #expect(e.document == start)
    }
}
