// LabelCommandsTests.swift: SetFrameLabel and RemoveFrameLabel. Labels must
// sit in 0...durationFrames; invalid params throw and leave the document
// unchanged; old files decode with no labels; validate rejects stray labels.
import FlareCore
import Foundation
import Testing

@Suite struct LabelCommandsTests {
    static func labelled() -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].labels["end"] = 48
        return doc
    }

    @Test func setLabelUndoRedo() throws {
        let start = Fixtures.document()
        try SceneCommandTests.roundTrip(SetFrameLabel(sceneID: Fixtures.sceneID, name: "hit", frame: 12), on: start) {
            #expect($0.scenes.first?.labels == ["start": 0, "hit": 12])
        }
    }

    @Test func setExistingLabelMovesItAndUndoes() throws {
        let start = Self.labelled()
        try SceneCommandTests.roundTrip(SetFrameLabel(sceneID: Fixtures.sceneID, name: "start", frame: 5), on: start) {
            #expect($0.scenes.first?.labels == ["start": 5, "end": 48])
        }
    }

    @Test func removeLabelUndoRedo() throws {
        let start = Self.labelled()
        try SceneCommandTests.roundTrip(RemoveFrameLabel(sceneID: Fixtures.sceneID, name: "start"), on: start) {
            #expect($0.scenes.first?.labels == ["end": 48])
        }
    }

    @Test func invalidParamsThrowWithoutChanges() {
        let start = Self.labelled()
        SceneCommandTests.rejects(SetFrameLabel(sceneID: Fixtures.sceneID, name: "x", frame: 49), on: start,
                                  .invalidFrame(49))
        SceneCommandTests.rejects(SetFrameLabel(sceneID: Fixtures.sceneID, name: "x", frame: -1), on: start,
                                  .invalidFrame(-1))
        SceneCommandTests.rejects(SetFrameLabel(sceneID: "missing", name: "x", frame: 1), on: start,
                                  .sceneNotFound("missing"))
        SceneCommandTests.rejects(RemoveFrameLabel(sceneID: Fixtures.sceneID, name: "nope"), on: start,
                                  .labelNotFound("nope"))
    }

    @Test func oldFileDecodesWithNoLabels() throws {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[]}]}}
        """#
        let scene = try #require(try FlareFormat.decode(Data(json.utf8)).scenes.first)
        #expect(scene.labels.isEmpty)
    }

    @Test func labelsRoundTripByteStable() throws {
        let doc = Self.labelled()
        let first = try FlareFormat.encode(doc)
        #expect(try FlareFormat.decode(first) == doc)
        #expect(try FlareFormat.encode(FlareFormat.decode(first)) == first)
    }

    @Test(arguments: [-1, 11])
    func validateRejectsLabelOutsideScene(frame: Int) {
        let json = #"""
        {"format":"flare","version":1,
         "document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":10,"layers":[],
           "labels":{"bad":\#(frame)}}]}}
        """#
        #expect {
            try FlareFormat.decode(Data(json.utf8))
        } throws: { error in
            guard case FormatError.invalid = error else { return false }
            return true
        }
    }

    /// One sample of each label command for CommandRegistryTests, valid on the fixture.
    static func registrySamples() -> [any Command] {
        [
            SetFrameLabel(sceneID: Fixtures.sceneID, name: "hit", frame: 12),
            RemoveFrameLabel(sceneID: Fixtures.sceneID, name: "start"),
        ]
    }

    /// Random label steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let name = ["start", "a", "b"].randomElement(using: &rng) ?? "a"
            try e.perform(SetFrameLabel(sceneID: Fixtures.sceneID, name: name,
                                        frame: Int.random(in: -2...50, using: &rng)))
        },
        { e, rng, _ in
            let name = ["start", "a", "b"].randomElement(using: &rng) ?? "a"
            try e.perform(RemoveFrameLabel(sceneID: Fixtures.sceneID, name: name))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps)
    }
}
