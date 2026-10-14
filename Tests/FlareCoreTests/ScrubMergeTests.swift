// ScrubMergeTests.swift: an inspector scrub (SetKeyframe steps on one key
// under one coalesce key) is one undo entry holding one command that keeps the
// key from before the first step and takes the last value. Steps for another
// owner, layer, property or frame do not merge into it.
@testable import FlareCore
import Foundation
import Testing

@Suite struct ScrubMergeTests {
    static let owner = LayerOwner.scene(Fixtures.sceneID)

    static func step(_ i: Int, frame: Int) -> SetKeyframe {
        SetKeyframe(owner: owner, layerID: "ball", property: "x",
                    keyframe: Keyframe(frame: frame, value: Double(i) * 0.5, easing: .easeIn))
    }

    /// Scrubs 200 steps on `frame` and checks one entry with one command whose
    /// encoding holds the last value, then one undo gives back the original.
    func scrub(frame: Int) throws -> (before: Document, afterUndo: Document) {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        for i in 1...200 {
            try engine.perform(Self.step(i, frame: frame), coalesceKey: "scrub")
        }
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        #expect(engine.document.scenes.first?.layers.last?.keyframe(at: frame, property: "x")?.value == 100)

        let command = try #require(engine.undoStack.first?.commands.first)
        let data = try CommandRegistry.builtIn.encode(command)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let params = object?["params"] as? [String: Any]
        let keyframe = params?["keyframe"] as? [String: Any]
        #expect(keyframe?["value"] as? Double == 100)
        #expect(keyframe?["frame"] as? Int == frame)

        try engine.undo()
        #expect(!engine.canUndo)
        let afterUndo = engine.document
        try engine.redo()
        #expect(engine.document.scenes.first?.layers.last?.keyframe(at: frame, property: "x")?.value == 100)
        return (original, afterUndo)
    }

    @Test func twoHundredStepsAreOneCommand() throws {
        // Frame 24 already holds a key (value 100, linear): undo restores it.
        let existing = try scrub(frame: 24)
        #expect(existing.afterUndo == existing.before)
        let restored = existing.afterUndo.scenes.first?.layers.last?.keyframe(at: 24, property: "x")
        #expect(restored == Keyframe(frame: 24, value: 100))

        // Frame 12 holds none: undo removes the scrubbed key.
        let fresh = try scrub(frame: 12)
        #expect(fresh.afterUndo == fresh.before)
        #expect(fresh.afterUndo.scenes.first?.layers.last?.keyframe(at: 12, property: "x") == nil)
    }

    @Test func mergeDecidesOnParamsOnly() {
        var a = Self.step(1, frame: 6)
        let same = a.merge(Self.step(2, frame: 6))
        #expect(same)
        #expect(a.keyframe == Keyframe(frame: 6, value: 1, easing: .easeIn))

        let others = [
            SetKeyframe(owner: .symbol(Fixtures.sceneID), layerID: "ball", property: "x",
                        keyframe: Keyframe(frame: 6, value: 9)),
            SetKeyframe(owner: Self.owner, layerID: "bg", property: "x", keyframe: Keyframe(frame: 6, value: 9)),
            SetKeyframe(owner: Self.owner, layerID: "ball", property: "y", keyframe: Keyframe(frame: 6, value: 9)),
            SetKeyframe(owner: Self.owner, layerID: "ball", property: "x", keyframe: Keyframe(frame: 7, value: 9)),
        ]
        for other in others {
            var b = a
            let merged = b.merge(other)
            #expect(!merged)
            #expect(b.keyframe == a.keyframe)
        }
    }
}
