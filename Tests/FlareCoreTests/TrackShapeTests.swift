// TrackShapeTests.swift: the animate-properties contract (AP-1). The colour and
// shape key commands are registered under their ids and round-trip through the
// registry; `TrackTarget.key` names the `Layer.colorTracks` key; the stubs
// throw `CommandError.notBuilt` naming the command id instead of trapping; and a layer without tracks
// samples as static (nil), including one decoded from a file that lacks them.
@testable import FlareCore
import Foundation
import Testing

@Suite struct TrackShapeTests {
    static let owner = LayerOwner.scene(Fixtures.sceneID)
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    /// One of each track command, with every param set off its default.
    static func commands() -> [any Command] {
        [
            SetColorKeyframe(owner: owner, layerID: "ball", target: .fill(shape: 0), frame: 4,
                             value: Color(r: 1, g: 0, b: 0), easing: .easeInOut),
            RemoveColorKeyframe(owner: owner, layerID: "ball", target: .stroke(shape: 1), frame: 4),
            MoveColorKeyframes(owner: owner, layerID: "ball", target: .text(index: 2), frames: [0, 4], by: 3),
            SetShapeKeyframe(owner: owner, layerID: "ball", shape: 0, frame: 8, path: square, easing: .hold),
            RemoveShapeKeyframe(owner: owner, layerID: "ball", shape: 0, frame: 8),
        ]
    }

    @Test func idsAreRegistered() {
        let ids = ["colorKey.set", "colorKey.remove", "colorKey.move", "shapeKey.set", "shapeKey.remove"]
        #expect(TrackCommands.all.map { $0.id } == ids)
        #expect(Set(ids).isSubset(of: Set(CommandRegistry.builtIn.ids)))
        #expect(Self.commands().map { type(of: $0).id } == ids)
    }

    @Test func targetKeys() {
        #expect(TrackTarget.fill(shape: 0).key == "fill.0")
        #expect(TrackTarget.stroke(shape: 3).key == "stroke.3")
        #expect(TrackTarget.text(index: 12).key == "text.12")
        #expect(TrackTarget.fill(shape: 1) != .stroke(shape: 1))
    }

    @Test func strokeWidthKey() {
        #expect(Layer.trackKey(strokeWidthOf: 2) == "strokeWidth.2")
    }

    @Test func commandsRoundTripThroughTheRegistry() throws {
        for command in Self.commands() {
            let data = try CommandRegistry.builtIn.encode(command)
            let decoded = try CommandRegistry.builtIn.decode(data)
            #expect(type(of: decoded).id == type(of: command).id)
            #expect(decoded.label == command.label)
            #expect(try CommandRegistry.builtIn.encode(decoded) == data)
            #expect((decoded as? any LayerCommand)?.layerID == "ball")
        }
    }

    /// The commands still stubs (`TrackCommandsTests.notBuiltIDs`); CommandFuzzTests fuzzes the built ones.
    static func stubs() -> [any Command] { commands().filter { TrackCommandsTests.notBuiltIDs.contains(type(of: $0).id) } }

    @Test func stubsThrowNotBuilt() throws {
        for command in Self.stubs() {
            let notBuilt = CommandError.notBuilt("\(type(of: command).id) is not built yet (animate-properties)")
            var cmd = command
            var doc = Fixtures.document()
            #expect(throws: notBuilt) { try cmd.execute(&doc) }
            #expect(throws: notBuilt) { try cmd.undo(&doc) }
            #expect(doc == Fixtures.document())
            var engine = CommandEngine(document: Fixtures.document())
            #expect(throws: notBuilt) { try engine.perform(command) }
            #expect(engine.document == Fixtures.document())
            #expect(!engine.canUndo)
        }
    }

    /// Seeded byte fuzz of the stubs' envelopes: decode throws a CommandError or
    /// yields a command whose perform throws one and changes nothing.
    @Test func envelopeFuzzThrowsCleanly() throws {
        let valid = try Self.stubs().map { Array(try CommandRegistry.builtIn.encode($0)) }
        let alphabet = Array(#"{}[]",:0123456789-.eE truefalsn\"#.utf8)
        var rng = SplitMix64(seed: 442)
        for _ in 0..<2000 {
            var bytes = valid[Int.random(in: 0..<valid.count, using: &rng)]
            for _ in 0..<Int.random(in: 1...4, using: &rng) {
                let i = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: bytes[i] = alphabet.randomElement(using: &rng) ?? 0
                case 1: bytes.remove(at: i)
                default: bytes.insert(alphabet.randomElement(using: &rng) ?? 0, at: i)
                }
                if bytes.isEmpty { bytes = [0x7B] }
            }
            let command: any Command
            do { command = try CommandRegistry.builtIn.decode(Data(bytes)) } catch is CommandError { continue }
            var engine = CommandEngine(document: Fixtures.document())
            #expect(throws: CommandError.self) { try engine.perform(command) }
            #expect(engine.document == Fixtures.document())
        }
    }

    /// Old files load: a layer whose JSON has no colorTracks or shapeTracks
    /// decodes with both empty and samples as static.
    @Test func staticWhenEmpty() throws {
        let json = #"{"id":"l","name":"L","shapes":[],"tracks":{},"isVisible":true,"isLocked":false}"#
        let layer = try JSONDecoder().decode(Layer.self, from: Data(json.utf8))
        #expect(layer.colorTracks.isEmpty && layer.shapeTracks.isEmpty)
        for target in [TrackTarget.fill(shape: 0), .stroke(shape: 0), .text(index: 0)] {
            #expect(layer.sampledColor(target, at: 0) == nil)
            #expect(layer.sampledColor(target, at: .nan) == nil)
        }
        #expect(layer.sampledPath(shape: 0, at: 12) == nil)
        #expect(layer.sampledPath(shape: -1, at: .infinity) == nil)
    }
}
