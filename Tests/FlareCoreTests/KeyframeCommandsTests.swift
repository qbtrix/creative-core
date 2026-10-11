// KeyframeCommandsTests.swift: SetKeyframeEasing and ShiftKeyframes apply,
// undo and redo exactly, and invalid params throw without touching the document.
import FlareCore
import Foundation
import Testing

@Suite struct KeyframeCommandsTests {
    let s = Fixtures.sceneID

    @Test func setUndoRedo() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(SetKeyframeEasing(sceneID: s, layerID: "ball", property: "x", frame: 24, easing: .easeOut))
        let track = engine.document.scenes[0].layers[1].tracks["x"]
        #expect(track?[1] == Keyframe(frame: 24, value: 100, easing: .easeOut))
        #expect(track?[0] == original.scenes[0].layers[1].tracks["x"]?[0])
        #expect(engine.undoActionName == "Undo Set Keyframe Easing")
        let changed = engine.document

        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == changed)
    }

    @Test func missingKeyframeThrowsWithoutChanges() {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        #expect(throws: CommandError.keyframeNotFound(property: "x", frame: 5)) {
            try engine.perform(SetKeyframeEasing(sceneID: s, layerID: "ball", property: "x", frame: 5, easing: .ease))
        }
        #expect(throws: CommandError.keyframeNotFound(property: "y", frame: 0)) {
            try engine.perform(SetKeyframeEasing(sceneID: s, layerID: "ball", property: "y", frame: 0, easing: .ease))
        }
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.perform(SetKeyframeEasing(sceneID: s, layerID: "nope", property: "x", frame: 0, easing: .ease))
        }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        let cmd = SetKeyframeEasing(sceneID: s, layerID: "ball", property: "x", frame: 0, easing: .linear)
        #expect(throws: CommandError.notExecuted) { try cmd.undo(&doc) }
    }

    @Test func paramsRoundTripThroughJSON() throws {
        let cmd = SetKeyframeEasing(sceneID: s, layerID: "ball", property: "x", frame: 0,
                                    easing: .cubicBezier(x1: 0.1, y1: 0.2, x2: 0.3, y2: 0.4))
        var decoded = try JSONDecoder().decode(SetKeyframeEasing.self, from: JSONEncoder().encode(cmd))
        var doc = Fixtures.document()
        try decoded.execute(&doc)
        #expect(doc.scenes[0].layers[1].tracks["x"]?[0].easing == cmd.easing)
    }

    /// A ball layer with keyframes on two tracks: x at 0, 24; y at 10, 30.
    static func twoTrackDocument() -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].tracks["y"] = [Keyframe(frame: 10, value: 1), Keyframe(frame: 30, value: 2)]
        return doc
    }

    @Test func shiftUndoRedo() throws {
        var engine = CommandEngine(document: Self.twoTrackDocument())
        let original = engine.document
        try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 5, toFrame: 24, delta: 5))
        let tracks = engine.document.scenes[0].layers[1].tracks
        #expect(tracks["x"]?.map(\.frame) == [0, 29])
        #expect(tracks["y"]?.map(\.frame) == [15, 30])
        #expect(tracks["x"]?[1] == Keyframe(frame: 29, value: 100))
        #expect(tracks["x"]?[0] == original.scenes[0].layers[1].tracks["x"]?[0])
        #expect(engine.undoActionName == "Undo Shift Keyframes")
        let changed = engine.document

        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == changed)
    }

    @Test func shiftPastOutsideKeyframeKeepsTrackSorted() throws {
        var engine = CommandEngine(document: Self.twoTrackDocument())
        try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 0, toFrame: 10, delta: 40))
        let tracks = engine.document.scenes[0].layers[1].tracks
        #expect(tracks["x"]?.map(\.frame) == [24, 40])
        #expect(tracks["y"]?.map(\.frame) == [30, 50])
    }

    @Test func shiftInvalidThrowsWithoutChanges() {
        var engine = CommandEngine(document: Self.twoTrackDocument())
        let original = engine.document
        // y:10 -> 30 collides with y:30, which is outside 5...24.
        #expect(throws: CommandError.frameOccupied(property: "y", frame: 30)) {
            try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 5, toFrame: 24, delta: 20))
        }
        #expect(throws: CommandError.invalidFrame(-1)) {
            try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 0, toFrame: 5, delta: -1))
        }
        #expect(throws: CommandError.invalidFrame(24)) {
            try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 20, toFrame: 25, delta: Int.max))
        }
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.perform(ShiftKeyframes(sceneID: s, layerID: "nope", fromFrame: 0, toFrame: 5, delta: 1))
        }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func shiftWholeTrackOntoItselfIsAllowed() throws {
        var engine = CommandEngine(document: Self.twoTrackDocument())
        // Every y key is in range, so 10 -> 30 does not collide with the old 30.
        try engine.perform(ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 10, toFrame: 30, delta: 20))
        #expect(engine.document.scenes[0].layers[1].tracks["y"]?.map(\.frame) == [30, 50])
    }

    @Test func shiftUndoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        let cmd = ShiftKeyframes(sceneID: s, layerID: "ball", fromFrame: 0, toFrame: 5, delta: 1)
        #expect(throws: CommandError.notExecuted) { try cmd.undo(&doc) }
    }

    /// One valid sample of each keyframe command here, for CommandRegistryTests.
    static func registrySamples() -> [any Command] {
        [SetKeyframeEasing(sceneID: Fixtures.sceneID, layerID: "ball", property: "x", frame: 24, easing: .easeOut),
         ShiftKeyframes(sceneID: Fixtures.sceneID, layerID: "ball", fromFrame: 0, toFrame: 24, delta: 5)]
    }

    /// Random keyframe steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng), prop = UndoPropertyTests.anyProp(&rng)
            let easing: Easing = Bool.random(using: &rng) ? .easeIn : .linear
            try e.perform(SetKeyframeEasing(sceneID: Fixtures.sceneID, layerID: layer, property: prop,
                                            frame: Int.random(in: -1...30, using: &rng), easing: easing))
        },
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng)
            let from = Int.random(in: -1...30, using: &rng)
            try e.perform(ShiftKeyframes(sceneID: Fixtures.sceneID, layerID: layer, fromFrame: from,
                                         toFrame: from + Int.random(in: -2...20, using: &rng),
                                         delta: Int.random(in: -10...10, using: &rng)))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        // Mixed with the core steps so there are keyframes to change.
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps)
    }
}
