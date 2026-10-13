// ShapeTextOwnerTests.swift: the shape and text commands on a symbol's layers
// (Q5d). Each edit undoes exactly, a locked symbol layer rejects them, a drag
// merges only within one owner, and symbol-owned envelopes round-trip.
@testable import FlareCore
import Foundation
import Testing

@Suite struct ShapeTextOwnerTests {
    static let sym = LayerOwner.symbol("sym")
    static let square = Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 4)])

    /// Performs `command`, checks it changed only the symbol, undoes it to
    /// `before`, and redoes it back.
    static func performAndUndo(_ command: any Command, _ e: inout CommandEngine) throws {
        let before = e.document
        try e.perform(command)
        #expect(e.document != before, "\(command.label) changed nothing")
        #expect(e.document.scenes == before.scenes, "\(command.label) touched the scene")
        let after = e.document
        try e.undo()
        #expect(e.document == before, "\(command.label) undo")
        try e.redo()
        #expect(e.document == after, "\(command.label) redo")
    }

    @Test func shapeAndTextEditsInSymbolUndoExactly() throws {
        var e = CommandEngine(document: Fixtures.withSymbol())
        let commands: [any Command] = [
            AddShape(owner: Self.sym, layerID: "wing", shape: Self.square),
            SetShapeFill(owner: Self.sym, layerID: "wing", index: 0, fill: .solid(.white)),
            TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: 3, dy: -2),
            AddTextShape(owner: Self.sym, layerID: "tail", text: TextCommandsTests.hello),
            SetTextString(owner: Self.sym, layerID: "tail", index: 0, string: "Bye"),
            SetTextFont(owner: Self.sym, layerID: "tail", index: 0, family: "Courier", size: 9),
            RemoveTextShape(owner: Self.sym, layerID: "tail", index: 0),
            RemoveShape(owner: Self.sym, layerID: "wing", index: 0),
        ]
        for command in commands { try Self.performAndUndo(command, &e) }
        #expect(e.document.symbols[0].layers.allSatisfy { $0.shapes.isEmpty && $0.texts.isEmpty })

        // The edits landed where they were addressed, with their values.
        var f = CommandEngine(document: Fixtures.withSymbol())
        for command in commands.prefix(6) { try f.perform(command) }
        let wing = f.document.symbols[0].layers[0], tail = f.document.symbols[0].layers[1]
        #expect(wing.shapes == [Shape(points: [Point(x: 3, y: -2), Point(x: 7, y: -2), Point(x: 7, y: 2)],
                                      fill: .solid(.white))])
        #expect(tail.texts.map { [$0.string, $0.fontFamily] } == [["Bye", "Courier"]])
        #expect(tail.texts.first?.fontSize == 9)
    }

    @Test func lockedSymbolLayerThrowsLayerLocked() throws {
        var start = Fixtures.withSymbol()
        start.symbols[0].layers[0].shapes = [Self.square]
        start.symbols[0].layers[0].texts = [TextCommandsTests.hello]
        var e = CommandEngine(document: start)
        try e.perform(SetLayerFlags(owner: Self.sym, layerID: "wing", isLocked: true))
        let locked = e.document
        let commands: [any Command] = [
            AddShape(owner: Self.sym, layerID: "wing", shape: Self.square),
            RemoveShape(owner: Self.sym, layerID: "wing", index: 0),
            SetShapeFill(owner: Self.sym, layerID: "wing", index: 0, fill: .solid(.white)),
            TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: 1, dy: 1),
            AddTextShape(owner: Self.sym, layerID: "wing", text: TextCommandsTests.hello),
            RemoveTextShape(owner: Self.sym, layerID: "wing", index: 0),
            SetTextString(owner: Self.sym, layerID: "wing", index: 0, string: "x"),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "X", size: 3),
        ]
        for command in commands {
            #expect(throws: CommandError.layerLocked("wing"), "\(command.label)") { try e.perform(command) }
            #expect(e.document == locked)
        }
    }

    @Test func missingSymbolThrowsSymbolNotFound() {
        var e = CommandEngine(document: Fixtures.withSymbol())
        let command = AddShape(owner: .symbol("ghost"), layerID: "wing", shape: Self.square)
        #expect(throws: CommandError.symbolNotFound("ghost")) { try e.perform(command) }
        #expect(!e.canUndo)
    }

    @Test func dragMergesOnlyWithinOneOwner() throws {
        var start = Fixtures.withSymbol()
        start.symbols[0].id = Fixtures.sceneID  // a symbol sharing the scene's id
        start.symbols[0].layers[0].id = "ball"  // and a layer sharing the scene layer's id
        start.symbols[0].layers[0].shapes = [Self.square]
        var e = CommandEngine(document: start)
        let s = Fixtures.sceneID
        for _ in 0..<3 {
            try e.perform(TranslateShape(owner: .symbol(s), layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "drag")
        }
        #expect(e.undoStack.first?.commands.count == 1)
        try e.perform(TranslateShape(owner: .scene(s), layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "drag")
        #expect(e.undoStack.first?.commands.count == 2)
        #expect(e.document.symbols[0].layers[0].shapes[0].points[0] == Point(x: 3, y: 0))
        #expect(e.document.scenes[0].layers[1].shapes[0].points[0] == Point(x: 1, y: 0))
        try e.undo()
        #expect(e.document == start)
    }

    @Test func symbolEnvelopesRoundTripFlat() throws {
        let commands: [any Command] = [
            RemoveShape(owner: Self.sym, layerID: "wing", index: 0),
            SetShapeFill(owner: Self.sym, layerID: "wing", index: 0, fill: .solid(.white)),
            TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: 1, dy: 2),
            RemoveTextShape(owner: Self.sym, layerID: "tail", index: 0),
            SetTextString(owner: Self.sym, layerID: "tail", index: 0, string: "x"),
            SetTextFont(owner: Self.sym, layerID: "tail", index: 0, family: "X", size: 3),
        ]
        for command in commands {
            let data = try CommandRegistry.builtIn.encode(command)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let params = object?["params"] as? [String: Any]
            #expect(params?["symbolID"] as? String == "sym", "\(command.label)")
            #expect(params?["sceneID"] == nil, "\(command.label)")
            #expect(try CommandRegistry.builtIn.encode(CommandRegistry.builtIn.decode(data)) == data)
        }
    }

    @Test func oldSceneEnvelopeDecodes() throws {
        let json = #"{"id":"shape.translate","params":{"dx":1,"dy":2,"index":0,"layerID":"ball","sceneID":"s1"}}"#
        let decoded = try CommandRegistry.builtIn.decode(Data(json.utf8))
        let translate = try #require(decoded as? TranslateShape)
        #expect(translate.owner == .scene("s1"))
        #expect(translate.dx == 1 && translate.dy == 2)
    }
}
