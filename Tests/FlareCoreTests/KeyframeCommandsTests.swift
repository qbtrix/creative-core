// KeyframeCommandsTests.swift: SetKeyframeEasing sets, undoes and redoes
// exactly, and a missing keyframe throws without touching the document.
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

    /// One valid sample of each keyframe command here, for CommandRegistryTests.
    static func registrySamples() -> [any Command] {
        [SetKeyframeEasing(sceneID: Fixtures.sceneID, layerID: "ball", property: "x", frame: 24, easing: .easeOut)]
    }

    /// Random keyframe steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let layer = UndoPropertyTests.anyLayer(e, &rng), prop = UndoPropertyTests.anyProp(&rng)
            let easing: Easing = Bool.random(using: &rng) ? .easeIn : .linear
            try e.perform(SetKeyframeEasing(sceneID: Fixtures.sceneID, layerID: layer, property: prop,
                                            frame: Int.random(in: -1...30, using: &rng), easing: easing))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        // Mixed with the core steps so there are keyframes to change.
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps)
    }
}
