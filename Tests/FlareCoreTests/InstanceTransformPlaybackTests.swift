// InstanceTransformPlaybackTests.swift: SetInstanceTransform and
// SetInstancePlayback on a test-built symbol "spark" placed in a scene layer
// and in a layer of "sym". A drag of one instance is one undo entry, steps on
// another owner or instance never merge, bad params change nothing, and each
// undo is exact.
@testable import FlareCore
import Testing

@Suite struct InstanceTransformPlaybackTests {
    static let s = Fixtures.sceneID
    static let spark = InstanceCommandsTests.spark

    /// "spark" placed twice on scene layer "bg" and once on "sym"'s layer "tail".
    static func document() -> Document {
        var doc = InstanceCommandsTests.document()
        doc.scenes[0].layers[0].instances = [spark, Instance(symbolID: "spark", transform: Transform(x: 1))]
        doc.symbols[0].layers[1].instances = [spark]
        return doc
    }

    @Test(arguments: [(LayerOwner.scene(Fixtures.sceneID), "bg"), (.symbol("sym"), "tail")])
    func dragOfOneInstanceIsOneUndoEntry(owner: LayerOwner, layer: String) throws {
        let start = Self.document()
        var engine = CommandEngine(document: start)
        for i in 1...100 {
            try engine.perform(SetInstanceTransform(owner: owner, layerID: layer, index: 0,
                                                    transform: Transform(x: 0.5 * Double(i), rotation: Double(i))),
                               coalesceKey: "drag")
        }
        let dragged = engine.document
        #expect(dragged.layers(of: owner)?.first { $0.id == layer }?.instances[0].transform
            == Transform(x: 50, rotation: 100))
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == 1)
        try engine.undo()
        #expect(engine.document == start)
        #expect(!engine.canUndo)
        try engine.redo()
        #expect(engine.document == dragged)
    }

    @Test func setsOfOtherOwnersOrInstancesDoNotMerge() throws {
        // One coalesce key across all steps: the entry is shared, but each step
        // on another owner or instance stays its own command.
        let start = Self.document()
        var engine = CommandEngine(document: start)
        let steps: [(LayerOwner, String, Int)] = [(.scene(Self.s), "bg", 0), (.symbol("sym"), "tail", 0),
                                                  (.scene(Self.s), "bg", 1), (.scene(Self.s), "bg", 0)]
        for (step, (owner, layer, index)) in steps.enumerated() {
            try engine.perform(SetInstanceTransform(owner: owner, layerID: layer, index: index,
                                                    transform: Transform(x: Double(10 + step))),
                               coalesceKey: "drag")
        }
        #expect(engine.undoStack.count == 1)
        #expect(engine.undoStack.first?.commands.count == steps.count)
        try engine.undo()
        #expect(engine.document == start)

        var first = SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 0, transform: Transform(x: 1))
        var doc = start
        try first.execute(&doc)
        for (owner, layer, index) in steps.dropFirst().dropLast() {
            var next = SetInstanceTransform(owner: owner, layerID: layer, index: index, transform: Transform(x: 2))
            var d = doc
            try next.execute(&d)
            let merged = first.merge(next)
            #expect(!merged)
        }
        #expect(first.transform == Transform(x: 1))
    }

    @Test func badParamsThrowBeforeAnyChange() throws {
        var engine = CommandEngine(document: Self.document())
        let before = engine.document
        let cases: [(any Command, CommandError)] = [
            (SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 0, transform: Transform(x: .nan)),
             .invalidTransform),
            (SetInstanceTransform(owner: .symbol("sym"), layerID: "tail", index: 0,
                                  transform: Transform(scaleX: .infinity)), .invalidTransform),
            (SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 2, transform: Transform()),
             .invalidIndex(2)),
            (SetInstancePlayback(owner: .scene(Self.s), layerID: "bg", index: 0, firstFrame: -1, loop: .loop),
             .invalidFrame(-1)),
            (SetInstancePlayback(owner: .symbol("sym"), layerID: "tail", index: -1, firstFrame: 0, loop: .loop),
             .invalidIndex(-1)),
        ]
        for (command, error) in cases {
            #expect(throws: error) { try engine.perform(command) }
            #expect(engine.document == before)
        }
        #expect(!engine.canUndo)
    }

    @Test(arguments: [(LayerOwner.scene(Fixtures.sceneID), "bg"), (.symbol("sym"), "tail")])
    func playbackSetsAndUndoesExactly(owner: LayerOwner, layer: String) throws {
        let start = Self.document()
        var engine = CommandEngine(document: start)
        try engine.perform(SetInstancePlayback(owner: owner, layerID: layer, index: 0, firstFrame: 4, loop: .playOnce))
        let instance = engine.document.layers(of: owner)?.first { $0.id == layer }?.instances[0]
        #expect(instance == Instance(symbolID: "spark", transform: Self.spark.transform, firstFrame: 4, loop: .playOnce))
        let set = engine.document
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == set)
    }
}
