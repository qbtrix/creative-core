// TrackCommandsTests.swift: the track family's registry ids, registry samples and
// undo steps. A new track command adds its id to `expectedIDs`, one sample to
// `registrySamples()` and its random steps to `undoSteps` here;
// CommandRegistryTests and UndoPropertyTests read all three, so neither shared
// test file changes.
// AP-3 turns the key checks on; Fixtures/tracks.flare keys fill, stroke, width and path.
import FlareCore
import Foundation
import Testing

@Suite struct TrackCommandsTests {
    /// Every id in `TrackCommands.all`, in order, written out by hand.
    static let expectedIDs: [String] = [
        "colorKey.set", "colorKey.remove", "colorKey.move", "shapeKey.set", "shapeKey.remove",
    ]

    /// The ids whose commands are still stubs that throw "not built"; each
    /// leaves this set when its task builds it and adds a registry sample.
    static let notBuiltIDs: Set<String> = Set(expectedIDs)

    /// One sample of every built track command (not in `notBuiltIDs`), each
    /// valid on `CommandRegistryTests.sampleDocument()`, in `expectedIDs` order.
    /// The shared tests execute every sample, so a stub gets one when it is built.
    static func registrySamples() -> [any Command] { [] }

    static let owner = LayerOwner.scene(Fixtures.sceneID)
    static let (red, blue) = (Color(r: 1, g: 0, b: 0), Color(r: 0, g: 0, b: 1))

    /// Fixtures/tracks.flare, decoded and validated through FlareFormat.
    static func fixture() throws -> Document {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/tracks.flare")
        return try FlareFormat.decode(Data(contentsOf: url))
    }
    static func fixtureScene() throws -> Scene { try #require(try fixture().scenes.first) }

    /// Random picks, some invalid: a missing layer, frames past 0...48, NaN or 1.5 colours, two-part paths.
    static func any<T>(_ items: [T], _ rng: inout SplitMix64) -> T { items[Int.random(in: 0..<items.count, using: &rng)] }
    static func anyOwner(_ rng: inout SplitMix64) -> (LayerOwner, String) { any([(owner, "ball"), (owner, "bg"), (owner, "ghost"), (.symbol("sym"), "wing")], &rng) }
    static func anyTarget(_ rng: inout SplitMix64) -> TrackTarget { any([.fill(shape: 0), .stroke(shape: 0), .fill(shape: 1), .text(index: 0)], &rng) }
    static func anyFrame(_ rng: inout SplitMix64) -> Int { any([0, 12, 24, 36, 48, -1, 49], &rng) }
    static func anyColor(_ rng: inout SplitMix64) -> Color {
        any([Color(r: .nan, g: 0, b: 0), Color(r: 0, g: 1.5, b: 0), Color(r: .random(in: 0...1, using: &rng), g: 0.5, b: .random(in: 0...1, using: &rng))], &rng)
    }
    static func anyEasing(_ rng: inout SplitMix64) -> Easing { any([.linear, .hold, .easeInOut], &rng) }
    static func anyPath(_ rng: inout SplitMix64) -> Path {
        let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)], closed: true)
        let star = (try? PathBuilders.star(in: Rect(minX: 0, minY: 0, maxX: 20, maxY: 20), points: 5, innerRatio: 0.5)) ?? square
        return any([square, star, Path(elements: square.elements + star.elements)], &rng)
    }

    /// Random track steps, valid and invalid, for assertUndoRestoresDocument.
    static let undoSteps: [UndoStep] = [
        { e, rng, _ in let (o, id) = anyOwner(&rng), drag = Bool.random(using: &rng) ? "colorKey.drag" : nil
            try e.perform(SetColorKeyframe(owner: o, layerID: id, target: anyTarget(&rng), frame: anyFrame(&rng),
                                           value: anyColor(&rng), easing: anyEasing(&rng)), coalesceKey: drag) },
        { e, rng, _ in let (o, id) = anyOwner(&rng)
            try e.perform(RemoveColorKeyframe(owner: o, layerID: id, target: anyTarget(&rng), frame: anyFrame(&rng))) },
        { e, rng, _ in let (o, id) = anyOwner(&rng)
            try e.perform(MoveColorKeyframes(owner: o, layerID: id, target: anyTarget(&rng),
                                             frames: [anyFrame(&rng), anyFrame(&rng)], by: Int.random(in: -30...30, using: &rng))) },
        { e, rng, _ in let (o, id) = anyOwner(&rng)
            try e.perform(SetShapeKeyframe(owner: o, layerID: id, shape: Int.random(in: 0...1, using: &rng),
                                           frame: anyFrame(&rng), path: anyPath(&rng), easing: anyEasing(&rng))) },
        { e, rng, _ in let (o, id) = anyOwner(&rng)
            try e.perform(RemoveShapeKeyframe(owner: o, layerID: id, shape: 0, frame: anyFrame(&rng))) },
    ]

    @Test func familyListsExactlyItsIDs() {
        #expect(TrackCommands.all.map { $0.id } == Self.expectedIDs)
    }

    @Test func samplesListExactlyItsIDs() {
        #expect(Self.registrySamples().map { type(of: $0).id } == Self.expectedIDs.filter { !Self.notBuiltIDs.contains($0) })
    }

    /// The fixture loads and validates; fill, stroke, stroke width and path are keyed at 0 and 24.
    @Test func fixtureValidates() throws {
        #expect(throws: Never.self) { try FlareFormat.validate(try Self.fixture()) }
        let layer = try #require(try Self.fixtureScene().layers.first)
        #expect(layer.colorTracks["fill.0"]?.map(\.frame) == [0, 24] && layer.colorTracks["stroke.0"]?.map(\.frame) == [0, 24])
        #expect(layer.tracks["strokeWidth.0"]?.map(\.value) == [2, 8])
        #expect(layer.shapeTracks.map(\.shapeIndex) == [0] && layer.shapeTracks.first?.keys.map(\.frame) == [0, 24])
        #expect(layer.shapeTracks.first?.keys.first?.path == layer.shapes.first?.outline)
    }

    // Ball's fill.0 (or `target`): a key, the keys, and a move.
    private func key(_ frame: Int, _ value: Color, _ easing: Easing = .linear, _ target: TrackTarget = .fill(shape: 0)) -> SetColorKeyframe {
        SetColorKeyframe(owner: Self.owner, layerID: "ball", target: target, frame: frame, value: value, easing: easing)
    }
    private func fills(_ engine: CommandEngine) -> [ColorKeyframe]? { engine.document.scenes.first?.layers.first { $0.id == "ball" }?.colorTracks["fill.0"] }
    private func move(_ frames: [Int], by delta: Int) -> MoveColorKeyframes {
        MoveColorKeyframes(owner: Self.owner, layerID: "ball", target: .fill(shape: 0), frames: frames, by: delta)
    }

    @Test(.disabled("AP-3 turns this on"))
    func setMoveRemoveUndoExactly() throws {
        var engine = CommandEngine(document: Fixtures.document()), states: [Document] = []
        let remove = RemoveColorKeyframe(owner: Self.owner, layerID: "ball", target: .fill(shape: 0), frame: 0)
        for command in [key(0, Self.red, .easeInOut), key(24, Self.blue), move([24], by: 12), remove] as [any Command] {
            states.append(engine.document)
            try engine.perform(command)
            if states.count == 2 { #expect(fills(engine) == [ColorKeyframe(frame: 0, value: Self.red, easing: .easeInOut), ColorKeyframe(frame: 24, value: Self.blue)]) }
            if states.count == 3 { #expect(fills(engine)?.map(\.frame) == [0, 36]) }
        }
        #expect(fills(engine) == [ColorKeyframe(frame: 36, value: Self.blue)])
        while let expected = states.popLast() {
            try engine.undo()
            #expect(engine.document == expected)
        }
    }

    @Test(.disabled("AP-3 turns this on"))
    func mergeOnlySameKey() throws {
        var drag = key(10, Self.red), other = key(10, Self.red, .linear, .stroke(shape: 0))
        let merged = [drag.merge(key(10, Self.blue)), drag.merge(key(20, Self.blue)), other.merge(key(10, Self.blue))]
        #expect(merged == [true, false, false])
        // A drag over two frames under one coalesce key keeps both keys and undoes in one step.
        var engine = CommandEngine(document: Fixtures.document())
        for (frame, value) in [(10, Self.red), (10, Self.blue), (20, Self.red)] { try engine.perform(key(frame, value), coalesceKey: "drag") }
        #expect(fills(engine) == [ColorKeyframe(frame: 10, value: Self.blue), ColorKeyframe(frame: 20, value: Self.red)])
        try engine.undo()
        #expect(engine.document == Fixtures.document() && !engine.canUndo)
    }

    @Test(.disabled("AP-3 turns this on"))
    func moveAllOrNothing() throws {
        var engine = CommandEngine(document: Fixtures.document())
        for frame in [0, 12, 40] { try engine.perform(key(frame, Self.red)) }
        let before = engine.document
        // 40 + 10 is past the 48-frame scene, so neither key moves.
        #expect(throws: CommandError.self) { try engine.perform(move([12, 40], by: 10)) }
        #expect(engine.document == before)
    }

    @Test(.disabled("AP-3 turns this on"))
    func keysStaySorted() throws {
        var engine = CommandEngine(document: Fixtures.document())
        for (frame, value) in [(0, Self.red), (12, Self.blue), (24, Color.white)] { try engine.perform(key(frame, value)) }
        try engine.perform(move([0], by: 18))
        #expect(fills(engine)?.map(\.frame) == [12, 18, 24])
        #expect(fills(engine)?.map(\.value) == [Self.blue, Self.red, .white])
    }

    @Test(.disabled("AP-3 turns this on"))
    func badColourAndLockedLayerRefused() throws {
        var locked = Fixtures.document()
        locked.scenes[0].layers[1].isLocked = true
        var engine = CommandEngine(document: locked)
        #expect(throws: CommandError.layerLocked("ball")) { try engine.perform(key(0, Self.red)) }
        engine = CommandEngine(document: Fixtures.document())
        for bad in [Color(r: .nan, g: 0, b: 0), Color(r: 0, g: 0, b: 1.5), Color(r: 0, g: 0, b: 0, a: .infinity)] {
            #expect(throws: CommandError.self) { try engine.perform(key(0, bad)) }
        }
        #expect(engine.document == Fixtures.document())
    }

    @Test(.disabled("AP-3 turns this on"), arguments: 0..<100)
    func undoAllRestoresOriginal(seed: UInt64) throws {
        try assertUndoRestoresDocument(seed: seed, steps: Self.undoSteps, start: Fixtures.withSymbol())
    }
}
