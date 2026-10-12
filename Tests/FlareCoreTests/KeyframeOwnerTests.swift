// KeyframeOwnerTests.swift: the five keyframe commands take an owner, so they
// edit a symbol's layers as well as a scene's. Drags on different owners never
// coalesce, and pre-owner scene envelopes still encode byte for byte.
@testable import FlareCore
import Foundation
import Testing

@Suite struct KeyframeOwnerTests {
    static let registry = CommandRegistry.builtIn

    /// `Fixtures.withSymbol()` with a copy of the scene's "ball" layer in "sym",
    /// so the same layer id lives under both owners.
    static func sharedBallDocument() -> Document {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers.append(doc.scenes[0].layers[1])
        return doc
    }

    @Test func keysALayerMovedIntoASymbol() throws {
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
        let converted = engine.document
        try engine.perform(SetKeyframe(owner: .symbol("sym"), layerID: "ball", property: "x",
                                       keyframe: Keyframe(frame: 3, value: 10)))
        #expect(engine.document.symbols[0].layers[0].keyframe(at: 3, property: "x") == Keyframe(frame: 3, value: 10))
        try engine.undo()
        #expect(engine.document == converted)
    }

    @Test func everyKeyframeCommandEditsASymbolLayerAndUndoesExactly() throws {
        let owner = LayerOwner.symbol("sym")
        let commands: [any Command] = [
            SetKeyframe(owner: owner, layerID: "wing", property: "x", keyframe: Keyframe(frame: 8, value: 1)),
            MoveKeyframe(owner: owner, layerID: "wing", property: "x", from: 0, to: 4),
            RemoveKeyframe(owner: owner, layerID: "wing", property: "x", frame: 0),
            SetKeyframeEasing(owner: owner, layerID: "wing", property: "x", frame: 0, easing: .easeIn),
            ShiftKeyframes(owner: owner, layerID: "wing", fromFrame: 0, toFrame: 0, delta: 7),
        ]
        let expected: [[Keyframe]] = [
            [Keyframe(frame: 0, value: 5), Keyframe(frame: 8, value: 1)],
            [Keyframe(frame: 4, value: 5)],
            [],
            [Keyframe(frame: 0, value: 5, easing: .easeIn)],
            [Keyframe(frame: 7, value: 5)],
        ]
        for (command, track) in zip(commands, expected) {
            var engine = CommandEngine(document: Fixtures.withSymbol())
            let original = engine.document
            try engine.perform(command)
            #expect((engine.document.symbols[0].layers[0].tracks["x"] ?? []) == track, "\(type(of: command).id)")
            #expect(engine.document.scenes == original.scenes)
            try engine.undo()
            #expect(engine.document == original, "\(type(of: command).id)")
        }
    }

    @Test func lockedSymbolLayerAndMissingSymbolThrowWithoutChanges() {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers[0].isLocked = true
        var engine = CommandEngine(document: doc)
        #expect(throws: CommandError.layerLocked("wing")) {
            try engine.perform(SetKeyframe(owner: .symbol("sym"), layerID: "wing", property: "x",
                                           keyframe: Keyframe(frame: 2, value: 0)))
        }
        #expect(throws: CommandError.symbolNotFound("ghost")) {
            try engine.perform(ShiftKeyframes(owner: .symbol("ghost"), layerID: "wing", fromFrame: 0, toFrame: 9, delta: 1))
        }
        #expect(engine.document == doc)
        #expect(!engine.canUndo)
    }

    @Test func dragInsideASymbolIsOneUndoEntryAndNeverMergesWithTheScene() throws {
        var doc = Self.sharedBallDocument()
        _ = doc.scenes[0].layers[1].setKeyframe(Keyframe(frame: 34, value: 0), property: "x")
        var engine = CommandEngine(document: doc)
        for i in 0..<10 {
            try engine.perform(MoveKeyframe(owner: .symbol("sym"), layerID: "ball", property: "x",
                                            from: 24 + i, to: 25 + i), coalesceKey: "drag")
        }
        let dragged = engine.document
        #expect(dragged.symbols[0].layers[2].tracks["x"]?.map(\.frame) == [0, 34])
        // Same key, layer id, property and frame: only the owner differs. A
        // wrong merge would move the symbol's key on to 35 and skip the scene.
        try engine.perform(MoveKeyframe(owner: .scene(Fixtures.sceneID), layerID: "ball", property: "x",
                                        from: 34, to: 35), coalesceKey: "drag")
        #expect(engine.document.scenes[0].layers[1].tracks["x"]?.map(\.frame) == [0, 24, 35])
        #expect(engine.document.symbols == dragged.symbols)
        try engine.undo()
        #expect(engine.document == doc)
        #expect(!engine.canUndo)

        var a = MoveKeyframe(owner: .symbol("sym"), layerID: "ball", property: "x", from: 0, to: 1)
        let otherOwner = a.merge(MoveKeyframe(owner: .scene("sym"), layerID: "ball", property: "x", from: 1, to: 2))
        #expect(!otherOwner)
        #expect(a.to == 1)
        let sameOwner = a.merge(MoveKeyframe(owner: .symbol("sym"), layerID: "ball", property: "x", from: 1, to: 2))
        #expect(sameOwner)
        #expect(a.to == 2)
    }

    /// Envelopes as written before keyframe commands took an owner.
    static let sceneEnvelopes = [
        #"{"id":"keyframe.set","params":{"keyframe":{"easing":{"linear":{}},"frame":3,"value":10},"layerID":"ball","property":"x","sceneID":"s1"}}"#,
        #"{"id":"keyframe.move","params":{"from":0,"layerID":"ball","property":"x","sceneID":"s1","to":5}}"#,
        #"{"id":"keyframe.remove","params":{"frame":24,"layerID":"ball","property":"x","sceneID":"s1"}}"#,
        #"{"id":"keyframe.setEasing","params":{"easing":{"hold":{}},"frame":24,"layerID":"ball","property":"x","sceneID":"s1"}}"#,
        #"{"id":"keyframe.shift","params":{"delta":5,"fromFrame":0,"layerID":"ball","sceneID":"s1","toFrame":24}}"#,
    ]

    @Test(arguments: sceneEnvelopes)
    func sceneEnvelopeStaysByteIdentical(_ json: String) throws {
        let command = try Self.registry.decode(Data(json.utf8))
        #expect(String(decoding: try Self.registry.encode(command), as: UTF8.self) == json)
        var engine = CommandEngine(document: Fixtures.document())
        try engine.perform(command)
        #expect(engine.document != Fixtures.document())
    }

    @Test(arguments: sceneEnvelopes)
    func symbolEnvelopeRoundTripsAndEditsTheSymbol(_ sceneJSON: String) throws {
        let json = sceneJSON.replacingOccurrences(of: #""sceneID":"s1""#, with: #""symbolID":"sym""#)
        let command = try Self.registry.decode(Data(json.utf8))
        #expect(String(decoding: try Self.registry.encode(command), as: UTF8.self) == json)
        var engine = CommandEngine(document: Self.sharedBallDocument())
        let original = engine.document
        try engine.perform(command)
        #expect(engine.document.symbols != original.symbols)
        #expect(engine.document.scenes == original.scenes)
        try engine.undo()
        #expect(engine.document == original)
    }

    @Test func envelopeWithBothOrNeitherOwnerKeyThrows() {
        for json in [
            #"{"id":"keyframe.remove","params":{"frame":24,"layerID":"ball","property":"x","sceneID":"s1","symbolID":"sym"}}"#,
            #"{"id":"keyframe.remove","params":{"frame":24,"layerID":"ball","property":"x"}}"#,
        ] {
            #expect(throws: CommandError.self) { try Self.registry.decode(Data(json.utf8)) }
        }
    }
}
