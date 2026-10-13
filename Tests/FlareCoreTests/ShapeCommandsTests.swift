// ShapeCommandsTests.swift: RemoveShape, SetShapeFill and TranslateShape. Each
// undoes exactly; a bad index or locked layer throws and leaves the document as is.
import FlareCore
import Testing

@Suite struct ShapeCommandsTests {
    static let s = Fixtures.sceneID

    static func ball(_ e: CommandEngine) throws -> Layer {
        try #require(e.document.scenes.first?.layers.first { $0.id == "ball" })
    }

    @Test func removeShapeUndoRestores() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(RemoveShape(owner: .scene(Self.s), layerID: "ball", index: 0))
        #expect(try Self.ball(engine).shapes.isEmpty)
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(try Self.ball(engine).shapes.isEmpty)
    }

    @Test func removeShapeReinsertsAtSameIndex() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let tri = Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 1)])
        try engine.perform(AddShape(owner: .scene(Self.s), layerID: "ball", shape: tri))
        let before = engine.document
        try engine.perform(RemoveShape(owner: .scene(Self.s), layerID: "ball", index: 0))
        #expect(try Self.ball(engine).shapes == [tri])
        try engine.undo()
        #expect(engine.document == before)
    }

    @Test func setShapeFillUndoRestores() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(SetShapeFill(owner: .scene(Self.s), layerID: "ball", index: 0, fill: .solid(.white)))
        #expect(try Self.ball(engine).shapes.first?.fill == .solid(.white))
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func translateShapeMovesPointsAndPath() throws {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)), .line(to: Point(x: 1, y: 0)),
            .quad(control: Point(x: 2, y: 0), to: Point(x: 2, y: 1)),
            .cubic(control1: Point(x: 2, y: 2), control2: Point(x: 1, y: 2), to: Point(x: 0, y: 2)), .close,
        ])
        let shape = Shape(points: [Point(x: 0, y: 0)], path: path)
        let doc = Document(scenes: [Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L", shapes: [shape])])])
        var engine = CommandEngine(document: doc)
        try engine.perform(TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: 10, dy: -1))
        let moved = try #require(engine.document.scenes.first?.layers.first?.shapes.first)
        #expect(moved.points == [Point(x: 10, y: -1)])
        #expect(moved.path?.elements == [
            .move(to: Point(x: 10, y: -1)), .line(to: Point(x: 11, y: -1)),
            .quad(control: Point(x: 12, y: -1), to: Point(x: 12, y: 0)),
            .cubic(control1: Point(x: 12, y: 1), control2: Point(x: 11, y: 1), to: Point(x: 10, y: 1)), .close,
        ])
        try engine.undo()
        #expect(engine.document == doc)
    }

    @Test func translateUndoIsExactDespiteRounding() throws {
        let shape = Shape(points: [Point(x: 0.1, y: 0.7)])
        let doc = Document(scenes: [Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L", shapes: [shape])])])
        var engine = CommandEngine(document: doc)
        try engine.perform(TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: 0.2, dy: 1e16))
        try engine.undo()
        #expect(engine.document == doc)
    }

    static func edits(index: Int) -> [any Command] {
        [
            RemoveShape(owner: .scene(s), layerID: "ball", index: index),
            SetShapeFill(owner: .scene(s), layerID: "ball", index: index, fill: .solid(.white)),
            TranslateShape(owner: .scene(s), layerID: "ball", index: index, dx: 1, dy: 1),
        ]
    }

    @Test(arguments: [-1, 1, Int.max, Int.min])
    func badIndexThrowsWithoutChanges(index: Int) throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        for edit in Self.edits(index: index) {
            #expect(throws: CommandError.shapeNotFound(index)) { try engine.perform(edit) }
            #expect(engine.document == original)
        }
        #expect(!engine.canUndo)
    }

    @Test func lockedLayerRejectsShapeEdits() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: true))
        let locked = engine.document
        for edit in Self.edits(index: 0) {
            #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(edit) }
            #expect(engine.document == locked)
        }
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        #expect(throws: CommandError.notExecuted) {
            try RemoveShape(owner: .scene(Self.s), layerID: "ball", index: 0).undo(&doc)
        }
    }

    static func anyIndex(_ e: CommandEngine, _ owner: LayerOwner, _ layer: String, _ rng: inout SplitMix64) -> Int {
        let count = e.document.layers(of: owner)?.first { $0.id == layer }?.shapes.count ?? 0
        return Int.random(in: -1...count, using: &rng)
    }

    /// Random shape edit steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            try e.perform(RemoveShape(owner: owner, layerID: layer, index: anyIndex(e, owner, layer, &rng)))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let color = Color(r: Double.random(in: 0...1, using: &rng), g: 0, b: 1)
            let fill = Bool.random(using: &rng) ? Fill.solid(color)
                : .linear(stops: [GradientStop(offset: 0, color: color)], start: Point(x: 0, y: 0), end: Point(x: 1, y: 1))
            try e.perform(SetShapeFill(owner: owner, layerID: layer,
                                       index: anyIndex(e, owner, layer, &rng), fill: fill))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            try e.perform(TranslateShape(owner: owner, layerID: layer, index: anyIndex(e, owner, layer, &rng),
                                         dx: UndoPropertyTests.anyNumber(in: -50...50, &rng),
                                         dy: UndoPropertyTests.anyNumber(in: -50...50, &rng)),
                          coalesceKey: Bool.random(using: &rng) ? "drag" : nil)
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps)
    }
}
