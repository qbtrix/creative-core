// SceneEditCommandTests.swift: RenameScene and ReorderScene. Each undo returns
// the original document exactly; an empty name or an index outside the scene
// list throws before any change, so neither the document nor the undo stack moves.
import FlareCore
import Foundation
import Testing

@Suite struct SceneEditCommandTests {
    @Test func renameSceneAndUndoExactly() throws {
        let start = SceneCommandTests.threeScenes()
        try SceneCommandTests.roundTrip(RenameScene(sceneID: "s2", name: "Intro"), on: start) { doc in
            var expected = start
            expected.scenes[1].name = "Intro"
            #expect(doc == expected)
        }
    }

    @Test func renameSceneRejectsEmptyNameAndMissingScene() {
        let start = SceneCommandTests.threeScenes()
        SceneCommandTests.rejects(RenameScene(sceneID: "s1", name: ""), on: start, .emptyName)
        SceneCommandTests.rejects(RenameScene(sceneID: "nope", name: "X"), on: start, .sceneNotFound("nope"))
    }

    @Test func reorderFirstSceneToLastAndUndoExactly() throws {
        let start = SceneCommandTests.threeScenes()
        try SceneCommandTests.roundTrip(ReorderScene(sceneID: "s1", toIndex: 2), on: start) { doc in
            #expect(doc.scenes.map(\.id) == ["s2", "s3", "s1"])
            #expect(doc.scenes[2] == start.scenes[0])
        }
        try SceneCommandTests.roundTrip(ReorderScene(sceneID: "s3", toIndex: 0), on: start) { doc in
            #expect(doc.scenes.map(\.id) == ["s3", "s1", "s2"])
        }
        try SceneCommandTests.roundTrip(ReorderScene(sceneID: "s2", toIndex: 1), on: start) { doc in
            #expect(doc == start)
        }
    }

    @Test func reorderSceneRejectsOutOfRangeIndexAndMissingScene() {
        let start = SceneCommandTests.threeScenes()
        SceneCommandTests.rejects(ReorderScene(sceneID: "s1", toIndex: 3), on: start, .invalidIndex(3))
        SceneCommandTests.rejects(ReorderScene(sceneID: "s1", toIndex: -1), on: start, .invalidIndex(-1))
        SceneCommandTests.rejects(ReorderScene(sceneID: "nope", toIndex: 0), on: start, .sceneNotFound("nope"))
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = SceneCommandTests.threeScenes()
        #expect(throws: CommandError.notExecuted) { try RenameScene(sceneID: "s1", name: "X").undo(&doc) }
        #expect(throws: CommandError.notExecuted) { try ReorderScene(sceneID: "s1", toIndex: 2).undo(&doc) }
        #expect(doc == SceneCommandTests.threeScenes())
    }

    @Test func encodesParamsOnly() throws {
        let cases: [(any Command, Set<String>)] = [
            (RenameScene(sceneID: "s1", name: "Intro"), ["sceneID", "name"]),
            (ReorderScene(sceneID: "s1", toIndex: 2), ["sceneID", "toIndex"]),
        ]
        for (original, keys) in cases {
            var command = original
            var doc = SceneCommandTests.threeScenes()
            try command.execute(&doc)
            let data = try CommandRegistry.builtIn.encode(command)
            let params = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["params"] as? [String: Any]
            #expect(Set(params?.keys.map { $0 } ?? []) == keys)
            let decoded = try CommandRegistry.builtIn.decode(data)
            var copy = SceneCommandTests.threeScenes()
            #expect(throws: CommandError.notExecuted) { try decoded.undo(&copy) }
        }
    }
}
