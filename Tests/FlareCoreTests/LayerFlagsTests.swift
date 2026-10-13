// LayerFlagsTests.swift: Layer isVisible and isLocked. Old v1 files get the
// defaults, SetLayerFlags undoes exactly, and a locked layer rejects content
// edits until it is unlocked.
import FlareCore
import Foundation
import Testing

@Suite struct LayerFlagsTests {
    static let s = Fixtures.sceneID

    @Test func v1FileWithoutFlagsGetsDefaults() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,
           "layers":[{"id":"l","name":"L","shapes":[],"tracks":{}}]}]}}
        """#
        let layer = try #require(try FlareFormat.decode(Data(json.utf8)).scenes.first?.layers.first)
        #expect(layer.isVisible)
        #expect(!layer.isLocked)
    }

    @Test func flagsRoundTrip() throws {
        let layer = Layer(id: "l", name: "L", isVisible: false, isLocked: true)
        let doc = Document(scenes: [Scene(id: "s", name: "S", layers: [layer])])
        #expect(try FlareFormat.decode(FlareFormat.encode(doc)) == doc)
    }

    @Test func undoOfSetLayerFlagsRestores() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isVisible: false, isLocked: true))
        let ball = try #require(engine.document.scenes.first?.layers.first { $0.id == "ball" })
        #expect(!ball.isVisible)
        #expect(ball.isLocked)
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func nilFlagIsLeftUnchanged() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: true))
        let ball = try #require(engine.document.scenes.first?.layers.first { $0.id == "ball" })
        #expect(ball.isVisible)
        #expect(ball.isLocked)
    }

    @Test func missingLayerThrows() {
        var engine = CommandEngine(document: Fixtures.document())
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "nope", isLocked: true))
        }
    }

    @Test func lockedLayerRejectsSetKeyframeUntilUnlocked() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: true))
        let locked = engine.document
        let set = SetKeyframe(sceneID: Self.s, layerID: "ball", property: "y", keyframe: Keyframe(frame: 5, value: 1))
        #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(set) }
        #expect(engine.document == locked)

        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: false))
        try engine.perform(set)
        let ball = try #require(engine.document.scenes.first?.layers.first { $0.id == "ball" })
        #expect(ball.tracks["y"] == [Keyframe(frame: 5, value: 1)])
    }

    @Test func lockedLayerRejectsEveryContentEdit() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: true))
        let locked = engine.document
        let edits: [any Command] = [
            SetKeyframe(sceneID: Self.s, layerID: "ball", property: "x", keyframe: Keyframe(frame: 0, value: 9)),
            MoveKeyframe(sceneID: Self.s, layerID: "ball", property: "x", from: 0, to: 5),
            RemoveKeyframe(sceneID: Self.s, layerID: "ball", property: "x", frame: 0),
            SetKeyframeEasing(sceneID: Self.s, layerID: "ball", property: "x", frame: 0, easing: .linear),
            ShiftKeyframes(sceneID: Self.s, layerID: "ball", fromFrame: 0, toFrame: 30, delta: 1),
            AddShape(owner: .scene(Self.s), layerID: "ball", shape: Shape(points: [Point(x: 0, y: 0)])),
        ]
        for edit in edits {
            #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(edit) }
            #expect(engine.document == locked)
        }
        // Rename and visibility still work on a locked layer.
        try engine.perform(RenameLayer(owner: .scene(Self.s), layerID: "ball", name: "B"))
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isVisible: false))
    }

    @Test func undoOfEditWorksAfterLockIsUndone() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(AddShape(owner: .scene(Self.s), layerID: "ball", shape: Shape(points: [Point(x: 1, y: 1)])))
        try engine.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isLocked: true))
        try engine.undo()
        try engine.undo()
        #expect(engine.document == original)
    }

    /// Random flag steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let visible: Bool? = Bool.random(using: &rng) ? Bool.random(using: &rng) : nil
            try e.perform(SetLayerFlags(owner: owner, layerID: layer, isVisible: visible,
                                        isLocked: Bool.random(using: &rng)))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps)
    }
}
