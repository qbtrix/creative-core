// InstanceCommandsTests.swift: AddInstance and RemoveInstance on scene and
// symbol layers. Each undo is exact, bad params change nothing, a symbol
// placed inside itself fails perform's validation, and validate rejects a
// non-finite instance transform.
import FlareCore
import Foundation
import Testing

@Suite struct InstanceCommandsTests {
    static let s = Fixtures.sceneID
    static let spark = Instance(symbolID: "spark", transform: Transform(x: 4, y: 2))

    /// `Fixtures.withSymbol()` plus an unused symbol "spark".
    static func document() -> Document {
        var doc = Fixtures.withSymbol()
        doc.symbols.append(Symbol(id: "spark", name: "Spark", durationFrames: 6))
        return doc
    }

    @Test(arguments: [LayerOwner.scene(Fixtures.sceneID), .symbol("sym")])
    func addAndRemoveEachUndoExactly(owner: LayerOwner) throws {
        let layer = owner == .symbol("sym") ? "tail" : "bg"
        let second = Instance(symbolID: "spark", transform: Transform(x: -1, scaleY: 2), firstFrame: 3, loop: .playOnce)
        var engine = CommandEngine(document: Self.document())
        var history = [engine.document]
        try engine.perform(AddInstance(owner: owner, layerID: layer, instance: Self.spark))
        history.append(engine.document)
        try engine.perform(AddInstance(owner: owner, layerID: layer, instance: second))
        history.append(engine.document)
        try engine.perform(RemoveInstance(owner: owner, layerID: layer, index: 0))

        #expect(history[1].layers(of: owner)?.first { $0.id == layer }?.instances == [Self.spark])
        #expect(history[2].layers(of: owner)?.first { $0.id == layer }?.instances == [Self.spark, second])
        #expect(engine.document.layers(of: owner)?.first { $0.id == layer }?.instances == [second])
        let final = engine.document
        while let previous = history.popLast() {
            try engine.undo()
            #expect(engine.document == previous)
        }
        #expect(!engine.canUndo)
        for _ in 0..<3 { try engine.redo() }
        #expect(engine.document == final)
    }

    @Test func symbolInsideItselfIsInvalidAndChangesNothing() {
        var engine = CommandEngine(document: Self.document())
        let error = #expect(throws: CommandError.self) {
            try engine.perform(AddInstance(owner: .symbol("sym"), layerID: "wing", instance: Instance(symbolID: "sym")))
        }
        if case .invalidDocument? = error {} else { Issue.record("not invalidDocument: \(String(describing: error))") }
        #expect(engine.document == Self.document())
        #expect(!engine.canUndo)
    }

    @Test func badParamsThrowBeforeAnyChange() throws {
        var engine = CommandEngine(document: Self.document())
        try engine.perform(AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Self.spark))
        let before = engine.document
        let cases: [(any Command, CommandError)] = [
            (AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Instance(symbolID: "ghost")),
             .symbolNotFound("ghost")),
            (AddInstance(owner: .scene(Self.s), layerID: "ball",
                         instance: Instance(symbolID: "spark", transform: Transform(x: .nan))), .invalidTransform),
            (AddInstance(owner: .scene(Self.s), layerID: "ball",
                         instance: Instance(symbolID: "spark", transform: Transform(rotation: .infinity))),
             .invalidTransform),
            (AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Instance(symbolID: "spark", firstFrame: -1)),
             .invalidFrame(-1)),
            (AddInstance(owner: .symbol("ghost"), layerID: "wing", instance: Self.spark), .symbolNotFound("ghost")),
            (AddInstance(owner: .scene(Self.s), layerID: "nope", instance: Self.spark), .layerNotFound("nope")),
            (RemoveInstance(owner: .scene(Self.s), layerID: "ball", index: 1), .invalidIndex(1)),
            (RemoveInstance(owner: .scene(Self.s), layerID: "ball", index: -1), .invalidIndex(-1)),
            (RemoveInstance(owner: .scene(Self.s), layerID: "nope", index: 0), .layerNotFound("nope")),
            // "bg" has no instances, so even index 0 is out of range.
            (RemoveInstance(owner: .scene(Self.s), layerID: "bg", index: 0), .invalidIndex(0)),
            (SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 0, transform: Transform()),
             .invalidIndex(0)),
            (SetInstancePlayback(owner: .scene(Self.s), layerID: "bg", index: 0, firstFrame: 0, loop: .loop),
             .invalidIndex(0)),
        ]
        for (command, error) in cases {
            #expect(throws: error) { try engine.perform(command) }
            #expect(engine.document == before)
        }

        var locked = engine
        try locked.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isVisible: true, isLocked: true))
        let lockedDoc = locked.document
        for command in [AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Self.spark) as any Command,
                        RemoveInstance(owner: .scene(Self.s), layerID: "ball", index: 0)] {
            #expect(throws: CommandError.layerLocked("ball")) { try locked.perform(command) }
            #expect(locked.document == lockedDoc)
        }
    }

    @Test func addInstanceUndoThrowsRatherThanRemoveAnotherInstance() throws {
        var doc = Self.document()
        var cmd = AddInstance(owner: .scene(Self.s), layerID: "bg", instance: Self.spark)
        try cmd.execute(&doc)
        let error = CommandError.invalidDocument("layer bg: the added instance of spark is no longer last")

        var moved = doc
        moved.scenes[0].layers[0].instances.append(Instance(symbolID: "spark", transform: Transform(x: 9)))
        let movedBefore = moved
        #expect(throws: error) { try cmd.undo(&moved) }
        #expect(moved == movedBefore)

        var emptied = doc
        emptied.scenes[0].layers[0].instances = []
        let emptiedBefore = emptied
        #expect(throws: error) { try cmd.undo(&emptied) }
        #expect(emptied == emptiedBefore)
    }

    @Test func undoBeforeExecuteThrows() {
        var doc = Self.document()
        doc.scenes[0].layers[0].instances = [Self.spark]
        let before = doc
        let commands: [any Command] = [
            AddInstance(owner: .scene(Self.s), layerID: "bg", instance: Self.spark),
            RemoveInstance(owner: .scene(Self.s), layerID: "bg", index: 0),
            SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 0, transform: Transform(x: 3)),
            SetInstancePlayback(owner: .scene(Self.s), layerID: "bg", index: 0, firstFrame: 2, loop: .playOnce),
        ]
        for command in commands {
            #expect(throws: CommandError.notExecuted, "\(type(of: command).id)") { try command.undo(&doc) }
            #expect(doc == before)
        }
    }

    @Test func validateRejectsNonFiniteInstanceTransform() throws {
        var doc = Self.document()
        doc.symbols[0].layers[0].instances = [Instance(symbolID: "spark", transform: Transform(scaleY: .nan))]
        #expect(throws: FormatError.invalid("layer wing: instance transform must be finite")) {
            try FlareFormat.validate(doc)
        }
        doc.symbols[0].layers[0].instances = [Self.spark]
        try FlareFormat.validate(doc)
    }

    /// One sample of each instance command, valid on `CommandRegistryTests.sampleDocument()`.
    static func registrySamples() -> [any Command] {
        [
            AddInstance(owner: .symbol("dot"), layerID: "d", instance: spark),
            RemoveInstance(owner: .scene(s), layerID: "bg", index: 0),
            SetInstanceTransform(owner: .scene(s), layerID: "bg", index: 0, transform: Transform(x: 3, rotation: 45)),
            SetInstancePlayback(owner: .scene(s), layerID: "bg", index: 0, firstFrame: 2, loop: .singleFrame),
        ]
    }

    /// Random instance steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let instance = Instance(symbolID: SymbolCommandsTests.anySymbol(e, &rng),
                                    transform: Transform(x: UndoPropertyTests.anyNumber(in: -50...50, &rng)),
                                    firstFrame: Int.random(in: -1...5, using: &rng))
            try e.perform(AddInstance(owner: owner, layerID: layer, instance: instance))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let count = e.document.layers(of: owner)?.first { $0.id == layer }?.instances.count ?? 0
            try e.perform(RemoveInstance(owner: owner, layerID: layer, index: Int.random(in: -1...count, using: &rng)))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let count = e.document.layers(of: owner)?.first { $0.id == layer }?.instances.count ?? 0
            let transform = Transform(x: UndoPropertyTests.anyNumber(in: -50...50, &rng),
                                      rotation: UndoPropertyTests.anyNumber(in: -90...90, &rng))
            try e.perform(SetInstanceTransform(owner: owner, layerID: layer,
                                               index: Int.random(in: -1...count, using: &rng), transform: transform),
                          coalesceKey: Bool.random(using: &rng) ? "drag" : nil)
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let count = e.document.layers(of: owner)?.first { $0.id == layer }?.instances.count ?? 0
            let loop = [Instance.LoopMode.loop, .playOnce, .singleFrame].randomElement(using: &rng) ?? .loop
            try e.perform(SetInstancePlayback(owner: owner, layerID: layer, index: Int.random(in: -1...count, using: &rng),
                                              firstFrame: Int.random(in: -1...5, using: &rng), loop: loop))
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: UndoPropertyTests.coreSteps + Self.undoSteps,
                                       start: Self.document())
    }
}
