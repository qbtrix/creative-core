// CoalesceTests.swift: perform(_:coalesceKey:) merges consecutive same-key
// commands into one undo entry; a different or nil key, undo, redo or a group
// ends coalescing. Drags of a shape or a keyframe merge into one command.
@testable import FlareCore
import Testing

@Suite struct CoalesceTests {
    let s = Fixtures.sceneID

    /// Drags the "ball" x keyframe one frame per step, starting at `from`.
    func drag(_ engine: inout CommandEngine, from: Int, steps: Int, key: String?) throws {
        for i in 0..<steps {
            try engine.perform(
                MoveKeyframe(sceneID: s, layerID: "ball", property: "x", from: from + i, to: from + i + 1),
                coalesceKey: key)
        }
    }

    @Test func sameKeyIsOneUndoEntry() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try drag(&engine, from: 24, steps: 10, key: "drag")
        #expect(engine.document != original)
        try engine.undo()
        #expect(engine.document == original)
        #expect(!engine.canUndo)
        try engine.redo()
        let dragged = engine.document
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == dragged)
    }

    @Test func differentKeyStartsNewEntry() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try drag(&engine, from: 24, steps: 5, key: "a")
        let afterA = engine.document
        try drag(&engine, from: 29, steps: 5, key: "b")
        try engine.undo()
        #expect(engine.document == afterA)
        try engine.undo()
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func nilKeyNeverCoalesces() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try drag(&engine, from: 24, steps: 3, key: nil)
        for _ in 0..<3 { try engine.undo() }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func nilKeyBreaksARun() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try drag(&engine, from: 24, steps: 2, key: "k")
        let afterFirst = engine.document
        try drag(&engine, from: 26, steps: 1, key: nil)
        try drag(&engine, from: 27, steps: 2, key: "k")
        try engine.undo()
        try engine.undo()
        try engine.undo()
        #expect(!engine.canUndo)
        try engine.redo()
        #expect(engine.document == afterFirst)
    }

    @Test func undoEndsCoalescing() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(RenameLayer(sceneID: s, layerID: "ball", name: "Planet"))
        let renamed = engine.document
        try drag(&engine, from: 24, steps: 2, key: "k")
        try engine.undo()
        #expect(engine.document == renamed)
        // Same key again must not fold into the rename entry now on top.
        try drag(&engine, from: 24, steps: 2, key: "k")
        try engine.undo()
        #expect(engine.document == renamed)
        #expect(engine.undoActionName == "Undo Rename Layer")
    }

    @Test func redoEndsCoalescing() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try drag(&engine, from: 24, steps: 2, key: "k")
        let afterFirst = engine.document
        try engine.undo()
        try engine.redo()
        try drag(&engine, from: 26, steps: 2, key: "k")
        try engine.undo()
        #expect(engine.document == afterFirst)
    }

    @Test func groupEndsCoalescing() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try drag(&engine, from: 24, steps: 2, key: "k")
        let afterFirst = engine.document
        try engine.group("Nothing") { _ in }
        try drag(&engine, from: 26, steps: 2, key: "k")
        try engine.undo()
        #expect(engine.document == afterFirst)
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func keyIsIgnoredInsideAGroup() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.group("Drag") { e in
            try drag(&e, from: 24, steps: 3, key: "k")
        }
        try drag(&engine, from: 27, steps: 2, key: "k")
        #expect(engine.undoActionName == "Undo Move Keyframe")
        try engine.undo()
        #expect(engine.undoActionName == "Undo Drag")
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func shapeDragMergesIntoOneExactCommand() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        for _ in 0..<300 {
            try engine.perform(TranslateShape(sceneID: s, layerID: "ball", index: 0, dx: 0.1, dy: -0.3),
                               coalesceKey: "drag")
        }
        let dragged = engine.document
        let point = dragged.scenes.first?.layers.last?.shapes.first?.points.first
        #expect(point != original.scenes.first?.layers.last?.shapes.first?.points.first)
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        let merged = engine.undoStack.first?.commands.first as? TranslateShape
        #expect(abs((merged?.dx ?? 0) - 30) < 1e-9)
        #expect(abs((merged?.dy ?? 0) + 90) < 1e-9)
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == dragged)
        try FlareFormat.validate(engine.document)
    }

    @Test func keyframeDragMergesIntoOneCommand() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try drag(&engine, from: 24, steps: 10, key: "drag")
        let dragged = engine.document
        let merged = engine.undoStack.first?.commands
        #expect(merged?.count == 1)
        #expect((merged?.first as? MoveKeyframe).map { [$0.from, $0.to] } == [24, 34])
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document == dragged)
    }

    @Test func unrelatedCommandsInARunStaySeparate() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(TranslateShape(sceneID: s, layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "k")
        try drag(&engine, from: 24, steps: 2, key: "k")
        try engine.perform(TranslateShape(sceneID: s, layerID: "ball", index: 0, dx: 1, dy: 0), coalesceKey: "k")
        #expect(engine.undoStack.first?.commands.count == 3)
        try engine.undo()
        #expect(engine.document == original)
    }
}
