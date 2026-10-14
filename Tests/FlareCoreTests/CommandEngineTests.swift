// CommandEngineTests.swift: perform/undo/redo, named actions, grouping,
// atomicity on failure, and Codable params.
@testable import FlareCore
import Foundation
import Testing

@Suite struct CommandEngineTests {
    let s = Fixtures.sceneID

    @Test func performUndoRedo() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "Planet"))
        #expect(engine.document.scenes[0].layers[1].name == "Planet")
        try engine.undo()
        #expect(engine.document == original)
        try engine.redo()
        #expect(engine.document.scenes[0].layers[1].name == "Planet")
    }

    @Test func namedActions() throws {
        var engine = CommandEngine(document: Fixtures.document())
        #expect(engine.undoActionName == nil)
        try engine.perform(MoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", from: 24, to: 30))
        #expect(engine.undoActionName == "Undo Move Keyframe")
        try engine.undo()
        #expect(engine.redoActionName == "Redo Move Keyframe")
    }

    @Test func groupIsOneUndoStep() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        try engine.group("Nudge") { e in
            try e.perform(MoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", from: 24, to: 25))
            try e.perform(SetKeyframe(owner: .scene(s), layerID: "ball", property: "y", keyframe: Keyframe(frame: 3, value: 9)))
            try e.group("Inner") { inner in
                try inner.perform(RenameLayer(owner: .scene(s), layerID: "bg", name: "Sky"))
            }
        }
        #expect(engine.undoActionName == "Undo Nudge")
        try engine.undo()
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func failedGroupRollsBack() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        #expect(throws: CommandError.layerNotFound("nope")) {
            try engine.group("Broken") { e in
                try e.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "X"))
                try e.perform(RenameLayer(owner: .scene(s), layerID: "nope", name: "Y"))
            }
        }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func failedCommandChangesNothing() throws {
        var engine = CommandEngine(document: Fixtures.document())
        let original = engine.document
        #expect(throws: CommandError.frameOccupied(property: "x", frame: 0)) {
            try engine.perform(MoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", from: 24, to: 0))
        }
        #expect(throws: CommandError.duplicateID("bg")) {
            try engine.perform(AddLayer(owner: .scene(s), layer: Layer(id: "bg", name: "dup")))
        }
        #expect(throws: CommandError.invalidFrame(-1)) {
            try engine.perform(SetKeyframe(owner: .scene(s), layerID: "ball", property: "x", keyframe: Keyframe(frame: -1, value: 0)))
        }
        #expect(throws: CommandError.sceneNotFound("zz")) {
            try engine.perform(RemoveLayer(owner: .scene("zz"), layerID: "bg"))
        }
        #expect(engine.document == original)
        #expect(!engine.canUndo)
    }

    @Test func emptyStacksThrow() {
        var engine = CommandEngine(document: Document())
        #expect(throws: CommandError.nothingToUndo) { try engine.undo() }
        #expect(throws: CommandError.nothingToRedo) { try engine.redo() }
    }

    @Test func undoInsideGroupThrows() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(RenameLayer(owner: .scene(s), layerID: "bg", name: "A"))
        #expect(throws: CommandError.groupInProgress) {
            try engine.group("G") { e in try e.undo() }
        }
    }

    @Test func newCommandClearsRedo() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(RenameLayer(owner: .scene(s), layerID: "bg", name: "A"))
        try engine.undo()
        #expect(engine.canRedo)
        try engine.perform(RenameLayer(owner: .scene(s), layerID: "bg", name: "B"))
        #expect(!engine.canRedo)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Fixtures.document()
        #expect(throws: CommandError.notExecuted) { try RemoveLayer(owner: .scene(s), layerID: "bg").undo(&doc) }
        #expect(throws: CommandError.notExecuted) {
            try SetKeyframe(owner: .scene(s), layerID: "ball", property: "x", keyframe: Keyframe(frame: 0, value: 1)).undo(&doc)
        }
        #expect(doc == Fixtures.document())
    }

    @Test func commandParamsAreCodable() throws {
        let cmd = MoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", from: 24, to: 30)
        let data = try JSONEncoder().encode(cmd)
        var back = try JSONDecoder().decode(MoveKeyframe.self, from: data)
        #expect(MoveKeyframe.id == "keyframe.move")
        var doc = Fixtures.document()
        try back.execute(&doc)
        #expect(doc.scenes[0].layers[1].tracks["x"]?.last?.frame == 30)
        // A journal entry written before execute (no undo state) decodes too.
        let fresh = try JSONDecoder().decode(
            SetKeyframe.self,
            from: Data(#"{"sceneID":"s1","layerID":"ball","property":"x","keyframe":{"frame":1,"value":2,"easing":{"linear":{}}}}"#.utf8))
        #expect(fresh.keyframe.frame == 1)
    }

    @Test func performRejectsCommandsThatBreakTheFormat() throws {
        var doc = Fixtures.document()
        doc.stateMachines = [StateMachine(id: "m", name: "M",
            states: [MachineState(id: "a", name: "A", sceneID: s, startFrame: 0, endFrame: 40)],
            initialState: "a")]
        var e = CommandEngine(document: doc)
        let before = e.document

        #expect(throws: CommandError.self) { try e.perform(SetSceneTiming(sceneID: s, fps: 24, durationFrames: 10)) }
        #expect(throws: CommandError.self) { try e.perform(RemoveScene(sceneID: s)) }
        #expect(throws: CommandError.self) {
            try e.perform(SetKeyframe(owner: .scene(s), layerID: "ball", property: "x", keyframe: Keyframe(frame: 5, value: .nan)))
        }
        #expect(throws: CommandError.self) {
            try e.perform(AddLayer(owner: .scene(s), layer: Layer(id: "bad", name: "b", tracks: ["x": []])))
        }
        let nanShape = Shape(points: [Point(x: .nan, y: 0), Point(x: 1, y: 1)])
        #expect(throws: CommandError.self) { try e.perform(AddShape(owner: .scene(s), layerID: "ball", shape: nanShape)) }
        let curve = Shape(points: [], path: Path(elements: [.move(to: Point(x: 0, y: 0)),
                                                             .line(to: Point(x: 0, y: -.infinity))]))
        #expect(throws: CommandError.self) { try e.perform(AddShape(owner: .scene(s), layerID: "ball", shape: curve)) }
        #expect(throws: CommandError.self) {
            try e.perform(TranslateShape(owner: .scene(s), layerID: "ball", index: 0, dx: .infinity, dy: 0))
        }
        // Every rejected command left the document untouched and saveable.
        #expect(e.document == before)
        #expect(!e.canUndo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func invalidStepInGroupRollsBackTheGroup() throws {
        var e = CommandEngine(document: Fixtures.document())
        let before = e.document
        #expect(throws: CommandError.self) {
            try e.group("Mixed") { g in
                try g.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "Planet"))
                try g.perform(AddLayer(owner: .scene(s), layer: Layer(id: "bad", name: "b", tracks: ["x": []])))
            }
        }
        #expect(e.document == before)
        #expect(!e.canUndo)
        // A valid command still commits after the rejections.
        try e.perform(RenameLayer(owner: .scene(s), layerID: "ball", name: "Planet"))
        #expect(e.document.scenes[0].layers[1].name == "Planet")
    }

    @Test func layerScopedValidateCatchesTheTouchedLayer() {
        let before = Fixtures.document()
        var dup = before
        dup.scenes[0].layers.insert(Layer(id: "ball", name: "Copy"), at: 0)
        #expect(throws: FormatError.invalid("scene s1: duplicate layer id ball")) {
            try FlareFormat.validate(dup, layer: "ball", owner: .scene("s1"), since: before)
        }
        var emptyTrack = before
        emptyTrack.scenes[0].layers[1].tracks["y"] = []
        #expect(throws: FormatError.invalid("layer ball: empty track y")) {
            try FlareFormat.validate(emptyTrack, layer: "ball", owner: .scene("s1"), since: before)
        }
        var renamed = before
        renamed.scenes[0].layers[1].name = "Planet"
        #expect(throws: Never.self) { try FlareFormat.validate(renamed, layer: "ball", owner: .scene("s1"), since: before) }
    }

    @Test func layerScopedValidateCatchesALayerThatGrowsPastThePointLimit() {
        let before = FormatLimitsTests.document(points: FlareFormat.maxTotalPoints)
        var grown = before
        grown.scenes[0].layers[0].shapes[0].points.append(Point(x: 0, y: 0))
        #expect(throws: FormatError.tooLarge("more than \(FlareFormat.maxTotalPoints) points")) {
            try FlareFormat.validate(grown, layer: "l", owner: .scene("s"), since: before)
        }
    }

    @Test func layerScopedValidateCatchesTheTouchedSymbolLayer() {
        let before = Fixtures.withSymbol()
        let sym = LayerOwner.symbol("sym")
        var dup = before
        dup.symbols[0].layers.insert(Layer(id: "wing", name: "Copy"), at: 0)
        #expect(throws: FormatError.invalid("symbol sym: duplicate layer id wing")) {
            try FlareFormat.validate(dup, layer: "wing", owner: sym, since: before)
        }
        var emptyTrack = before
        emptyTrack.symbols[0].layers[0].tracks["y"] = []
        #expect(throws: FormatError.invalid("layer wing: empty track y")) {
            try FlareFormat.validate(emptyTrack, layer: "wing", owner: sym, since: before)
        }
        var cycle = before
        cycle.symbols[0].layers[0].instances = [Instance(symbolID: "sym")]
        #expect(throws: FormatError.invalid("symbol cycle sym -> sym")) {
            try FlareFormat.validate(cycle, layer: "wing", owner: sym, since: before)
        }
        var renamed = before
        renamed.symbols[0].layers[0].name = "Left Wing"
        #expect(throws: Never.self) { try FlareFormat.validate(renamed, layer: "wing", owner: sym, since: before) }
    }
}
