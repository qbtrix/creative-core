// TextCommandsTests.swift: the text commands undo exactly; a bad size, bad
// index or locked layer throws and leaves the document as is; files without
// text re-encode byte-stable; validate rejects a bad size; exporters throw.
import FlareCore
import Foundation
import Testing

@Suite struct TextCommandsTests {
    static let s = Fixtures.sceneID
    static let hello = TextShape(string: "Hello", fontFamily: "Helvetica", fontSize: 24,
                                 position: Point(x: 10, y: 20), fill: .solid(Color(r: 1, g: 0, b: 0)))

    /// The fixture with `hello` on the ball layer.
    static func withText() -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].texts = [hello]
        return doc
    }

    @Test func addEditRemoveEachUndoExactly() throws {
        var engine = CommandEngine(document: Fixtures.document())
        var history = [engine.document]
        try engine.perform(AddTextShape(owner: .scene(Self.s), layerID: "ball", text: Self.hello))
        history.append(engine.document)
        try engine.perform(SetTextString(owner: .scene(Self.s), layerID: "ball", index: 0, string: "Bye"))
        history.append(engine.document)
        try engine.perform(SetTextFont(owner: .scene(Self.s), layerID: "ball", index: 0, family: "Courier", size: 9.5))
        history.append(engine.document)
        var edited = Self.hello
        (edited.string, edited.fontFamily, edited.fontSize) = ("Bye", "Courier", 9.5)
        #expect(engine.document.scenes.first?.layers.last?.texts == [edited])
        try engine.perform(RemoveTextShape(owner: .scene(Self.s), layerID: "ball", index: 0))
        #expect(engine.document.scenes.first?.layers.last?.texts == [])
        while let previous = history.popLast() {
            try engine.undo()
            #expect(engine.document == previous)
        }
        #expect(!engine.canUndo)
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity])
    func badFontSizeThrowsWithoutChanges(size: Double) {
        var bad = Self.hello
        bad.fontSize = size
        var engine = CommandEngine(document: Self.withText())
        #expect(throws: CommandError.self) {
            try engine.perform(AddTextShape(owner: .scene(Self.s), layerID: "ball", text: bad))
        }
        #expect(throws: CommandError.self) {
            try engine.perform(SetTextFont(owner: .scene(Self.s), layerID: "ball", index: 0, family: "X", size: size))
        }
        #expect(engine.document == Self.withText())
        #expect(!engine.canUndo)
    }

    @Test func badIndexAndLockedLayerThrow() {
        let start = Self.withText()
        SceneCommandTests.rejects(RemoveTextShape(owner: .scene(Self.s), layerID: "ball", index: 1), on: start,
                                  .shapeNotFound(1))
        SceneCommandTests.rejects(SetTextString(owner: .scene(Self.s), layerID: "ball", index: -1, string: "x"), on: start,
                                  .shapeNotFound(-1))
        var locked = start
        locked.scenes[0].layers[1].isLocked = true
        let addToBall = AddTextShape(owner: .scene(Self.s), layerID: "ball", text: Self.hello)
        for command in Self.registrySamples().dropFirst() + [addToBall] {
            var engine = CommandEngine(document: locked)
            #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(command) }
            #expect(engine.document == locked)
        }
    }

    @Test func textEncodingAndExport() throws {
        let original = try FlareFormat.encode(Fixtures.document())
        #expect(!(String(data: original, encoding: .utf8) ?? "texts").contains("texts"))
        #expect(try FlareFormat.encode(FlareFormat.decode(original)) == original)
        let data = try FlareFormat.encode(Self.withText())
        #expect(try FlareFormat.decode(data) == Self.withText())
        // Exporters throw rather than drop the text.
        let scene = Self.withText().scenes[0]
        #expect(throws: SVGExportError.unsupported("text")) { try SVGExporter.export(scene: scene, frame: 0) }
        #expect(throws: LottieExportError.unsupported("text")) { try LottieExporter.export(scene: scene) }
    }

    @Test(arguments: ["0", "-3", "1e999"])
    func validateRejectsBadFontSize(size: String) throws {
        let good = try #require(String(data: try FlareFormat.encode(Self.withText()), encoding: .utf8))
        #expect(good.contains("\"fontSize\" : 24"))
        let bad = good.replacingOccurrences(of: "\"fontSize\" : 24", with: "\"fontSize\" : \(size)")
        #expect(throws: FormatError.self) { try FlareFormat.decode(Data(bad.utf8)) }
        var doc = Self.withText()
        doc.scenes[0].layers[1].texts[0].fontSize = .nan
        #expect(throws: FormatError.invalid("font size must be finite and > 0")) { try FlareFormat.validate(doc) }
    }

    /// One sample of each text command for CommandRegistryTests, valid on its sample document.
    static func registrySamples() -> [any Command] {
        [
            AddTextShape(owner: .scene(s), layerID: "bg", text: hello),
            RemoveTextShape(owner: .scene(s), layerID: "ball", index: 0),
            SetTextString(owner: .scene(s), layerID: "ball", index: 0, string: "Hi"),
            SetTextFont(owner: .scene(s), layerID: "ball", index: 0, family: "Courier", size: 12),
        ]
    }

    static func anyIndex(_ e: CommandEngine, _ layer: String, _ rng: inout SplitMix64) -> Int {
        let count = e.document.scenes.first?.layers.first { $0.id == layer }?.texts.count ?? 0
        return Int.random(in: -1...count, using: &rng)
    }

    /// Random text steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let text = TextShape(string: "t\(nextID)", fontFamily: "F",
                                 fontSize: UndoPropertyTests.anyNumber(in: -1...72, &rng),
                                 position: Point(x: UndoPropertyTests.anyNumber(in: -50...50, &rng), y: 0))
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            try e.perform(AddTextShape(owner: owner, layerID: layer, text: text))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            try e.perform(RemoveTextShape(owner: .scene(s), layerID: layer, index: anyIndex(e, layer, &rng)))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            try e.perform(SetTextString(owner: .scene(s), layerID: layer, index: anyIndex(e, layer, &rng), string: "s"))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            try e.perform(SetTextFont(owner: .scene(s), layerID: layer, index: anyIndex(e, layer, &rng), family: "A",
                                      size: UndoPropertyTests.anyNumber(in: -1...72, &rng)))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps,
                                       start: Self.withText())
    }
}
