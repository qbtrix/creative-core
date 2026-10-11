// CommandRegistryTests.swift: every built-in command round-trips through the
// {"id", "params"} envelope and behaves the same after decoding; unknown ids
// and malformed envelopes throw a CommandError, never crash (seeded fuzz).
import FlareCore
import Foundation
import Testing

@Suite struct CommandRegistryTests {
    static let registry = CommandRegistry.builtIn

    /// One sample of every built-in command, each valid on the fixture document.
    /// A new family adds one line here; a new command goes in its family's samples.
    static func samples() -> [any Command] {
        coreSamples()
            + SceneCommandTests.registrySamples()
            + KeyframeCommandsTests.registrySamples()
    }

    /// One sample of each layer, keyframe and shape command.
    static func coreSamples() -> [any Command] {
        let s = Fixtures.sceneID
        return [
            AddLayer(sceneID: s, layer: Layer(id: "new", name: "New"), index: 1),
            RemoveLayer(sceneID: s, layerID: "bg"),
            RenameLayer(sceneID: s, layerID: "ball", name: "Sphere"),
            SetKeyframe(sceneID: s, layerID: "ball", property: "y",
                        keyframe: Keyframe(frame: 12, value: 5, easing: .easeInOut)),
            MoveKeyframe(sceneID: s, layerID: "ball", property: "x", from: 24, to: 30),
            RemoveKeyframe(sceneID: s, layerID: "ball", property: "x", frame: 0),
            AddShape(sceneID: s, layerID: "bg",
                     shape: Shape(points: [Point(x: 1, y: 2), Point(x: 3, y: 4)], closed: false)),
            ReorderLayer(sceneID: s, layerID: "bg", toIndex: 1),
        ]
    }

    @Test func samplesCoverEveryBuiltIn() {
        let sampled = Set(Self.samples().map { type(of: $0).id })
        #expect(sampled == Set(Self.registry.ids))
        #expect(Self.registry.ids.count == Self.samples().count)
        #expect(Self.registry.ids.count == 13)
    }

    @Test func everyBuiltInRoundTripsAndBehavesTheSame() throws {
        for original in Self.samples() {
            let data = try Self.registry.encode(original)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(object?["id"] as? String == type(of: original).id)
            #expect(object?["params"] is [String: Any])

            let decoded = try Self.registry.decode(data)
            #expect(type(of: decoded).id == type(of: original).id)
            #expect(decoded.label == original.label)
            #expect(try Self.registry.encode(decoded) == data)

            var a = original, b = decoded
            var docA = Fixtures.document(), docB = Fixtures.document()
            try a.execute(&docA)
            try b.execute(&docB)
            #expect(docA == docB, "\(type(of: original).id) behaves differently after decoding")
            #expect(docA != Fixtures.document())
            try a.undo(&docA)
            try b.undo(&docB)
            #expect(docA == Fixtures.document())
            #expect(docB == Fixtures.document())
        }
    }

    @Test func decodesHandWrittenEnvelope() throws {
        let json = #"{"id":"keyframe.move","params":{"sceneID":"s1","layerID":"ball","property":"x","from":0,"to":5}}"#
        var cmd = try Self.registry.decode(Data(json.utf8))
        var doc = Fixtures.document()
        try cmd.execute(&doc)
        #expect(doc.scenes[0].layers[1].tracks["x"]?.first?.frame == 5)
    }

    @Test func unknownIDThrows() {
        #expect(throws: CommandError.unknownCommand("layer.explode")) {
            try Self.registry.decode(Data(#"{"id":"layer.explode","params":{}}"#.utf8))
        }
        #expect(throws: CommandError.unknownCommand("layer.add")) {
            try CommandRegistry().decode(Data(#"{"id":"layer.add","params":{}}"#.utf8))
        }
        #expect(throws: CommandError.unknownCommand("layer.rename")) {
            try CommandRegistry().encode(RenameLayer(sceneID: "s", layerID: "l", name: "n"))
        }
    }

    @Test(arguments: [
        "", "null", "[]", "{", "{}", #"{"id":3,"params":{}}"#,
        #"{"params":{"sceneID":"s1","layerID":"bg"}}"#,
        #"{"id":"layer.remove"}"#,
        #"{"id":"layer.remove","params":null}"#,
        #"{"id":"layer.remove","params":[]}"#,
        #"{"id":"layer.remove","params":{"sceneID":"s1"}}"#,
        #"{"id":"keyframe.move","params":{"sceneID":"s1","layerID":"b","property":"x","from":"0","to":1}}"#,
        #"{"id":"keyframe.move","params":{"sceneID":"s1","layerID":"b","property":"x","from":0,"to":99999999999999999999999}}"#,
    ])
    func malformedEnvelopeThrows(_ json: String) {
        #expect(throws: CommandError.self, "\(json)") { try Self.registry.decode(Data(json.utf8)) }
    }

    @Test func mutationFuzzNeverCrashes() throws {
        let valid = try Self.samples().map { Array(try Self.registry.encode($0)) }
        var rng = SplitMix64(seed: 11)
        let alphabet = Array(#"{}[]",:0123456789-.eE truefalsn\"#.utf8)
        for _ in 0..<3000 {
            var bytes = valid.randomElement(using: &rng) ?? [0x7B]
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                let i = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: bytes[i] = alphabet.randomElement(using: &rng) ?? 0
                case 1: bytes.remove(at: i)
                default: bytes.insert(alphabet.randomElement(using: &rng) ?? 0, at: i)
                }
                if bytes.isEmpty { bytes = [0x7B] }
            }
            do {
                var cmd = try Self.registry.decode(Data(bytes))
                var doc = Fixtures.document()
                try? cmd.execute(&doc)
            } catch is CommandError {
                // expected
            } catch {
                Issue.record("non-CommandError thrown: \(error)")
            }
        }
    }
}
