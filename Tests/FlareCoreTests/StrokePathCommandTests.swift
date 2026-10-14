// StrokePathCommandTests.swift: SetShapeStroke sets, replaces and removes a
// stroke; SetShapePath replaces a shape's path and points together. Each undo
// is exact, bad widths and non-finite points throw before any change, and
// both work on symbol layers.
import FlareCore
import Testing

@Suite struct StrokePathCommandTests {
    static let s = Fixtures.sceneID
    static let widthError = CommandError.invalidDocument("stroke width must be finite and >= 0")
    static let pointError = CommandError.invalidDocument("shape has a non-finite point")

    static func shape(_ e: CommandEngine, _ owner: LayerOwner = .scene(s), _ layer: String = "ball") -> Shape? {
        e.document.layers(of: owner)?.first { $0.id == layer }?.shapes.first
    }

    static let cubic = Path(elements: [
        .move(to: Point(x: 0, y: 0)),
        .cubic(control1: Point(x: 0.1, y: 5), control2: Point(x: 9.7, y: 5), to: Point(x: 10, y: 0)), .close,
    ])
    static let cubicPoints = [Point(x: 0, y: 0), Point(x: 10, y: 0)]

    @Test func strokeSetsReplacesAndRemovesEachUndoExact() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let thin = Stroke(color: Color(r: 0.2, g: 0.4, b: 0.6), width: 1.5, join: .round, cap: .square)
        let thick = Stroke(width: 8, join: .bevel)
        for stroke in [thin, thick, nil] {
            let before = engine.document
            try engine.perform(SetShapeStroke(owner: .scene(Self.s), layerID: "ball", index: 0, stroke: stroke))
            #expect(Self.shape(engine)?.stroke == stroke)
            try engine.undo()
            #expect(engine.document == before)
            try engine.redo()
            #expect(Self.shape(engine)?.stroke == stroke)
        }
        #expect(Self.shape(engine)?.stroke == nil)
        try engine.undo()
        #expect(Self.shape(engine)?.stroke == thick)
    }

    @Test(arguments: [-1.0, Double.nan, Double.infinity])
    func badStrokeWidthThrowsAndChangesNothing(width: Double) throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        let edit = SetShapeStroke(owner: .scene(Self.s), layerID: "ball", index: 0, stroke: Stroke(width: width))
        #expect(throws: Self.widthError) { try engine.perform(edit) }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
        var command = edit
        var doc = original
        #expect(throws: ModelError.invalidStroke("stroke width must be finite and >= 0")) { try command.execute(&doc) }
        #expect(doc == original)
    }

    @Test func pathSetsCubicAndPointsUndoRestoresBoth() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(SetShapePath(owner: .scene(Self.s), layerID: "ball", index: 0,
                                        path: Self.cubic, points: Self.cubicPoints))
        #expect(Self.shape(engine)?.path == Self.cubic)
        #expect(Self.shape(engine)?.points == Self.cubicPoints)
        let edited = engine.document
        try engine.perform(SetShapePath(owner: .scene(Self.s), layerID: "ball", index: 0,
                                        path: nil, points: [Point(x: 1, y: 1)]))
        try engine.undo()
        #expect(engine.document == edited)
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == edited)
    }

    @Test(arguments: [
        (Path?.none, [Point(x: .nan, y: 0)]),
        (Path(elements: [.move(to: Point(x: 0, y: 0)),
                         .cubic(control1: Point(x: 1, y: .nan), control2: Point(x: 2, y: 2), to: Point(x: 3, y: 0))]),
         [Point(x: 0, y: 0)]),
        (Path(elements: [.move(to: Point(x: .infinity, y: 0))]), [Point]()),
    ])
    func nonFinitePointThrowsAndChangesNothing(path: Path?, points: [Point]) throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        let edit = SetShapePath(owner: .scene(Self.s), layerID: "ball", index: 0, path: path, points: points)
        #expect(throws: Self.pointError) { try engine.perform(edit) }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func badIndexThrowsShapeNotFound() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        let edits: [any Command] = [
            SetShapeStroke(owner: .scene(Self.s), layerID: "ball", index: 1, stroke: Stroke()),
            SetShapePath(owner: .scene(Self.s), layerID: "ball", index: 1, path: Self.cubic, points: []),
        ]
        for edit in edits {
            #expect(throws: CommandError.shapeNotFound(1)) { try engine.perform(edit) }
        }
        #expect(engine.document == original)
    }

    @Test func bothWorkOnSymbolLayer() throws {
        let start = ShapeTextOwnerTests.start()
        var engine = CommandEngine(document: start)
        let sym = LayerOwner.symbol("sym")
        try engine.perform(SetShapeStroke(owner: sym, layerID: "wing", index: 0, stroke: Stroke(width: 3)))
        try engine.perform(SetShapePath(owner: sym, layerID: "wing", index: 0, path: Self.cubic, points: Self.cubicPoints))
        let shape = Self.shape(engine, sym, "wing")
        #expect(shape?.stroke == Stroke(width: 3))
        #expect(shape?.path == Self.cubic)
        #expect(shape?.points == Self.cubicPoints)
        #expect(engine.document.scenes == start.scenes)
        try engine.undo()
        try engine.undo()
        #expect(engine.document == start)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        #expect(throws: CommandError.notExecuted) {
            try SetShapeStroke(owner: .scene(Self.s), layerID: "ball", index: 0, stroke: nil).undo(&doc)
        }
        #expect(throws: CommandError.notExecuted) {
            try SetShapePath(owner: .scene(Self.s), layerID: "ball", index: 0, path: nil, points: []).undo(&doc)
        }
    }

    @Test func bothAreRegisteredAndSampled() {
        let ids = ShapeCommands.all.map { $0.id }
        #expect(ids.contains("shape.setStroke"))
        #expect(ids.contains("shape.setPath"))
        let sampled = Set(CommandRegistryTests.samples().map { type(of: $0).id })
        #expect(sampled.isSuperset(of: ["shape.setStroke", "shape.setPath"]))
    }
}
