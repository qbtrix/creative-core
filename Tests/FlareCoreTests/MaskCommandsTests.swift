// MaskCommandsTests.swift: the mask family's registry ids, registry samples and
// undo steps, and the MM-6 acceptance cases on Fixtures/masks.flare (a shape
// layer with two masks, a layer luma-matted by a hidden one). A new mask
// command adds its id to `expectedIDs`, one sample to `registrySamples()` and
// its random steps to `undoSteps` here; CommandRegistryTests and
// UndoPropertyTests read all three, so neither shared test file changes.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import FlareCore
import Testing

@Suite struct MaskCommandsTests {
    /// Every id in `MaskCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = ["mask.add", "mask.set", "mask.remove", "mask.move", "mask.setMatte"]

    static let o = LayerOwner.scene(Fixtures.sceneID)

    /// A closed square from (a, a) to (b, b).
    static func square(_ a: Double, _ b: Double) -> Path {
        Path(polyline: [Point(x: a, y: a), Point(x: b, y: a), Point(x: b, y: b), Point(x: a, y: b)], closed: true)
    }
    static func mask(_ a: Double, _ mode: MaskMode = .add, feather: Double = 0) -> LayerMask {
        LayerMask(path: square(a, 100 - a), mode: mode, feather: feather)
    }

    /// Gives the sample document's "ball" layer two masks, so the set, remove and move samples have masks to edit.
    static func addSampleMasks(_ doc: inout Document) {
        doc.scenes[0].layers[1].masks = [mask(10), mask(30, .subtract)]
    }

    /// One sample of every mask command, each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] {
        [AddLayerMask(owner: o, layerID: "ball", mask: mask(20, .intersect), index: 1),
         SetLayerMask(owner: o, layerID: "ball", index: 0, mask: mask(5, feather: 4)),
         RemoveLayerMask(owner: o, layerID: "ball", index: 1),
         MoveLayerMask(owner: o, layerID: "ball", from: 0, to: 1),
         SetTrackMatte(owner: o, layerID: "ball", matte: TrackMatte(sourceLayerID: "bg", kind: .luma))]
    }

    /// A mask index of `layer` in `owner`, sometimes one past the end or negative.
    static func anyIndex(_ e: CommandEngine, _ owner: LayerOwner, _ layer: String, _ rng: inout SplitMix64) -> Int {
        let count = e.document.layers(of: owner)?.first { $0.id == layer }?.masks.count ?? 0
        return Int.random(in: -1...count, using: &rng)
    }

    /// A mask with a random inset, mode and feather, the feather sometimes negative or not finite.
    static func anyMask(_ rng: inout SplitMix64) -> LayerMask {
        LayerMask(path: square(Double.random(in: 0...40, using: &rng), 90),
                  mode: [MaskMode.add, .subtract, .intersect, .difference].randomElement(using: &rng) ?? .add,
                  feather: UndoPropertyTests.anyNumber(in: -1...10, &rng),
                  opacity: Double.random(in: 0...1.2, using: &rng), inverted: Bool.random(using: &rng))
    }

    /// Random mask steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let index: Int? = Bool.random(using: &rng) ? nil : anyIndex(e, owner, layer, &rng) + 1
            try e.perform(AddLayerMask(owner: owner, layerID: layer, mask: anyMask(&rng), index: index))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let key: String? = Bool.random(using: &rng) ? "mask-drag" : nil
            try e.perform(SetLayerMask(owner: owner, layerID: layer, index: anyIndex(e, owner, layer, &rng), mask: anyMask(&rng)),
                          coalesceKey: key)
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            try e.perform(RemoveLayerMask(owner: owner, layerID: layer, index: anyIndex(e, owner, layer, &rng)))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let from = anyIndex(e, owner, layer, &rng), to = anyIndex(e, owner, layer, &rng)
            try e.perform(MoveLayerMask(owner: owner, layerID: layer, from: from, to: to))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let source = (e.document.layers(of: owner)?.map(\.id) ?? []) + ["missing"]
            let matte = Bool.random(using: &rng) ? nil
                : (source.randomElement(using: &rng)).map { TrackMatte(sourceLayerID: $0, kind: .lumaInverted) }
            try e.perform(SetTrackMatte(owner: owner, layerID: layer, matte: matte))
        },
    ]

    @Test(arguments: 0..<50 as Range<UInt64>)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps)
    }

    @Test func familyListsExactlyItsIDs() {
        #expect(MaskCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs)
    }

    // MARK: - MM-6 acceptance on the masks fixture

    static let m = LayerOwner.scene("masks")

    static func fixture() throws -> Document {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/masks.flare")
        return try FlareFormat.decode(Data(contentsOf: url))
    }

    static func layer(_ doc: Document, _ id: String) -> Layer? { doc.layers(of: m)?.first { $0.id == id } }

    /// Performs `command` on the fixture, then checks undo restores it and redo gives the same result again; returns that result.
    static func roundTrip(_ command: some Command) throws -> Document {
        let start = try fixture()
        var engine = CommandEngine(document: start)
        try engine.perform(command)
        let after = engine.document
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == after)
        return after
    }

    /// Checks `command` is refused through the engine and from `execute`, both leaving `start` unchanged.
    static func expectRefused(_ command: any Command, on start: Document) {
        var engine = CommandEngine(document: start)
        #expect(throws: (any Error).self) { try engine.perform(command) }
        #expect(engine.document == start && !engine.canUndo)
        var direct = command, doc = start
        #expect(throws: (any Error).self) { try direct.execute(&doc) }
        #expect(doc == start)
    }

    @Test func fixtureValidatesAndLoads() throws {
        let doc = try Self.fixture()
        try FlareFormat.validate(doc)
        #expect(Self.layer(doc, "card")?.masks.map(\.mode) == [.add, .subtract])
        #expect(Self.layer(doc, "card")?.masks.last?.feather == 8 && Self.layer(doc, "card")?.masks.last?.opacity == 0.75)
        #expect(Self.layer(doc, "photo")?.matte == TrackMatte(sourceLayerID: "lumen", kind: .luma))
        #expect(Self.layer(doc, "lumen")?.isVisible == false)
        #expect(try FlareFormat.decode(FlareFormat.encode(doc)) == doc)
    }

    @Test func addSetRemoveUndoExactly() throws {
        let extra = Self.mask(40, .difference, feather: 2)
        #expect(Self.layer(try Self.roundTrip(AddLayerMask(owner: Self.m, layerID: "card", mask: extra, index: 1)), "card")?
            .masks.map(\.mode) == [.add, .difference, .subtract])
        #expect(Self.layer(try Self.roundTrip(AddLayerMask(owner: Self.m, layerID: "photo", mask: extra)), "photo")?.masks == [extra])
        #expect(Self.layer(try Self.roundTrip(SetLayerMask(owner: Self.m, layerID: "card", index: 1, mask: extra)), "card")?
            .masks.last == extra)
        #expect(Self.layer(try Self.roundTrip(RemoveLayerMask(owner: Self.m, layerID: "card", index: 0)), "card")?
            .masks.map(\.mode) == [.subtract])
        let cleared = try Self.roundTrip(SetTrackMatte(owner: Self.m, layerID: "photo", matte: nil))
        #expect(Self.layer(cleared, "photo")?.matte == nil)
        let alpha = TrackMatte(sourceLayerID: "photo", kind: .alphaInverted)
        #expect(Self.layer(try Self.roundTrip(SetTrackMatte(owner: Self.m, layerID: "card", matte: alpha)), "card")?.matte == alpha)
    }

    /// Moving the first of three masks to the end and undoing gives back the same order, not a neighbour swap.
    @Test func moveUndoesExactly() throws {
        var start = try Self.fixture()
        try start.withLayer(Self.m, layer: "card") { $0.masks.append(Self.mask(45, .intersect)) }
        var engine = CommandEngine(document: start)
        try engine.perform(MoveLayerMask(owner: Self.m, layerID: "card", from: 0, to: 2))
        #expect(Self.layer(engine.document, "card")?.masks.map(\.mode) == [.subtract, .intersect, .add])
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(Self.layer(engine.document, "card")?.masks.map(\.mode) == [.subtract, .intersect, .add])
    }

    /// A drag of one mask coalesces into one step that undoes to before the drag; a step on another mask under the same key does not merge.
    @Test func mergeOnlySameMask() throws {
        let start = try Self.fixture()
        var engine = CommandEngine(document: start)
        for inset in [12.0, 14, 16] {
            try engine.perform(SetLayerMask(owner: Self.m, layerID: "card", index: 0, mask: Self.mask(inset)), coalesceKey: "drag")
        }
        #expect(engine.undoStack.count == 1 && engine.undoStack.last?.commands.count == 1)
        try engine.perform(SetLayerMask(owner: Self.m, layerID: "card", index: 1, mask: Self.mask(30)), coalesceKey: "drag")
        #expect(engine.undoStack.last?.commands.count == 2)
        #expect(Self.layer(engine.document, "card")?.masks == [Self.mask(16), Self.mask(30)])
        try engine.undo()
        #expect(engine.document == start)
    }

    /// A matte whose source reaches the layer through two mattes is refused, as are one-deep and self mattes.
    @Test func refusesCycleTwoDeep() throws {
        var engine = CommandEngine(document: try Self.fixture())
        try engine.perform(SetTrackMatte(owner: Self.m, layerID: "lumen", matte: TrackMatte(sourceLayerID: "card")))
        // photo -> lumen -> card: card matted by photo would close a cycle of three.
        Self.expectRefused(SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "photo")),
                           on: engine.document)
        var direct = SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "photo"))
        var doc = engine.document
        #expect(throws: CommandError.self) { try direct.execute(&doc) }
        let start = try Self.fixture()
        Self.expectRefused(SetTrackMatte(owner: Self.m, layerID: "lumen", matte: TrackMatte(sourceLayerID: "photo")), on: start)
        Self.expectRefused(SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "card")), on: start)
    }

    /// A source in another owner's list or nowhere is refused.
    @Test func refusesSourceElsewhere() throws {
        var start = try Self.fixture()
        start.symbols = [Symbol(id: "pins", name: "Pins", layers: [Layer(id: "pin", name: "Pin")])]
        for source in ["pin", "missing"] {
            Self.expectRefused(SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: source)), on: start)
        }
        Self.expectRefused(SetTrackMatte(owner: .symbol("pins"), layerID: "pin", matte: TrackMatte(sourceLayerID: "card")), on: start)
    }

    @Test func refusesLockedLayer() throws {
        var start = try Self.fixture()
        try start.withLayer(Self.m, layer: "card") { $0.isLocked = true }
        let commands: [any Command] = [
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20)),
            SetLayerMask(owner: Self.m, layerID: "card", index: 0, mask: Self.mask(20)),
            RemoveLayerMask(owner: Self.m, layerID: "card", index: 0),
            MoveLayerMask(owner: Self.m, layerID: "card", from: 0, to: 1),
            SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "lumen")),
        ]
        for command in commands { Self.expectRefused(command, on: start) }
    }

    @Test func refusesBadIndex() throws {
        let start = try Self.fixture()
        let commands: [any Command] = [
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20), index: 3),
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20), index: -1),
            SetLayerMask(owner: Self.m, layerID: "card", index: 2, mask: Self.mask(20)),
            RemoveLayerMask(owner: Self.m, layerID: "card", index: -1),
            RemoveLayerMask(owner: Self.m, layerID: "photo", index: 0),
            MoveLayerMask(owner: Self.m, layerID: "card", from: 0, to: 2),
            MoveLayerMask(owner: Self.m, layerID: "card", from: -1, to: 0),
        ]
        for command in commands { Self.expectRefused(command, on: start) }
    }
}
