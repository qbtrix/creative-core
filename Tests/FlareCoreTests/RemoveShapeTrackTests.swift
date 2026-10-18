// RemoveShapeTrackTests.swift: removing a shape or text takes its index-keyed
// tracks with it (fill.<i>, stroke.<i>, strokeWidth.<i>, the shape track, and
// text.<i>) and moves the tracks of later items down one, so animation stays
// on its shape; undo puts every track back exactly.
import FlareCore
import Testing

@Suite struct RemoveShapeTrackTests {
    static let owner = LayerOwner.scene(Fixtures.sceneID)
    static let (red, blue) = (Color(r: 1, g: 0, b: 0), Color(r: 0, g: 0, b: 1))
    static func keys(_ color: Color) -> [ColorKeyframe] { [ColorKeyframe(frame: 0, value: color), ColorKeyframe(frame: 24, value: blue)] }
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)
    static func shapeTrack(_ index: Int) -> ShapeTrack {
        ShapeTrack(shapeIndex: index, keys: [PathKeyframe(frame: 0, path: square), PathKeyframe(frame: 24, path: square)])
    }
    static func text(_ string: String) -> TextShape {
        TextShape(string: string, fontFamily: "Helvetica", fontSize: 24, position: Point(x: 10, y: 20), fill: .solid(red))
    }

    /// The fixture with ball holding shapes [A, B] and texts [T, U], and `edit` applied to ball.
    static func document(_ edit: (inout Layer) -> Void = { _ in }) -> Document {
        var doc = Fixtures.withSymbol()
        let a = doc.scenes[0].layers[1].shapes[0]
        var b = a.translated(dx: 20, dy: 0)
        b.fill = .solid(blue)
        doc.scenes[0].layers[1].shapes = [a, b]
        doc.scenes[0].layers[1].texts = [text("T"), text("U")]
        edit(&doc.scenes[0].layers[1])
        return doc
    }

    /// Performs `command`, checks the result validates, then undoes and checks
    /// the original comes back exactly. Returns the ball layer after the perform.
    static func performAndUndo(_ start: Document, _ command: any Command) throws -> Layer {
        var engine = CommandEngine(document: start)
        try engine.perform(command)
        try FlareFormat.validate(engine.document)
        let layer = try #require(engine.document.scenes[0].layers.first { $0.id == "ball" })
        try engine.undo()
        #expect(engine.document == start)
        return layer
    }

    @Test func removingTheHighestKeyedShapeDropsItsTracks() throws {
        let start = Self.document { l in
            l.colorTracks = ["fill.0": Self.keys(Self.red), "fill.1": Self.keys(Self.blue), "stroke.1": Self.keys(Self.red)]
            l.tracks["strokeWidth.1"] = [Keyframe(frame: 0, value: 2)]
            l.shapeTracks = [Self.shapeTrack(1), Self.shapeTrack(0)]
        }
        let layer = try Self.performAndUndo(start, RemoveShape(owner: Self.owner, layerID: "ball", index: 1))
        #expect(layer.colorTracks == ["fill.0": Self.keys(Self.red)])
        #expect(layer.tracks["strokeWidth.1"] == nil)
        #expect(layer.tracks["x"] == start.scenes[0].layers[1].tracks["x"])
        #expect(layer.shapeTracks == [Self.shapeTrack(0)])
    }

    @Test func removingALowerShapeDoesNotMoveItsTrackToTheNext() throws {
        let start = Self.document { $0.colorTracks = ["fill.0": Self.keys(Self.red)] }
        let layer = try Self.performAndUndo(start, RemoveShape(owner: Self.owner, layerID: "ball", index: 0))
        #expect(layer.colorTracks.isEmpty)
    }

    @Test func laterShapeTracksMoveDownWithTheirShape() throws {
        let start = Self.document { l in
            l.colorTracks = ["fill.0": Self.keys(Self.red), "stroke.1": Self.keys(Self.blue), "text.1": Self.keys(Self.red)]
            l.tracks["strokeWidth.1"] = [Keyframe(frame: 0, value: 3)]
            l.shapeTracks = [Self.shapeTrack(1)]
        }
        let layer = try Self.performAndUndo(start, RemoveShape(owner: Self.owner, layerID: "ball", index: 0))
        #expect(layer.colorTracks == ["stroke.0": Self.keys(Self.blue), "text.1": Self.keys(Self.red)])
        #expect(layer.tracks["strokeWidth.0"] == [Keyframe(frame: 0, value: 3)])
        #expect(layer.tracks["strokeWidth.1"] == nil)
        #expect(layer.shapeTracks == [Self.shapeTrack(0)])
    }

    @Test func removingATextDropsItsTrackAndMovesLaterOnesDown() throws {
        let only = Self.document { $0.colorTracks = ["text.0": Self.keys(Self.red), "fill.0": Self.keys(Self.blue)] }
        let dropped = try Self.performAndUndo(only, RemoveTextShape(owner: Self.owner, layerID: "ball", index: 0))
        #expect(dropped.colorTracks == ["fill.0": Self.keys(Self.blue)])

        let later = Self.document { $0.colorTracks = ["text.1": Self.keys(Self.red)] }
        let moved = try Self.performAndUndo(later, RemoveTextShape(owner: Self.owner, layerID: "ball", index: 0))
        #expect(moved.colorTracks == ["text.0": Self.keys(Self.red)])

        let highest = Self.document { $0.colorTracks = ["text.0": Self.keys(Self.blue), "text.1": Self.keys(Self.red)] }
        let kept = try Self.performAndUndo(highest, RemoveTextShape(owner: Self.owner, layerID: "ball", index: 1))
        #expect(kept.colorTracks == ["text.0": Self.keys(Self.blue)])
    }

    /// Ball with every kind of index-keyed track on shapes and texts 0 and 1.
    static func keyedDocument() -> Document {
        document { l in
            l.colorTracks = ["fill.0": keys(red), "fill.1": keys(blue), "stroke.1": keys(red),
                             "text.0": keys(blue), "text.1": keys(red)]
            l.tracks["strokeWidth.0"] = [Keyframe(frame: 0, value: 1)]
            l.tracks["strokeWidth.1"] = [Keyframe(frame: 0, value: 2)]
            l.shapeTracks = [shapeTrack(0), shapeTrack(1)]
        }
    }

    /// Random removals and colour and width keys on keyed shapes and texts, some invalid.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            try e.perform(RemoveShape(owner: owner, layerID: "ball", index: Int.random(in: -1...2, using: &rng)))
        },
        { e, rng, _ in
            try e.perform(RemoveTextShape(owner: owner, layerID: "ball", index: Int.random(in: -1...2, using: &rng)))
        },
        { e, rng, _ in
            let i = Int.random(in: 0...2, using: &rng)
            let target = [TrackTarget.fill(shape: i), .stroke(shape: i), .text(index: i)][Int.random(in: 0...2, using: &rng)]
            try e.perform(SetColorKeyframe(owner: owner, layerID: "ball", target: target,
                                           frame: Int.random(in: 0...48, using: &rng), value: red))
        },
        { e, rng, _ in
            let k = Keyframe(frame: Int.random(in: 0...48, using: &rng), value: Double.random(in: 0...8, using: &rng))
            try e.perform(SetKeyframe(owner: owner, layerID: "ball",
                                      property: "strokeWidth.\(Int.random(in: 0...1, using: &rng))", keyframe: k))
        },
    ]

    @Test(arguments: 0..<100)
    func undoRestoresKeyedRemovals(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps + ShapeCommandsTests.undoSteps
                                       + TextCommandsTests.undoSteps, start: Self.keyedDocument(), length: 20)
    }
}
