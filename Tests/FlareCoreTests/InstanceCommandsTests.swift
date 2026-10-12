// InstanceCommandsTests.swift: AddInstance, RemoveInstance and
// SetInstanceTransform on scene and symbol layers. Each undo is exact, a drag
// of one instance is one undo entry, bad params change nothing, and a symbol
// placed inside itself fails perform's validation.
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
    func addMoveRemoveEachUndoExactly(owner: LayerOwner) throws {
        let layer = owner == .symbol("sym") ? "tail" : "bg"
        var engine = CommandEngine(document: Self.document())
        var history = [engine.document]
        try engine.perform(AddInstance(owner: owner, layerID: layer, instance: Self.spark))
        history.append(engine.document)
        try engine.perform(SetInstanceTransform(owner: owner, layerID: layer, index: 0,
                                                transform: Transform(x: 9, y: -1, scaleX: 2, rotation: 30)))
        history.append(engine.document)
        try engine.perform(RemoveInstance(owner: owner, layerID: layer, index: 0))
        history.append(engine.document)

        #expect(history[1].layers(of: owner)?.first { $0.id == layer }?.instances == [Self.spark])
        #expect(history[2].layers(of: owner)?.first { $0.id == layer }?.instances.first?.transform
            == Transform(x: 9, y: -1, scaleX: 2, rotation: 30))
        #expect(history[3] == history[0])
        for expected in history.dropLast().reversed() {
            try engine.undo()
            #expect(engine.document == expected)
        }
        try engine.redo()
        #expect(engine.document == history[1])
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
            (AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Instance(symbolID: "spark", transform: Transform(x: .nan))),
             .invalidTransform),
            (AddInstance(owner: .scene(Self.s), layerID: "ball", instance: Instance(symbolID: "spark", firstFrame: -1)),
             .invalidFrame(-1)),
            (AddInstance(owner: .symbol("ghost"), layerID: "wing", instance: Self.spark), .symbolNotFound("ghost")),
            (SetInstanceTransform(owner: .scene(Self.s), layerID: "ball", index: 0,
                                  transform: Transform(rotation: .infinity)), .invalidTransform),
            (SetInstanceTransform(owner: .scene(Self.s), layerID: "ball", index: 1, transform: .identity),
             .invalidIndex(1)),
            (RemoveInstance(owner: .scene(Self.s), layerID: "ball", index: -1), .invalidIndex(-1)),
            (RemoveInstance(owner: .scene(Self.s), layerID: "nope", index: 0), .layerNotFound("nope")),
        ]
        for (command, error) in cases {
            #expect(throws: error) { try engine.perform(command) }
            #expect(engine.document == before)
        }

        var locked = engine
        try locked.perform(SetLayerFlags(owner: .scene(Self.s), layerID: "ball", isVisible: true, isLocked: true))
        #expect(throws: CommandError.layerLocked("ball")) {
            try locked.perform(RemoveInstance(owner: .scene(Self.s), layerID: "ball", index: 0))
        }
    }

    @Test func validateRejectsNonFiniteInstanceTransform() {
        var doc = Self.document()
        doc.symbols[0].layers[0].instances = [Instance(symbolID: "spark", transform: Transform(scaleY: .nan))]
        #expect(throws: FormatError.invalid("layer wing: instance transform must be finite")) {
            try FlareFormat.validate(doc)
        }
    }

    @Test func dragOfOneInstanceIsOneUndoEntry() throws {
        var start = Self.document()
        start.symbols[0].layers[1].instances = [Self.spark]
        var engine = CommandEngine(document: start)
        for i in 1...10 {
            try engine.perform(SetInstanceTransform(owner: .symbol("sym"), layerID: "tail", index: 0,
                                                    transform: Transform(x: 0.1 * Double(i))),
                               coalesceKey: "drag")
        }
        let dragged = engine.document
        #expect(dragged.symbols[0].layers[1].instances[0].transform == Transform(x: 0.1 * 10))
        try engine.undo()
        #expect(engine.document == start)
        #expect(!engine.canUndo)
        try engine.redo()
        #expect(engine.document == dragged)
    }

    @Test func setsOfOtherOwnersOrInstancesDoNotMerge() throws {
        // Every other instance starts where `first` ends, so only the address differs.
        let moved = Instance(symbolID: "spark", transform: Transform(x: 1))
        var doc = Self.document()
        doc.scenes[0].layers[0].instances = [Self.spark, moved]
        doc.symbols[0].layers.append(Layer(id: "bg", name: "Bg", instances: [moved]))
        var first = SetInstanceTransform(owner: .scene(Self.s), layerID: "bg", index: 0, transform: Transform(x: 1))
        try first.execute(&doc)
        for (owner, index) in [(LayerOwner.symbol("sym"), 0), (.scene(Self.s), 1)] {
            var next = SetInstanceTransform(owner: owner, layerID: "bg", index: index, transform: Transform(x: 2))
            var d = doc
            try next.execute(&d)
            var last = first
            let merged = last.merge(next)
            #expect(!merged)
        }
    }

    /// One sample of each instance command, valid on `CommandRegistryTests.sampleDocument()`.
    static func registrySamples() -> [any Command] {
        [
            AddInstance(owner: .symbol("dot"), layerID: "d", instance: spark),
            RemoveInstance(owner: .scene(s), layerID: "bg", index: 0),
            SetInstanceTransform(owner: .scene(s), layerID: "bg", index: 0, transform: Transform(x: 3, rotation: 45)),
        ]
    }

    /// A scene, symbol or missing owner, one of its layers or "missing", and an
    /// instance index in or just outside that layer's range.
    static func anyTarget(_ e: CommandEngine, _ rng: inout SplitMix64) -> (LayerOwner, String, Int) {
        let owners = [LayerOwner.scene(s), .symbol("missing")] + e.document.symbols.map { .symbol($0.id) }
        let owner = owners.randomElement(using: &rng) ?? .scene(s), layers = e.document.layers(of: owner) ?? []
        let i = Int.random(in: 0...layers.count, using: &rng)
        guard layers.indices.contains(i) else { return (owner, "missing", 0) }
        return (owner, layers[i].id, Int.random(in: -1...layers[i].instances.count, using: &rng))
    }

    /// Random instance steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer, _) = anyTarget(e, &rng)
            let instance = Instance(symbolID: SymbolCommandsTests.anySymbol(e, &rng),
                                    transform: Transform(x: UndoPropertyTests.anyNumber(in: -50...50, &rng)),
                                    firstFrame: Int.random(in: -1...5, using: &rng))
            try e.perform(AddInstance(owner: owner, layerID: layer, instance: instance))
        },
        { e, rng, _ in
            let (owner, layer, index) = anyTarget(e, &rng)
            try e.perform(RemoveInstance(owner: owner, layerID: layer, index: index))
        },
        { e, rng, _ in
            let (owner, layer, index) = anyTarget(e, &rng)
            let t = Transform(x: UndoPropertyTests.anyNumber(in: -50...50, &rng), y: 1,
                              rotation: UndoPropertyTests.anyNumber(in: -180...180, &rng))
            try e.perform(SetInstanceTransform(owner: owner, layerID: layer, index: index, transform: t),
                          coalesceKey: Bool.random(using: &rng) ? "drag" : nil)
        },
    ]

    @Test(arguments: 0..<200)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: Self.document())
    }
}
