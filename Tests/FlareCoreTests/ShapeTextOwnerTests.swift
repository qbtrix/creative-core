// ShapeTextOwnerTests.swift: the shape and text commands take an owner, so they
// edit a symbol's layers as well as a scene's. Drags under different owners
// never coalesce, and pre-owner scene envelopes still encode byte for byte.
@testable import FlareCore
import Foundation
import Testing

@Suite struct ShapeTextOwnerTests {
    static let sym = LayerOwner.symbol("sym")
    static let tri = Shape(points: [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 0, y: 4)])
    static let hello = TextShape(string: "Hi", fontFamily: "Helvetica", fontSize: 24, position: Point(x: 1, y: 2))

    static func wing(_ e: CommandEngine) throws -> Layer {
        try #require(e.document.symbols.first?.layers.first { $0.id == "wing" })
    }

    /// Performs each command in turn, then undoes them one by one and checks
    /// each undo gives back the document from before that command exactly.
    static func performThenUndoEach(_ engine: inout CommandEngine, _ commands: [any Command],
                                    check: (Int, CommandEngine) throws -> Void) throws {
        var history = [engine.document]
        for (i, command) in commands.enumerated() {
            let c = command
            try engine.perform(c)
            #expect(engine.document.scenes == history[0].scenes, "\(type(of: c).id) touched a scene")
            try check(i, engine)
            history.append(engine.document)
        }
        for expected in history.dropLast().reversed() {
            try engine.undo()
            #expect(engine.document == expected)
        }
        #expect(!engine.canUndo)
    }

    @Test func addFillTranslateAndRemoveAShapeInASymbol() throws {
        var engine = CommandEngine(document: Fixtures.withSymbol())
        let commands: [any Command] = [
            AddShape(owner: Self.sym, layerID: "wing", shape: Self.tri),
            SetShapeFill(owner: Self.sym, layerID: "wing", index: 0, fill: .solid(.white)),
            TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: 10, dy: -1),
            RemoveShape(owner: Self.sym, layerID: "wing", index: 0),
        ]
        try Self.performThenUndoEach(&engine, commands) { i, e in
            let shapes = try Self.wing(e).shapes
            switch i {
            case 0: #expect(shapes == [Self.tri])
            case 1: #expect(shapes.first?.fill == .solid(.white))
            case 2: #expect(shapes.first?.points == [Point(x: 10, y: -1), Point(x: 14, y: -1), Point(x: 10, y: 3)])
            default: #expect(shapes.isEmpty)
            }
        }
    }

    @Test func addEditAndRemoveTextInASymbol() throws {
        var engine = CommandEngine(document: Fixtures.withSymbol())
        let commands: [any Command] = [
            AddTextShape(owner: Self.sym, layerID: "wing", text: Self.hello),
            SetTextString(owner: Self.sym, layerID: "wing", index: 0, string: "Bye"),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "Courier", size: 12),
            RemoveTextShape(owner: Self.sym, layerID: "wing", index: 0),
        ]
        try Self.performThenUndoEach(&engine, commands) { i, e in
            let texts = try Self.wing(e).texts
            switch i {
            case 0: #expect(texts == [Self.hello])
            case 1: #expect(texts.map(\.string) == ["Bye"])
            case 2: #expect(texts.map { "\($0.fontFamily) \($0.fontSize)" } == ["Courier 12.0"])
            default: #expect(texts.isEmpty)
            }
        }
    }

    @Test func lockedSymbolLayerAndMissingSymbolThrowWithoutChanges() {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers[0].shapes = [Self.tri]
        doc.symbols[0].layers[0].texts = [Self.hello]
        doc.symbols[0].layers[0].isLocked = true
        var engine = CommandEngine(document: doc)
        let edits: [any Command] = [
            AddShape(owner: Self.sym, layerID: "wing", shape: Self.tri),
            RemoveShape(owner: Self.sym, layerID: "wing", index: 0),
            SetShapeFill(owner: Self.sym, layerID: "wing", index: 0, fill: .solid(.white)),
            TranslateShape(owner: Self.sym, layerID: "wing", index: 0, dx: 1, dy: 1),
            AddTextShape(owner: Self.sym, layerID: "wing", text: Self.hello),
            RemoveTextShape(owner: Self.sym, layerID: "wing", index: 0),
            SetTextString(owner: Self.sym, layerID: "wing", index: 0, string: "x"),
            SetTextFont(owner: Self.sym, layerID: "wing", index: 0, family: "A", size: 9),
        ]
        for edit in edits {
            let e = edit
            #expect(throws: CommandError.layerLocked("wing"), "\(type(of: e).id)") { try engine.perform(e) }
        }
        #expect(throws: CommandError.symbolNotFound("ghost")) {
            try engine.perform(AddShape(owner: .symbol("ghost"), layerID: "wing", shape: Self.tri))
        }
        #expect(engine.document == doc)
        #expect(!engine.canUndo)
    }

    @Test func dragInsideASymbolMergesAndNeverMergesWithTheScene() throws {
        // Symbol "sym" holds a copy of the scene's "ball", and the scene's shape
        // already sits where the drag ends, so only the owner tells them apart.
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers.append(doc.scenes[0].layers[1])
        let start = try #require(doc.scenes[0].layers[1].shapes.first)
        doc.scenes[0].layers[1].shapes[0] = start.translated(dx: 10, dy: 0)
        var engine = CommandEngine(document: doc)
        for _ in 0..<10 {
            try engine.perform(TranslateShape(owner: Self.sym, layerID: "ball", index: 0, dx: 1, dy: 0),
                               coalesceKey: "drag")
        }
        let dragged = engine.document
        #expect(dragged.symbols[0].layers[2].shapes.first == start.translated(dx: 10, dy: 0))
        #expect(engine.undoStack.last?.commands.count == 1)
        try engine.perform(TranslateShape(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, dx: 0, dy: 5),
                           coalesceKey: "drag")
        #expect(engine.document.scenes[0].layers[1].shapes.first == start.translated(dx: 10, dy: 5))
        #expect(engine.document.symbols == dragged.symbols)
        let commands = try #require(engine.undoStack.last?.commands)
        #expect(commands.count == 2)
        #expect((commands.first as? TranslateShape)?.dx == 10)
        try engine.undo()
        #expect(engine.document == doc)
        #expect(!engine.canUndo)
    }

    /// Envelopes as written before shape and text commands took an owner.
    static let sceneEnvelopes = [
        #"{"id":"shape.add","params":{"layerID":"ball","sceneID":"s1","shape":{"closed":false,"#
            + #""fill":{"a":1,"b":0,"g":0,"r":0},"points":[{"x":1,"y":2},{"x":3,"y":4}]}}}"#,
        #"{"id":"shape.remove","params":{"index":0,"layerID":"ball","sceneID":"s1"}}"#,
        #"{"id":"shape.setFill","params":{"fill":{"a":1,"b":1,"g":0,"r":0},"index":0,"layerID":"ball","sceneID":"s1"}}"#,
        #"{"id":"shape.translate","params":{"dx":1.5,"dy":-2,"index":0,"layerID":"ball","sceneID":"s1"}}"#,
        #"{"id":"text.add","params":{"layerID":"ball","sceneID":"s1","text":{"fill":{"a":1,"b":0,"g":0,"r":0},"#
            + #""fontFamily":"Helvetica","fontSize":24,"position":{"x":10,"y":20},"string":"Hi"}}}"#,
        #"{"id":"text.remove","params":{"index":0,"layerID":"ball","sceneID":"s1"}}"#,
        #"{"id":"text.setString","params":{"index":0,"layerID":"ball","sceneID":"s1","string":"Bye"}}"#,
        #"{"id":"text.setFont","params":{"family":"Courier","index":0,"layerID":"ball","sceneID":"s1","size":12}}"#,
    ]

    @Test(arguments: sceneEnvelopes)
    func sceneEnvelopeStaysByteIdentical(_ json: String) throws {
        let command = try CommandRegistry.builtIn.decode(Data(json.utf8))
        #expect(try CommandRegistry.builtIn.encode(command) == Data(json.utf8))
        var engine = CommandEngine(document: TextCommandsTests.withText())
        try engine.perform(command)
        #expect(engine.document != TextCommandsTests.withText())
    }

    @Test(arguments: sceneEnvelopes)
    func symbolEnvelopeRoundTripsAndEditsTheSymbol(_ sceneJSON: String) throws {
        let json = sceneJSON.replacingOccurrences(of: #""sceneID":"s1""#, with: #""symbolID":"sym""#)
        let command = try CommandRegistry.builtIn.decode(Data(json.utf8))
        let reencoded = try JSONSerialization.jsonObject(with: CommandRegistry.builtIn.encode(command)) as? NSDictionary
        #expect(reencoded == (try JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary))
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers.append(TextCommandsTests.withText().scenes[0].layers[1])
        var engine = CommandEngine(document: doc)
        try engine.perform(command)
        #expect(engine.document.symbols != doc.symbols)
        #expect(engine.document.scenes == doc.scenes)
        try engine.undo()
        #expect(engine.document == doc)
    }
}
