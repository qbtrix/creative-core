// StrokeColorFiniteTests.swift: a stroke color channel that is NaN or infinite
// is rejected (#193). AddShape on scene and symbol layers throws and leaves the
// document and undo stack as they were; validation rejects one on load too.
@testable import FlareCore
import Testing

@Suite struct StrokeColorFiniteTests {
    static func shape(_ stroke: Stroke) -> Shape {
        Shape(points: [Point(x: 1, y: 2)], stroke: stroke)
    }

    @Test(arguments: FillColorFiniteTests.badColors)
    func nonFiniteStrokeColorThrowsAndChangesNothing(_ color: Color) throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(RenameLayer(owner: .scene(Fixtures.sceneID), layerID: "ball", name: "Ball"))
        let before = e.document
        for (owner, layer) in [(LayerOwner.symbol("sym"), "wing"), (.scene(Fixtures.sceneID), "ball")] {
            let add = AddShape(owner: owner, layerID: layer, shape: Self.shape(Stroke(color: color)))
            #expect(throws: CommandError.invalidDocument("color channels must be finite"), "\(owner)") {
                try e.perform(add)
            }
            #expect(e.document == before)
            #expect(e.undoStack.count == 1)
            #expect(!e.canRedo)
        }
        _ = try FlareFormat.encode(e.document)
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test func nonFiniteStrokeWidthThrowsBeforePerform() {
        #expect(throws: ModelError.invalidStroke("stroke width must be finite and >= 0")) {
            try Stroke(width: .nan).validate()
        }
    }

    @Test func finiteStrokeAddsAndSaves() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let stroke = Stroke(color: Color(r: 0.25, g: 0.5, b: 0.75, a: 0.5), width: 2)
        try e.perform(AddShape(owner: .scene(Fixtures.sceneID), layerID: "ball", shape: Self.shape(stroke)))
        #expect(e.document.scenes[0].layers[1].shapes.last?.stroke == stroke)
        let decoded = try FlareFormat.decode(FlareFormat.encode(e.document))
        #expect(decoded == e.document)
    }

    @Test func documentWithNaNStrokeColorFailsValidation() {
        var doc = ShapeTextOwnerTests.start()
        doc.symbols[0].layers[0].shapes[0].stroke = Stroke(color: Color(r: 0, g: 0, b: 0, a: .infinity))
        #expect(throws: FormatError.invalid("color channels must be finite")) { try FlareFormat.validate(doc) }
    }
}
