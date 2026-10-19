// CommandRegistryTests.swift: every built-in command round-trips through the
// {"id", "params"} envelope and behaves the same after decoding (the ids are
// checked family by family against hand-written lists, 73 in all), and encode
// only their params, so a command decoded after execute is fresh; unknown ids
// and malformed envelopes throw a CommandError, never crash (seeded fuzz).
@testable import FlareCore
import Foundation
import Testing

@Suite struct CommandRegistryTests {
    static let registry = CommandRegistry.builtIn

    /// Every built-in family's ids, in `CommandRegistry.builtInFamilies`
    /// order and each in its family's `all` order, written out by hand so a
    /// command that no family lists, a family missing from the registry, or an
    /// id listed under the wrong family fails the tests. A family with its own
    /// test file keeps its list there, so a new command touches only its
    /// family's two files (ids, samples and undo steps); a new family adds
    /// one line here and one in `samples()`.
    static let familyIDs: [[String]] = [
        ["layer.add", "layer.remove", "layer.rename",
         "keyframe.set", "keyframe.move", "keyframe.remove", "shape.add"],
        ["layer.setFlags", "layer.reorder", "layer.duplicate"],
        ["shape.remove", "shape.setFill", "shape.setStroke", "shape.setPath", "shape.translate"],
        ["scene.add", "scene.remove", "scene.timing", "scene.setCanvas", "scene.rename", "scene.reorder"],
        ["keyframe.setEasing", "keyframe.shift"],
        ["document.metadata"],
        ["label.set", "label.remove"],
        ["guide.add", "guide.move", "guide.remove"],
        ["symbol.add", "symbol.remove", "symbol.rename", "symbol.convert"],
        ["text.add", "text.remove", "text.setString", "text.setFont"],
        ["swatch.add", "swatch.rename", "swatch.setColor", "swatch.remove"],
        ["instance.add", "instance.remove", "instance.setTransform", "instance.setPlayback"],
        ["machine.add", "machine.rename", "machine.remove", "machine.setInitial",
         "machine.addState", "machine.updateState", "machine.removeState",
         "machine.addTransition", "machine.updateTransition", "machine.removeTransition",
         "machine.addInput", "machine.updateInput", "machine.removeInput"],
        MaskCommandsTests.expectedIDs,
        TextStyleCommandsTests.expectedIDs,
        TrackCommandsTests.expectedIDs,
    ]

    /// Every built-in command id: the union of the family lists.
    static let expectedIDs = Set(familyIDs.joined())

    /// The ids still stubs that throw "not built", so they have no sample yet.
    static let notBuiltIDs = TrackCommandsTests.notBuiltIDs.union(TextStyleCommandsTests.notBuiltIDs)

    /// One sample of every built-in command, each valid on the fixture document.
    /// A new family adds one line here; a new command goes in its family's samples.
    static func samples() -> [any Command] {
        coreSamples()
            + SceneCommandTests.registrySamples()
            + KeyframeCommandsTests.registrySamples()
            + MetadataCommandsTests.registrySamples()
            + LabelCommandsTests.registrySamples()
            + GuideCommandsTests.registrySamples()
            + SymbolCommandsTests.registrySamples()
            + TextCommandsTests.registrySamples()
            + SwatchCommandsTests.registrySamples()
            + InstanceCommandsTests.registrySamples()
            + MachineCommandTests.registrySamples()
            + MachineStateCommandTests.registrySamples()
            + TransitionCommandTests.registrySamples()
            + MachineInputCommandTests.registrySamples()
            + MaskCommandsTests.registrySamples()
            + TextStyleCommandsTests.registrySamples()
            + TrackCommandsTests.registrySamples()
    }

    /// The text fixture plus a second, empty scene, unused symbol "spark",
    /// symbol "dot" (layer "d") placed on "bg", one guide, one swatch and
    /// state machine "btn" on "outro" with an extra unnamed state "off" and
    /// a bool input "on", so every sample is valid on it.
    static func sampleDocument() -> Document {
        var doc = TextCommandsTests.withText()
        doc.scenes.append(Scene(id: "outro", name: "Outro"))
        doc.symbols = [Symbol(id: "spark", name: "Spark", durationFrames: 6,
                              layers: [Layer(id: "glow", name: "Glow"), Layer(id: "core", name: "Core")]),
                       Symbol(id: "dot", name: "Dot", layers: [Layer(id: "d", name: "D")])]
        doc.scenes[0].layers[0].instances = [Instance(symbolID: "dot")]
        doc.symbols[0].layers[1].shapes = doc.scenes[0].layers[1].shapes
        doc.symbols[0].layers[1].texts = doc.scenes[0].layers[1].texts
        doc.scenes[0].guides = GuideCommandsTests.guided().scenes[0].guides
        doc.swatches = [Swatch(name: "Ink", color: .black)]
        doc.stateMachines = [MachineCommandTests.button(scene: "outro")]
        doc.stateMachines[0].states.append(MachineState(id: "off", name: "Off", sceneID: "outro",
                                                        startFrame: 41, endFrame: 48))
        doc.stateMachines[0].inputs = [MachineInputCommandTests.on]
        TrackCommandsTests.addSampleTrack(&doc)
        TextStyleCommandsTests.addSampleRuns(&doc)
        MaskCommandsTests.addSampleMasks(&doc)
        return doc
    }

    /// One sample of each layer, keyframe and shape command.
    static func coreSamples() -> [any Command] {
        let s = Fixtures.sceneID
        return [
            AddLayer(owner: .scene(s), layer: Layer(id: "new", name: "New"), index: 1),
            RemoveLayer(owner: .scene(s), layerID: "bg"),
            RenameLayer(owner: .scene(s), layerID: "ball", name: "Sphere"),
            SetKeyframe(owner: .scene(s), layerID: "ball", property: "y",
                        keyframe: Keyframe(frame: 12, value: 5, easing: .easeInOut)),
            MoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", from: 24, to: 30),
            RemoveKeyframe(owner: .scene(s), layerID: "ball", property: "x", frame: 0),
            AddShape(owner: .scene(s), layerID: "bg",
                     shape: Shape(points: [Point(x: 1, y: 2), Point(x: 3, y: 4)], closed: false)),
            ReorderLayer(owner: .scene(s), layerID: "bg", toIndex: 1),
            SetLayerFlags(owner: .scene(s), layerID: "ball", isVisible: false, isLocked: true),
            DuplicateLayer(owner: .scene(s), layerID: "ball"),
            RemoveShape(owner: .scene(s), layerID: "ball", index: 0),
            SetShapeFill(owner: .scene(s), layerID: "ball", index: 0, fill: .solid(Color(r: 0, g: 0, b: 1))),
            SetShapeStroke(owner: .scene(s), layerID: "ball", index: 0, stroke: Stroke(width: 2, cap: .round)),
            SetShapePath(owner: .scene(s), layerID: "ball", index: 0, path: StrokePathCommandTests.cubic,
                         points: StrokePathCommandTests.cubicPoints),
            TranslateShape(owner: .scene(s), layerID: "ball", index: 0, dx: 1, dy: 1),
        ]
    }

    /// One symbol-owned sample per command that takes an owner, valid on
    /// `sampleDocument()`. Kept apart from `samples()`, which holds one per id.
    static func symbolSamples() -> [any Command] {
        let sym = LayerOwner.symbol("spark")
        return [
            AddLayer(owner: sym, layer: Layer(id: "new", name: "New"), index: 0),
            RemoveLayer(owner: sym, layerID: "glow"),
            RenameLayer(owner: sym, layerID: "core", name: "Heart"),
            ReorderLayer(owner: sym, layerID: "glow", toIndex: 1),
            SetLayerFlags(owner: sym, layerID: "core", isLocked: true),
            DuplicateLayer(owner: sym, layerID: "core"),
        ] + ShapeTextOwnerTests.edits(sym, layerID: "core")
    }

    @Test func everyBuiltInCommandIsRegistered() {
        #expect(Self.expectedIDs.count == 73)
        #expect(Set(Self.registry.ids) == Self.expectedIDs)
    }

    /// Each family registers exactly its own list, and no id is listed twice,
    /// within a family or across two.
    @Test func everyFamilyRegistersExactlyItsList() {
        let families = CommandRegistry.builtInFamilies
        #expect(families.count == Self.familyIDs.count)
        for (family, ids) in zip(families, Self.familyIDs) {
            #expect(family.map { $0.id } == ids)
        }
        let listed = Array(Self.familyIDs.joined())
        #expect(listed.count == Self.expectedIDs.count, "an id is listed twice")
    }

    /// The W1 seams: mask, text style and track families are registered, last
    /// and in that order.
    @Test func w1FamiliesAreRegistered() {
        let ids = CommandRegistry.builtInFamilies.suffix(3).map { $0.map { $0.id } }
        #expect(ids == [MaskCommands.all, TextStyleCommands.all, TrackCommands.all].map { $0.map { $0.id } })
        #expect(ids == [MaskCommandsTests.expectedIDs, TextStyleCommandsTests.expectedIDs, TrackCommandsTests.expectedIDs])
    }

    @Test func samplesCoverEveryBuiltIn() {
        // Stubs throw "not built" until their task lands, so they have no sample yet.
        let built = Self.expectedIDs.subtracting(Self.notBuiltIDs)
        let sampled = Set(Self.samples().map { type(of: $0).id })
        #expect(sampled == built)
        #expect(Self.samples().count == built.count)
    }

    @Test func everyBuiltInRoundTripsAndBehavesTheSame() throws {
        for original in Self.samples() + Self.symbolSamples() {
            let data = try Self.registry.encode(original)
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(object?["id"] as? String == type(of: original).id)
            #expect(object?["params"] is [String: Any])
            if original is any LayerCommand, let params = object?["params"] as? [String: Any] {
                #expect(params.keys.filter { $0 == "sceneID" || $0 == "symbolID" }.count == 1, "owner not flat")
            }

            let decoded = try Self.registry.decode(data)
            #expect(type(of: decoded).id == type(of: original).id)
            #expect(decoded.label == original.label)
            #expect(try Self.registry.encode(decoded) == data)

            var a = original, b = decoded
            let start = Self.sampleDocument()
            var docA = start, docB = start
            try a.execute(&docA)
            try b.execute(&docB)
            #expect(docA == docB, "\(type(of: original).id) behaves differently after decoding")
            #expect(docA != start)
            try a.undo(&docA)
            try b.undo(&docB)
            #expect(docA == start)
            #expect(docB == start)
        }
    }

    @Test func encodedCommandCarriesParamsOnly() throws {
        var cmd = RemoveLayer(owner: .scene("s1"), layerID: "ball")
        var d = Fixtures.document()
        try cmd.execute(&d)
        let data = try Self.registry.encode(cmd)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json == #"{"id":"layer.remove","params":{"layerID":"ball","sceneID":"s1"}}"#)

        // A decoded command is fresh: undo before execute throws, execute works.
        let decoded = try Self.registry.decode(data)
        var fresh = Fixtures.document()
        #expect(throws: CommandError.notExecuted) { try decoded.undo(&fresh) }
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(decoded)
        #expect(e.document.scenes[0].layers.map(\.id) == ["bg"])
        try e.undo()
        #expect(e.document == Fixtures.document())
    }

    /// Executing a command never changes its encoding, and the copy decoded
    /// from an executed command performs and undoes exactly on a fresh document.
    @Test func everyBuiltInEncodesTheSameAfterExecute() throws {
        let start = Self.sampleDocument()
        for original in Self.samples() + Self.symbolSamples() {
            let id = type(of: original).id
            let before = try Self.registry.encode(original)
            var executed = original
            var doc = start
            try executed.execute(&doc)
            let after = try Self.registry.encode(executed)
            #expect(after == before, "\(id) encodes undo state")

            var e = CommandEngine(document: start)
            try e.perform(try Self.registry.decode(after))
            #expect(e.document == doc, "\(id)")
            try e.undo()
            #expect(e.document == start, "\(id)")
        }
    }

    @Test func decodesHandWrittenEnvelope() throws {
        let json = #"{"id":"keyframe.move","params":{"sceneID":"s1","layerID":"ball","property":"x","from":0,"to":5}}"#
        var cmd = try Self.registry.decode(Data(json.utf8))
        var doc = Fixtures.document()
        try cmd.execute(&doc)
        #expect(doc.scenes[0].layers[1].tracks["x"]?.first?.frame == 5)
    }

    /// Envelopes written before layer list commands took an owner decode as
    /// scene-owned, perform, and re-encode byte for byte.
    @Test(arguments: [
        #"{"id":"layer.add","params":{"index":1,"layer":{"id":"new","instances":[],"isLocked":false,"isVisible":true,"#
            + #""name":"New","shapes":[],"tracks":{}},"sceneID":"s1"}}"#,
        #"{"id":"layer.remove","params":{"layerID":"bg","sceneID":"s1"}}"#,
        #"{"id":"layer.rename","params":{"layerID":"ball","name":"Sphere","sceneID":"s1"}}"#,
        #"{"id":"layer.reorder","params":{"layerID":"bg","sceneID":"s1","toIndex":1}}"#,
        #"{"id":"layer.setFlags","params":{"isLocked":true,"layerID":"ball","sceneID":"s1"}}"#,
    ])
    func preOwnerLayerEnvelopesStayByteIdentical(_ json: String) throws {
        let decoded = try Self.registry.decode(Data(json.utf8))
        #expect((decoded as? any LayerCommand)?.owner == .scene("s1"))
        #expect(try Self.registry.encode(decoded) == Data(json.utf8))
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(decoded)
        #expect(e.document != Fixtures.document())
    }

    @Test func unknownIDThrows() {
        #expect(throws: CommandError.unknownCommand("layer.explode")) {
            try Self.registry.decode(Data(#"{"id":"layer.explode","params":{}}"#.utf8))
        }
        #expect(throws: CommandError.unknownCommand("layer.add")) {
            try CommandRegistry().decode(Data(#"{"id":"layer.add","params":{}}"#.utf8))
        }
        #expect(throws: CommandError.unknownCommand("layer.rename")) {
            try CommandRegistry().encode(RenameLayer(owner: .scene("s"), layerID: "l", name: "n"))
        }
    }

    @Test(arguments: [
        "", "null", "[]", "{", "{}", #"{"id":3,"params":{}}"#,
        #"{"params":{"sceneID":"s1","layerID":"bg"}}"#,
        #"{"id":"layer.remove"}"#,
        #"{"id":"layer.remove","params":null}"#,
        #"{"id":"layer.remove","params":[]}"#,
        #"{"id":"layer.remove","params":{"sceneID":"s1"}}"#,
        #"{"id":"layer.remove","params":{"layerID":"bg"}}"#,
        #"{"id":"layer.remove","params":{"layerID":"bg","sceneID":"s1","symbolID":"spark"}}"#,
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
