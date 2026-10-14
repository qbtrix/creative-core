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

    /// One valid sample of each scene command, for CommandRegistryTests.
    static func registrySamples() -> [any Command] {
        [
            AddScene(scene: Scene(id: "s2", name: "Two", fps: 30, durationFrames: 60), index: 1),
            RemoveScene(sceneID: Fixtures.sceneID),
            SetSceneTiming(sceneID: Fixtures.sceneID, fps: 30, durationFrames: 90),
            SetSceneCanvas(sceneID: Fixtures.sceneID, width: 1920, height: 1080, background: Color(r: 0, g: 0.2, b: 0.4)),
        ]
    }

    /// A scene id from the document, or "missing".
    static func anyScene(_ e: CommandEngine, _ rng: inout SplitMix64) -> String {
        (e.document.scenes.map(\.id) + ["missing"]).randomElement(using: &rng) ?? "missing"
    }

    /// Random scene steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, nextID in
            nextID += 1
            let id = Bool.random(using: &rng) ? anyScene(e, &rng) : "S\(nextID)"
            let fps = Int.random(in: -1...60, using: &rng)
            let duration = Int.random(in: -1...30, using: &rng)
            try e.perform(AddScene(scene: Scene(id: id, name: "Scene \(nextID)", fps: fps, durationFrames: duration),
                                   index: Int.random(in: -2...5, using: &rng)))
        },
        { e, rng, _ in
            try e.perform(RemoveScene(sceneID: anyScene(e, &rng)))
        },
        { e, rng, _ in
            let scene = anyScene(e, &rng)
            try e.perform(SetSceneTiming(sceneID: scene, fps: Int.random(in: -1...60, using: &rng),
                                         durationFrames: Int.random(in: -1...30, using: &rng)))
        },
        { e, rng, _ in
            // Mostly valid sizes; sometimes zero, negative or NaN, or a NaN channel.
            let sizes: [Double] = [1, 64, 640, 1920, 0, -1, .nan]
            let w = sizes.randomElement(using: &rng) ?? 1
            let h = sizes[0..<4].randomElement(using: &rng) ?? 1
            let red = Int.random(in: 0..<4, using: &rng) == 0 ? .nan : Double.random(in: 0...1, using: &rng)
            try e.perform(SetSceneCanvas(sceneID: anyScene(e, &rng), width: w, height: h,
                                         background: Color(r: red, g: 0.5, b: 0.5)))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: Self.threeScenes())
    }
}
