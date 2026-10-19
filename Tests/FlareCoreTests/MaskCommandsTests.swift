// MaskCommandsTests.swift: the mask family's ids, registry samples and undo steps
// (CommandRegistryTests and UndoPropertyTests read all three), then the MM-6 cases on Fixtures/masks.flare.
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
    static let o = LayerOwner.scene(Fixtures.sceneID), m = LayerOwner.scene("masks")

    static func mask(_ a: Double, _ mode: MaskMode = .add, feather: Double = 0) -> LayerMask {
        let b = 100 - a
        let points = [Point(x: a, y: a), Point(x: b, y: a), Point(x: b, y: b), Point(x: a, y: b)]
        return LayerMask(path: Path(polyline: points, closed: true), mode: mode, feather: feather)
    }

    /// Gives the sample document's "ball" layer two masks, so the set, remove and move samples have masks to edit.
    static func addSampleMasks(_ doc: inout Document) { doc.scenes[0].layers[1].masks = [mask(10), mask(30, .subtract)] }

    /// One sample of every mask command, each valid on
    /// `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    static func registrySamples() -> [any Command] {
        [AddLayerMask(owner: o, layerID: "ball", mask: mask(20, .intersect), index: 1),
         SetLayerMask(owner: o, layerID: "ball", index: 0, mask: mask(5, feather: 4)),
         RemoveLayerMask(owner: o, layerID: "ball", index: 1),
         MoveLayerMask(owner: o, layerID: "ball", from: 0, to: 1),
         SetTrackMatte(owner: o, layerID: "ball", matte: TrackMatte(sourceLayerID: "bg", kind: .luma))]
    }

    /// A random target and one of its mask indices, about one time in eight one past the end or negative.
    static func anyIndex(_ e: CommandEngine, _ rng: inout SplitMix64) -> (LayerOwner, String, Int) {
        let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
        let count = e.document.layers(of: owner)?.first { $0.id == layer }?.masks.count ?? 0
        guard count > 0, Int.random(in: 0..<8, using: &rng) > 0 else { return (owner, layer, [-1, count].randomElement(using: &rng) ?? -1) }
        return (owner, layer, Int.random(in: 0..<count, using: &rng))
    }

    /// A mask with a random inset, mode and feather, the feather sometimes negative or not finite.
    static func anyMask(_ rng: inout SplitMix64) -> LayerMask {
        var mask = mask(Double.random(in: 0...40, using: &rng), [.add, .subtract, .intersect, .difference].randomElement(using: &rng) ?? .add,
                        feather: UndoPropertyTests.anyNumber(in: -1...10, &rng))
        (mask.opacity, mask.inverted) = (Double.random(in: 0...1.2, using: &rng), Bool.random(using: &rng))
        return mask
    }

    /// Random mask steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in
            let (owner, layer, i) = anyIndex(e, &rng)
            try e.perform(AddLayerMask(owner: owner, layerID: layer, mask: anyMask(&rng), index: Bool.random(using: &rng) ? nil : i + 1))
        },
        { e, rng, _ in
            let (owner, layer, i) = anyIndex(e, &rng), key: String? = Bool.random(using: &rng) ? "mask-drag" : nil
            try e.perform(SetLayerMask(owner: owner, layerID: layer, index: i, mask: anyMask(&rng)), coalesceKey: key)
        },
        { e, rng, _ in
            let (owner, layer, i) = anyIndex(e, &rng)
            try e.perform(RemoveLayerMask(owner: owner, layerID: layer, index: i))
        },
        { e, rng, _ in
            let (owner, layer, from) = anyIndex(e, &rng), to = anyIndex(e, &rng).2
            try e.perform(MoveLayerMask(owner: owner, layerID: layer, from: from, to: to))
        },
        { e, rng, _ in
            let (owner, layer) = UndoPropertyTests.anyTarget(e, &rng)
            let source = Bool.random(using: &rng) ? nil : ((e.document.layers(of: owner)?.map(\.id) ?? []) + ["missing"]).randomElement(using: &rng)
            try e.perform(SetTrackMatte(owner: owner, layerID: layer, matte: source.map { TrackMatte(sourceLayerID: $0, kind: .lumaInverted) }))
        },
    ]

    @Test(arguments: 0..<50 as Range<UInt64>)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps)
    }

    @Test func familyAndSamplesListExactlyItsIDs() {
        #expect(MaskCommands.all.map { $0.id } == Self.expectedIDs)
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs)
    }

    // MARK: - MM-6 acceptance on the masks fixture

    static func fixture() throws -> Document {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/masks.flare")
        return try FlareFormat.decode(Data(contentsOf: url))
    }

    static func layer(_ doc: Document, _ id: String) -> Layer? { doc.layers(of: m)?.first { $0.id == id } }

    /// Performs `command` on the fixture, checks undo restores it and redo repeats it, and returns the card or `id` layer after.
    static func roundTrip(_ command: some Command, _ id: String = "card") throws -> Layer? {
        let start = try fixture()
        var engine = CommandEngine(document: start)
        try engine.perform(command)
        let after = engine.document
        try engine.undo()
        #expect(engine.document == start)
        try engine.redo()
        #expect(engine.document == after)
        return layer(after, id)
    }

    /// Checks `command` is refused through the engine and from `execute`, both leaving `start` unchanged.
    static func expectRefused(_ command: any Command, on start: Document) {
        var engine = CommandEngine(document: start), direct = command, doc = start
        #expect(throws: (any Error).self) { try engine.perform(command) }
        #expect(engine.document == start && !engine.canUndo)
        #expect(throws: (any Error).self) { try direct.execute(&doc) }
        #expect(doc == start)
    }

    @Test func fixtureValidatesAndLoads() throws {
        let doc = try Self.fixture()
        try FlareFormat.validate(doc)
        let card = Self.layer(doc, "card")
        #expect(card?.masks.map(\.mode) == [.add, .subtract] && card?.masks.last?.feather == 8 && card?.masks.last?.opacity == 0.75)
        #expect(Self.layer(doc, "photo")?.matte == TrackMatte(sourceLayerID: "lumen", kind: .luma))
        #expect(Self.layer(doc, "lumen")?.isVisible == false)
        #expect(try FlareFormat.decode(FlareFormat.encode(doc)) == doc)
    }

    @Test func addSetRemoveUndoExactly() throws {
        let extra = Self.mask(40, .difference, feather: 2), alpha = TrackMatte(sourceLayerID: "photo", kind: .alphaInverted)
        #expect(try Self.roundTrip(AddLayerMask(owner: Self.m, layerID: "card", mask: extra, index: 1))?.masks.map(\.mode)
            == [.add, .difference, .subtract])
        #expect(try Self.roundTrip(AddLayerMask(owner: Self.m, layerID: "photo", mask: extra), "photo")?.masks == [extra])
        #expect(try Self.roundTrip(SetLayerMask(owner: Self.m, layerID: "card", index: 1, mask: extra))?.masks.last == extra)
        #expect(try Self.roundTrip(RemoveLayerMask(owner: Self.m, layerID: "card", index: 0))?.masks.map(\.mode) == [.subtract])
        #expect(try Self.roundTrip(SetTrackMatte(owner: Self.m, layerID: "photo", matte: nil), "photo")?.matte == nil)
        #expect(try Self.roundTrip(SetTrackMatte(owner: Self.m, layerID: "card", matte: alpha))?.matte == alpha)
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
        Self.expectRefused(SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "photo")), on: engine.document)
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

    /// Every command refuses a locked layer, and the index commands an index outside the list.
    @Test func refusesLockedLayerAndBadIndex() throws {
        let start = try Self.fixture()
        var locked = start
        try locked.withLayer(Self.m, layer: "card") { $0.isLocked = true }
        for command in [
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20)),
            SetLayerMask(owner: Self.m, layerID: "card", index: 0, mask: Self.mask(20)),
            RemoveLayerMask(owner: Self.m, layerID: "card", index: 0),
            MoveLayerMask(owner: Self.m, layerID: "card", from: 0, to: 1),
            SetTrackMatte(owner: Self.m, layerID: "card", matte: TrackMatte(sourceLayerID: "lumen")),
        ] as [any Command] { Self.expectRefused(command, on: locked) }
        for command in [
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20), index: 3),
            AddLayerMask(owner: Self.m, layerID: "card", mask: Self.mask(20), index: -1),
            SetLayerMask(owner: Self.m, layerID: "card", index: 2, mask: Self.mask(20)),
            RemoveLayerMask(owner: Self.m, layerID: "photo", index: 0),
            MoveLayerMask(owner: Self.m, layerID: "card", from: 0, to: 2),
            MoveLayerMask(owner: Self.m, layerID: "card", from: -1, to: 0),
        ] as [any Command] { Self.expectRefused(command, on: start) }
    }
}
