// SceneBackgroundFiniteTests.swift: a scene background channel that is NaN or
// infinite is rejected (#196). AddScene throws and leaves the document and undo
// stack as they were, so the document still saves; validation rejects one on
// load too.
@testable import FlareCore
import Testing

@Suite struct SceneBackgroundFiniteTests {
    static let badColors: [Color] = [Double.nan, .infinity, -.infinity].flatMap { v in
        [Color(r: v, g: 0, b: 0), Color(r: 0, g: v, b: 0), Color(r: 0, g: 0, b: v), Color(r: 0, g: 0, b: 0, a: v)]
    }

    @Test(arguments: badColors)
    func nonFiniteBackgroundThrowsAndChangesNothing(_ color: Color) throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(RenameLayer(owner: .scene(Fixtures.sceneID), layerID: "ball", name: "Ball"))
        let before = e.document
        let add = AddScene(scene: Scene(id: "s9", name: "S9", background: color))
        #expect(throws: CommandError.invalidDocument("background color channels must be finite")) {
            try e.perform(add)
        }
        #expect(e.document == before)
        #expect(e.undoStack.count == 1)
        #expect(!e.canRedo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func finiteBackgroundAddsAndSaves() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let background = Color(r: 0.25, g: 0.5, b: 0.75, a: 0.5)
        try e.perform(AddScene(scene: Scene(id: "s9", name: "S9", background: background)))
        #expect(e.document.scenes.last?.background == background)
        #expect(try FlareFormat.decode(FlareFormat.encode(e.document)) == e.document)
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test(arguments: badColors)
    func documentWithNonFiniteBackgroundFailsValidation(_ color: Color) {
        var doc = ShapeTextOwnerTests.start()
        doc.scenes[0].background = color
        let message = "scene \(Fixtures.sceneID): background color channels must be finite"
        #expect(throws: FormatError.invalid(message)) { try FlareFormat.validate(doc) }
    }
}
