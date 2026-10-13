// FillColorFiniteTests.swift: a fill color channel that is NaN or infinite is
// rejected (#189). Shape and text commands on scene and symbol layers throw and
// leave the document and undo stack as they were; validation rejects one too.
@testable import FlareCore
import Testing

@Suite struct FillColorFiniteTests {
    static let badColors = [
        Color(r: .nan, g: 0, b: 0), Color(r: 0, g: .infinity, b: 0),
        Color(r: 0, g: 0, b: -.infinity), Color(r: 0, g: 0, b: 0, a: .nan),
    ]

    static func fills(_ color: Color) -> [Fill] {
        let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: color)]
        return [.solid(color),
                .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0)),
                .radial(stops: stops, center: Point(x: 0, y: 0), radius: 2)]
    }

    static func commands(_ owner: LayerOwner, layerID: String, fill: Fill) -> [any Command] {
        var text = TextCommandsTests.hello
        text.fill = fill
        return [
            SetShapeFill(owner: owner, layerID: layerID, index: 0, fill: fill),
            AddShape(owner: owner, layerID: layerID, shape: Shape(points: [Point(x: 1, y: 2)], fill: fill)),
            AddTextShape(owner: owner, layerID: layerID, text: text),
        ]
    }

    @Test(arguments: badColors)
    func nonFiniteFillColorThrowsAndChangesNothing(_ color: Color) throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(RenameLayer(owner: .scene(Fixtures.sceneID), layerID: "ball", name: "Ball"))
        let before = e.document
        for (owner, layer) in [(LayerOwner.symbol("sym"), "wing"), (.scene(Fixtures.sceneID), "ball")] {
            for fill in Self.fills(color) {
                for command in Self.commands(owner, layerID: layer, fill: fill) {
                    #expect(throws: CommandError.invalidDocument("color channels must be finite"),
                            "\(command.label) \(owner)") { try e.perform(command) }
                    #expect(e.document == before)
                    #expect(e.undoStack.count == 1)
                    #expect(!e.canRedo)
                }
            }
        }
        _ = try FlareFormat.encode(e.document)
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test func finiteFillColorsStillPass() throws {
        for fill in Self.fills(Color(r: 0.25, g: 0.5, b: 0.75, a: 0.5)) {
            try fill.validate()
        }
    }

    @Test func documentWithNaNTextFillFailsValidation() throws {
        var doc = ShapeTextOwnerTests.start()
        doc.symbols[0].layers[0].texts[0].fill = .solid(Color(r: .nan, g: 0, b: 0))
        #expect(throws: FormatError.invalid("color channels must be finite")) { try FlareFormat.validate(doc) }
    }
}
