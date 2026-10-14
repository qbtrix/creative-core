// SceneCanvasCommandTests.swift: SetSceneCanvas sets a scene's canvas size and
// background, and undo restores the old ones exactly. A size that is not
// finite and > 0, or a non-finite background channel, throws invalidDocument
// before any change, so neither the document nor the undo stack moves.
import FlareCore
import Foundation
import Testing

@Suite struct SceneCanvasCommandTests {
    static let navy = Color(r: 0.05, g: 0.1, b: 0.3, a: 0.9)

    @Test func setsSizeAndBackgroundAndUndoesExactly() throws {
        let start = SceneCommandTests.threeScenes()
        let command = SetSceneCanvas(sceneID: "s2", width: 1920, height: 1080, background: Self.navy)
        try SceneCommandTests.roundTrip(command, on: start) { doc in
            var expected = start
            expected.scenes[1].width = 1920
            expected.scenes[1].height = 1080
            expected.scenes[1].background = Self.navy
            #expect(doc == expected)
        }
    }

    @Test func undoRestoresTheOldBackground() throws {
        var start = SceneCommandTests.threeScenes()
        start.scenes[0].background = Color(r: 0.25, g: 0.5, b: 0.75, a: 0.5)
        var engine = CommandEngine(document: start)
        try engine.perform(SetSceneCanvas(sceneID: "s1", width: start.scenes[0].width,
                                          height: start.scenes[0].height, background: Self.navy))
        try engine.undo()
        #expect(engine.document.scenes[0].background == Color(r: 0.25, g: 0.5, b: 0.75, a: 0.5))
        #expect(engine.document == start)
    }

    @Test func badSizeOrBackgroundThrowsBeforeAnyChange() {
        let start = SceneCommandTests.threeScenes()
        let size = CommandError.invalidDocument("scene s1: canvas size must be finite and > 0")
        for (w, h) in [(0.0, 1080.0), (-1, 1080), (.nan, 1080), (1920, 0), (1920, -1), (1920, .nan),
                       (.infinity, 1080), (1920, .infinity)] {
            SceneCommandTests.rejects(SetSceneCanvas(sceneID: "s1", width: w, height: h, background: Self.navy),
                                      on: start, size)
        }
        let color = CommandError.invalidDocument("background color channels must be finite")
        for bad in [Color(r: .nan, g: 0, b: 0), Color(r: 0, g: 0, b: 0, a: .infinity)] {
            SceneCommandTests.rejects(SetSceneCanvas(sceneID: "s1", width: 1920, height: 1080, background: bad),
                                      on: start, color)
        }
        SceneCommandTests.rejects(SetSceneCanvas(sceneID: "nope", width: 1920, height: 1080, background: Self.navy),
                                  on: start, .sceneNotFound("nope"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = SceneCommandTests.threeScenes()
        #expect(throws: CommandError.notExecuted) {
            try SetSceneCanvas(sceneID: "s1", width: 1, height: 1, background: .white).undo(&doc)
        }
        #expect(doc == SceneCommandTests.threeScenes())
    }

    @Test func encodesParamsOnly() throws {
        var command = SetSceneCanvas(sceneID: "s1", width: 1920, height: 1080, background: Self.navy)
        var doc = SceneCommandTests.threeScenes()
        try command.execute(&doc)
        let data = try CommandRegistry.builtIn.encode(command)
        let params = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["params"] as? [String: Any]
        #expect(Set(params?.keys.map { $0 } ?? []) == ["sceneID", "width", "height", "background"])
        let decoded = try CommandRegistry.builtIn.decode(data)
        var copy = SceneCommandTests.threeScenes()
        #expect(throws: CommandError.notExecuted) { try decoded.undo(&copy) }
    }
}
