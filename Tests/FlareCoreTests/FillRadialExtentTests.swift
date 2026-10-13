// FillRadialExtentTests.swift: a radial gradient whose center and radius are
// each finite but whose center.x ± radius overflows is rejected (#200), so a
// document that validates always exports to Lottie.
@testable import FlareCore
import Testing

@Suite struct FillRadialExtentTests {
    static let stops = FillPointFiniteTests.stops
    static let big = Double.greatestFiniteMagnitude

    static let overflowingFills: [Fill] = [
        .radial(stops: stops, center: Point(x: big, y: 0), radius: big),
        .radial(stops: stops, center: Point(x: 1e308, y: 0), radius: 1e308),
        .radial(stops: stops, center: Point(x: -1e308, y: 5), radius: 1e308),
    ]

    @Test(arguments: overflowingFills)
    func overflowingRadialGradientThrowsAndChangesNothing(_ fill: Fill) throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        try e.perform(RenameLayer(owner: .scene(Fixtures.sceneID), layerID: "ball", name: "Ball"))
        let before = e.document
        for (owner, layer) in [(LayerOwner.symbol("sym"), "wing"), (.scene(Fixtures.sceneID), "ball")] {
            for command in FillColorFiniteTests.commands(owner, layerID: layer, fill: fill) {
                #expect(throws: CommandError.invalidDocument("radial gradient center ± radius must be finite"),
                        "\(command.label) \(owner)") { try e.perform(command) }
                #expect(e.document == before)
                #expect(e.undoStack.count == 1)
            }
        }
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test func nearLimitRadialGradientValidatesAndExportsToLottie() throws {
        var e = CommandEngine(document: Fixtures.document())
        let fill = Fill.radial(stops: Self.stops, center: Point(x: Self.big / 2, y: -3), radius: Self.big / 2)
        try e.perform(SetShapeFill(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, fill: fill))
        let decoded = try FlareFormat.decode(FlareFormat.encode(e.document))
        #expect(decoded == e.document)
        let lottie = try LottieExporter.export(scene: e.document.scenes[0])
        #expect(!lottie.isEmpty)
        try e.undo()
        #expect(e.document == Fixtures.document())
    }

    @Test func documentWithOverflowingRadialGradientFailsValidation() throws {
        var doc = ShapeTextOwnerTests.start()
        doc.symbols[0].layers[0].texts[0].fill = .radial(stops: Self.stops, center: Point(x: Self.big, y: 0),
                                                         radius: Self.big)
        #expect(throws: FormatError.invalid("radial gradient center ± radius must be finite")) {
            try FlareFormat.validate(doc)
        }
    }
}
