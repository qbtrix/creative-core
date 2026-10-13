// FillPointFiniteTests.swift: a gradient start, end or center with a NaN or
// infinite coordinate is rejected (#192). Shape and text commands on scene and
// symbol layers throw and leave the document and undo stack as they were.
@testable import FlareCore
import Testing

@Suite struct FillPointFiniteTests {
    static let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]
    static let origin = Point(x: 0, y: 0)

    static let badFills: [Fill] = [
        .linear(stops: stops, start: Point(x: .nan, y: 0), end: Point(x: 1, y: 0)),
        .linear(stops: stops, start: Point(x: 0, y: -.infinity), end: Point(x: 1, y: 0)),
        .linear(stops: stops, start: origin, end: Point(x: 1, y: .infinity)),
        .linear(stops: stops, start: origin, end: Point(x: .nan, y: 0)),
        .radial(stops: stops, center: Point(x: 0, y: .nan), radius: 2),
        .radial(stops: stops, center: Point(x: .infinity, y: 0), radius: 2),
    ]

    @Test(arguments: badFills)
    func nonFiniteGradientPointThrowsAndChangesNothing(_ fill: Fill) throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(RenameLayer(owner: .scene(Fixtures.sceneID), layerID: "ball", name: "Ball"))
        let before = e.document
        for (owner, layer) in [(LayerOwner.symbol("sym"), "wing"), (.scene(Fixtures.sceneID), "ball")] {
            for command in FillColorFiniteTests.commands(owner, layerID: layer, fill: fill) {
                #expect(throws: CommandError.invalidDocument("gradient points must be finite"),
                        "\(command.label) \(owner)") { try e.perform(command) }
                #expect(e.document == before)
                #expect(e.undoStack.count == 1)
                #expect(!e.canRedo)
            }
        }
        _ = try FlareFormat.encode(e.document)
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test func finiteGradientPointsStillSaveAndRoundTrip() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let linear = Fill.linear(stops: Self.stops, start: Point(x: -3, y: 1.5), end: Point(x: 4, y: 2))
        let radial = Fill.radial(stops: Self.stops, center: Point(x: 2, y: -1), radius: 3)
        try e.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: linear))
        try e.perform(SetShapeFill(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, fill: radial))
        let decoded = try FlareFormat.decode(FlareFormat.encode(e.document))
        #expect(decoded == e.document)
        #expect(decoded.symbols[0].layers[0].shapes[0].fill == linear)
    }

    @Test func documentWithNaNGradientCenterFailsValidation() throws {
        var doc = ShapeTextOwnerTests.start()
        doc.symbols[0].layers[0].texts[0].fill = .radial(stops: Self.stops, center: Point(x: .nan, y: 0), radius: 1)
        #expect(throws: FormatError.invalid("gradient points must be finite")) { try FlareFormat.validate(doc) }
    }
}
