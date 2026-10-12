// UndoDepthTests.swift: the undo stack keeps at most maxUndoDepth entries.
@testable import FlareCore
import Foundation
import Testing

@Suite struct UndoDepthTests {
    let s = Fixtures.sceneID

    @Test func defaultDepthIs500() {
        #expect(CommandEngine(document: Fixtures.document()).maxUndoDepth == 500)
    }

    @Test func oldestEntryIsDropped() throws {
        var engine = CommandEngine(document: Fixtures.document(), maxUndoDepth: 3)
        var afterTwo: Document?
        for i in 1...5 {
            try engine.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "Name \(i)"))
            if i == 2 { afterTwo = engine.document }
        }
        for _ in 0..<3 { try engine.undo() }
        #expect(engine.document == afterTwo)
        #expect(!engine.canUndo)
        #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
        // Redo still replays all three kept steps.
        for _ in 0..<3 { try engine.redo() }
        #expect(engine.document.scenes[0].layers[1].name == "Name 5")
    }

    @Test func groupCountsAsOneEntry() throws {
        var engine = CommandEngine(document: Fixtures.document(), maxUndoDepth: 1)
        let original = engine.document
        try engine.group("Two Renames") { e in
            try e.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "A"))
            try e.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "B"))
        }
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func zeroOrNegativeDepthKeepsNoHistory() throws {
        for depth in [0, -5] {
            var engine = CommandEngine(document: Fixtures.document(), maxUndoDepth: depth)
            #expect(engine.maxUndoDepth == 0)
            try engine.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "X"))
            #expect(engine.document.scenes[0].layers[1].name == "X")
            #expect(!engine.canUndo)
            #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
        }
    }
}
