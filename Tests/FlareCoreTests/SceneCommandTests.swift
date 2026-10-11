// SceneCommandTests.swift: AddScene, RemoveScene and SetSceneTiming. Each undo
// returns the original document (scene order included); invalid params throw
// and leave the document unchanged.
import FlareCore
import Testing

@Suite struct SceneCommandTests {
    static func threeScenes() -> Document {
        var doc = Fixtures.document()
        doc.scenes.append(Scene(id: "s2", name: "Two", fps: 30, durationFrames: 60))
        doc.scenes.append(Scene(id: "s3", name: "Three", fps: 12, durationFrames: 0))
        return doc
    }

    /// Runs `command` through an engine, checks the effect, then undo and redo.
    static func roundTrip(_ command: some Command, on start: Document, check: (Document) -> Void) throws {
        var engine = CommandEngine(document: start)
        try engine.perform(command)
        let after = engine.document
        check(after)
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == after)
    }

    /// `command` throws `error` and the engine's document is untouched.
    static func rejects(_ command: some Command, on start: Document, _ error: CommandError) {
        var engine = CommandEngine(document: start)
        #expect(throws: error) { try engine.perform(command) }
        #expect(engine.document == start)
        #expect(!engine.canUndo)
    }

    @Test func addSceneInsertsAtIndexAndUndoes() throws {
        let start = Self.threeScenes()
        let new = Scene(id: "new", name: "New", fps: 25, durationFrames: 10)
        try Self.roundTrip(AddScene(scene: new, index: 1), on: start) {
            #expect($0.scenes.map(\.id) == ["s1", "new", "s2", "s3"])
        }
        try Self.roundTrip(AddScene(scene: new), on: start) {
            #expect($0.scenes.map(\.id) == ["s1", "s2", "s3", "new"])
        }
        try Self.roundTrip(AddScene(scene: new, index: -4), on: start) {
            #expect($0.scenes.map(\.id) == ["new", "s1", "s2", "s3"])
        }
        try Self.roundTrip(AddScene(scene: new, index: 99), on: start) {
            #expect($0.scenes.last == new)
        }
    }

    @Test func addSceneRejectsInvalidParams() {
        let start = Self.threeScenes()
        Self.rejects(AddScene(scene: Scene(id: "s2", name: "Dup")), on: start, .duplicateID("s2"))
        Self.rejects(AddScene(scene: Scene(id: "x", name: "X", fps: 0)), on: start, .invalidFPS(0))
        Self.rejects(AddScene(scene: Scene(id: "x", name: "X", fps: -3)), on: start, .invalidFPS(-3))
        Self.rejects(AddScene(scene: Scene(id: "x", name: "X", durationFrames: -1)), on: start, .invalidDuration(-1))
    }

    @Test func removeSceneRestoresOrder() throws {
        let start = Self.threeScenes()
        for (i, id) in ["s1", "s2", "s3"].enumerated() {
            try Self.roundTrip(RemoveScene(sceneID: id), on: start) {
                #expect($0.scenes.count == 2)
                #expect(!$0.scenes.contains { $0.id == id })
                #expect(start.scenes[i].id == id)
            }
        }
        Self.rejects(RemoveScene(sceneID: "nope"), on: start, .sceneNotFound("nope"))
    }

    @Test func setSceneTimingChangesOnlyTiming() throws {
        let start = Self.threeScenes()
        try Self.roundTrip(SetSceneTiming(sceneID: "s2", fps: 60, durationFrames: 0), on: start) { doc in
            #expect(doc.scenes[1].fps == 60)
            #expect(doc.scenes[1].durationFrames == 0)
            var expected = start
            expected.scenes[1].fps = 60
            expected.scenes[1].durationFrames = 0
            #expect(doc == expected)
        }
    }

    @Test func setSceneTimingRejectsInvalidParams() {
        let start = Self.threeScenes()
        Self.rejects(SetSceneTiming(sceneID: "s1", fps: 0, durationFrames: 10), on: start, .invalidFPS(0))
        Self.rejects(SetSceneTiming(sceneID: "s1", fps: -24, durationFrames: 10), on: start, .invalidFPS(-24))
        Self.rejects(SetSceneTiming(sceneID: "s1", fps: 24, durationFrames: -1), on: start, .invalidDuration(-1))
        Self.rejects(SetSceneTiming(sceneID: "nope", fps: 24, durationFrames: 1), on: start, .sceneNotFound("nope"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.threeScenes()
        #expect(throws: CommandError.notExecuted) { try RemoveScene(sceneID: "s1").undo(&doc) }
        #expect(throws: CommandError.notExecuted) {
            try SetSceneTiming(sceneID: "s1", fps: 1, durationFrames: 1).undo(&doc)
        }
        #expect(doc == Self.threeScenes())
    }
}
