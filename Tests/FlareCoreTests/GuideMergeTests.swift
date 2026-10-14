// GuideMergeTests.swift: a guide drag (MoveGuide steps under one coalesce key)
// is one undo entry holding one command that keeps the first old position and
// takes the last new one. Steps for another guide index or another scene do
// not merge into it.
@testable import FlareCore
import Testing

@Suite struct GuideMergeTests {
    /// The fixture with guides at x = 100 and y = 50, and a second scene with a
    /// guide at x = 7.
    static func guided() -> Document {
        var doc = GuideCommandsTests.guided()
        var two = Scene(id: "s2", name: "Two", fps: 30, durationFrames: 60)
        two.guides = [Guide(axis: .vertical, position: 7)]
        doc.scenes.append(two)
        return doc
    }

    @Test func fiftyStepDragIsOneCommandWithFirstOldAndLastNew() throws {
        var engine = CommandEngine(document: Self.guided())
        let original = engine.document
        for i in 1...50 {
            try engine.perform(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: 100 + Double(i) * 3),
                               coalesceKey: "guide-drag")
        }
        #expect(engine.document.scenes.first?.guides.first?.position == 250)
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        let merged = engine.undoStack.first?.commands.first as? MoveGuide
        #expect(merged?.oldPosition == 100)
        #expect(merged?.position == 250)
        try engine.undo()
        #expect(engine.document == original)
        #expect(!engine.canUndo)
        try engine.redo()
        #expect(engine.document.scenes.first?.guides.first?.position == 250)
    }

    @Test func anotherIndexDoesNotMerge() throws {
        var engine = CommandEngine(document: Self.guided())
        let original = engine.document
        try engine.perform(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: 120), coalesceKey: "k")
        try engine.perform(MoveGuide(sceneID: Fixtures.sceneID, index: 1, position: 60), coalesceKey: "k")
        #expect(engine.undoStack.first?.commands.count == 2)
        let moves = engine.undoStack.first?.commands.compactMap { $0 as? MoveGuide }
        #expect(moves?.map(\.oldPosition) == [100, 50])
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func anotherSceneDoesNotMerge() throws {
        var engine = CommandEngine(document: Self.guided())
        let original = engine.document
        try engine.perform(MoveGuide(sceneID: Fixtures.sceneID, index: 0, position: 120), coalesceKey: "k")
        try engine.perform(MoveGuide(sceneID: "s2", index: 0, position: 9), coalesceKey: "k")
        #expect(engine.undoStack.first?.commands.count == 2)
        let moves = engine.undoStack.first?.commands.compactMap { $0 as? MoveGuide }
        #expect(moves?.map(\.sceneID) == [Fixtures.sceneID, "s2"])
        #expect(moves?.map(\.oldPosition) == [100, 7])
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func mergeDecidesOnParamsOnly() {
        var first = MoveGuide(sceneID: Fixtures.sceneID, index: 2, position: 5)
        let same = first.merge(MoveGuide(sceneID: Fixtures.sceneID, index: 2, position: 8))
        #expect(same)
        #expect(first.position == 8)
        #expect(first.oldPosition == nil)
        let otherIndex = first.merge(MoveGuide(sceneID: Fixtures.sceneID, index: 3, position: 9))
        let otherScene = first.merge(MoveGuide(sceneID: "s2", index: 2, position: 9))
        #expect(!otherIndex)
        #expect(!otherScene)
        #expect(first.position == 8)
    }
}
