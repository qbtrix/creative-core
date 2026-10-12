// LayerListOwnerAdversarialTests.swift: edge cases and fuzz for the layer list
// commands (add, remove, rename, reorder, flags) on symbol owners: shared scene
// and symbol ids, missing owners, extreme indices, invalid layer content, the
// layer limit, symbol-keyed envelopes, and a seeded mixed-owner run.
@testable import FlareCore
import Foundation
import Testing

@Suite struct LayerListOwnerAdversarialTests {
    private static let registry = CommandRegistry.builtIn

    /// `Fixtures.withSymbol()` with the symbol renamed to "s1", so a scene and
    /// a symbol share an id.
    private static func sharedIDs() -> Document {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].id = "s1"
        return doc
    }

    /// One command of each layer list type against `owner`, valid for both
    /// fixtures' layer names ("wing" in the symbol, "ball" in the scene).
    private static func commands(_ owner: LayerOwner, layer: String) -> [any Command] {
        [
            AddLayer(owner: owner, layer: Layer(id: "fresh", name: "Fresh"), index: 0),
            RenameLayer(owner: owner, layerID: layer, name: "Renamed"),
            ReorderLayer(owner: owner, layerID: layer, toIndex: 0),
            SetLayerFlags(owner: owner, layerID: layer, isVisible: false, isLocked: true),
            RemoveLayer(owner: owner, layerID: layer),
        ]
    }

    @Test func sharedSceneAndSymbolIDsStayApart() throws {
        let start = Self.sharedIDs()
        for (owner, layer) in [(LayerOwner.symbol("s1"), "tail"), (.scene("s1"), "ball")] {
            for command in Self.commands(owner, layer: layer) {
                var e = CommandEngine(document: start)
                try e.perform(command)
                if case .symbol = owner {
                    #expect(e.document.scenes == start.scenes, "\(command.label) touched the scene")
                } else {
                    #expect(e.document.symbols == start.symbols, "\(command.label) touched the symbol")
                }
                try e.undo()
                #expect(e.document == start)
                try e.redo()
                try e.undo()
                #expect(e.document == start)
            }
        }
    }

    @Test func missingOwnersThrowAndChangeNothing() {
        let start = Fixtures.withSymbol()
        let cases: [(LayerOwner, CommandError)] = [
            (.symbol("ghost"), .symbolNotFound("ghost")), (.scene("ghost"), .sceneNotFound("ghost")),
            (.symbol(""), .symbolNotFound("")), (.scene("sym"), .sceneNotFound("sym")),
            (.symbol("s1"), .symbolNotFound("s1")),
        ]
        for (owner, error) in cases {
            for command in Self.commands(owner, layer: "wing") {
                var e = CommandEngine(document: start)
                #expect(throws: error, "\(command.label) on \(owner)") { try e.perform(command) }
                #expect(e.document == start)
                #expect(!e.canUndo)
            }
        }
    }

    @Test func missingLayerInSymbolThrows() {
        let sym = LayerOwner.symbol("sym")
        // "ball" exists in the scene but not in the symbol.
        let commands: [any Command] = [
            RenameLayer(owner: sym, layerID: "ball", name: "x"),
            ReorderLayer(owner: sym, layerID: "ball", toIndex: 0),
            SetLayerFlags(owner: sym, layerID: "ball", isLocked: true),
            RemoveLayer(owner: sym, layerID: "ball"),
        ]
        for command in commands {
            var e = CommandEngine(document: Fixtures.withSymbol())
            #expect(throws: CommandError.layerNotFound("ball"), "\(command.label)") { try e.perform(command) }
            #expect(e.document == Fixtures.withSymbol())
        }
    }

    @Test(arguments: [Int.min, -1, 0, 1, 2, 3, Int.max])
    func addLayerClampsAnyIndexIntoASymbol(_ index: Int) throws {
        let start = Fixtures.withSymbol()
        var e = CommandEngine(document: start)
        try e.perform(AddLayer(owner: .symbol("sym"), layer: Layer(id: "fin", name: "Fin"), index: index))
        let ids = try #require(e.document.layers(of: .symbol("sym"))).map(\.id)
        let at = min(max(index, 0), 2)
        var expected = ["wing", "tail"]
        expected.insert("fin", at: at)
        #expect(ids == expected)
        try e.undo()
        #expect(e.document == start)
    }

    @Test func addLayerIntoAnEmptySymbolAndRemoveEveryLayer() throws {
        var start = Fixtures.withSymbol()
        start.symbols.append(Symbol(id: "empty", name: "Empty"))
        var e = CommandEngine(document: start)
        try e.perform(AddLayer(owner: .symbol("empty"), layer: Layer(id: "a", name: "A"), index: 5))
        #expect(e.document.layers(of: .symbol("empty"))?.map(\.id) == ["a"])
        try e.perform(RemoveLayer(owner: .symbol("sym"), layerID: "tail"))
        try e.perform(RemoveLayer(owner: .symbol("sym"), layerID: "wing"))
        #expect(e.document.layers(of: .symbol("sym")) == [])
        #expect(throws: CommandError.layerNotFound("wing")) {
            try e.perform(RemoveLayer(owner: .symbol("sym"), layerID: "wing"))
        }
        #expect(throws: CommandError.layerNotFound("wing")) {
            try e.perform(ReorderLayer(owner: .symbol("sym"), layerID: "wing", toIndex: 0))
        }
        for _ in 0..<3 { try e.undo() }
        #expect(e.document == start)
    }

    @Test(arguments: [Int.min, -1, 2, 3, Int.max])
    func reorderOutOfRangeInASymbolThrows(_ to: Int) {
        var e = CommandEngine(document: Fixtures.withSymbol())
        #expect(throws: CommandError.invalidIndex(to)) {
            try e.perform(ReorderLayer(owner: .symbol("sym"), layerID: "wing", toIndex: to))
        }
        #expect(e.document == Fixtures.withSymbol())
    }

    @Test func reorderToTheSameIndexIsAnExactNoOp() throws {
        var e = CommandEngine(document: Fixtures.withSymbol())
        try e.perform(ReorderLayer(owner: .symbol("sym"), layerID: "tail", toIndex: 1))
        #expect(e.document == Fixtures.withSymbol())
        try e.undo()
        #expect(e.document == Fixtures.withSymbol())
    }

    @Test func addLayerRejectsInvalidContentInASymbol() {
        var start = Fixtures.withSymbol()
        // "outer" holds an instance of "sym", so "sym" may not hold one of "outer".
        start.symbols.append(Symbol(id: "outer", name: "Outer", layers: [
            Layer(id: "o", name: "O", instances: [Instance(symbolID: "sym")]),
        ]))
        let bad: [Layer] = [
            Layer(id: "nan", name: "N", tracks: ["x": [Keyframe(frame: 0, value: .nan)]]),
            Layer(id: "inf", name: "I", tracks: ["x": [Keyframe(frame: 0, value: .infinity)]]),
            Layer(id: "empty", name: "E", tracks: ["x": []]),
            Layer(id: "unsorted", name: "U", tracks: ["x": [Keyframe(frame: 5, value: 0), Keyframe(frame: 1, value: 0)]]),
            Layer(id: "pt", name: "P", shapes: [Shape(points: [Point(x: .nan, y: 0)], fill: .solid(.black))]),
            Layer(id: "self", name: "S", instances: [Instance(symbolID: "sym")]),
            Layer(id: "cycle", name: "C", instances: [Instance(symbolID: "outer")]),
            Layer(id: "ghost", name: "G", instances: [Instance(symbolID: "nope")]),
        ]
        for layer in bad {
            var e = CommandEngine(document: start)
            #expect(throws: CommandError.self, "\(layer.id)") {
                try e.perform(AddLayer(owner: .symbol("sym"), layer: layer))
            }
            #expect(e.document == start, "\(layer.id)")
        }
    }

    @Test func addLayerPastTheLayerLimitOfASymbolThrows() throws {
        var start = Fixtures.withSymbol()
        start.symbols[0].layers = (0..<FlareFormat.maxLayersPerScene).map { Layer(id: "l\($0)", name: "") }
        var e = CommandEngine(document: start)
        #expect(throws: CommandError.self) {
            try e.perform(AddLayer(owner: .symbol("sym"), layer: Layer(id: "over", name: "")))
        }
        #expect(e.document == start)
        // A rename, a reorder and a remove at the limit still work.
        try e.perform(RenameLayer(owner: .symbol("sym"), layerID: "l9999", name: "Last"))
        try e.perform(ReorderLayer(owner: .symbol("sym"), layerID: "l9999", toIndex: 0))
        try e.perform(RemoveLayer(owner: .symbol("sym"), layerID: "l0"))
        for _ in 0..<3 { try e.undo() }
        #expect(e.document == start)
    }

    @Test func oddNamesAndIDsRoundTripThroughSymbolEnvelopes() throws {
        let huge = String(repeating: "é🙂\u{0}", count: 5_000)
        var start = Fixtures.withSymbol()
        start.symbols[0].id = huge
        let owner = LayerOwner.symbol(huge)
        let commands: [any Command] = [
            AddLayer(owner: owner, layer: Layer(id: huge, name: huge), index: Int.max),
            RenameLayer(owner: owner, layerID: huge, name: ""),
            ReorderLayer(owner: owner, layerID: huge, toIndex: 0),
            SetLayerFlags(owner: owner, layerID: huge),
            RemoveLayer(owner: owner, layerID: huge),
        ]
        var e = CommandEngine(document: start)
        for command in commands {
            let data = try Self.registry.encode(command)
            let decoded = try Self.registry.decode(data)
            #expect((decoded as? any LayerCommand)?.owner == owner)
            #expect(try Self.registry.encode(decoded) == data)
            try e.perform(decoded)
        }
        for _ in commands { try e.undo() }
        #expect(e.document == start)
    }

    @Test(arguments: [
        #"{"id":"layer.add","params":{"index":1,"layer":{"id":"fin","name":"Fin","shapes":[],"tracks":{}},"symbolID":"sym"}}"#,
        #"{"id":"layer.remove","params":{"layerID":"wing","symbolID":"sym"}}"#,
        #"{"id":"layer.rename","params":{"layerID":"wing","name":"Fin","symbolID":"sym"}}"#,
        #"{"id":"layer.reorder","params":{"layerID":"wing","symbolID":"sym","toIndex":1}}"#,
        #"{"id":"layer.setFlags","params":{"isVisible":false,"layerID":"wing","symbolID":"sym"}}"#,
    ])
    func handWrittenSymbolEnvelopesDecodeAndPerform(_ json: String) throws {
        let decoded = try Self.registry.decode(Data(json.utf8))
        #expect((decoded as? any LayerCommand)?.owner == .symbol("sym"))
        var e = CommandEngine(document: Fixtures.withSymbol())
        try e.perform(decoded)
        #expect(e.document.scenes == Fixtures.withSymbol().scenes)
        #expect(e.document != Fixtures.withSymbol())
        try e.undo()
        #expect(e.document == Fixtures.withSymbol())
    }

    @Test(arguments: [
        #"{"id":"layer.add","params":{"layer":{"id":"fin","name":"Fin","shapes":[],"tracks":{}}}}"#,
        #"{"id":"layer.add","params":{"layer":{"id":"fin","name":"Fin","shapes":[],"tracks":{}},"sceneID":"s1","symbolID":"sym"}}"#,
        #"{"id":"layer.add","params":{"layer":{"id":"fin","name":"Fin","shapes":[],"tracks":{}},"symbolID":"sym","index":1e30}}"#,
        #"{"id":"layer.add","params":{"layer":{"id":"fin","name":"Fin","shapes":[],"tracks":{}},"symbolID":"sym","index":1.5}}"#,
        #"{"id":"layer.add","params":{"layer":null,"symbolID":"sym"}}"#,
        #"{"id":"layer.rename","params":{"layerID":"wing","symbolID":"sym"}}"#,
        #"{"id":"layer.rename","params":{"layerID":"wing","name":null,"symbolID":"sym"}}"#,
        #"{"id":"layer.reorder","params":{"layerID":"wing","symbolID":"sym","toIndex":"1"}}"#,
        #"{"id":"layer.reorder","params":{"layerID":"wing","symbolID":"sym","toIndex":9223372036854775808}}"#,
        #"{"id":"layer.setFlags","params":{"layerID":"wing","symbolID":"sym","isLocked":"yes"}}"#,
        #"{"id":"layer.remove","params":{"layerID":7,"symbolID":"sym"}}"#,
        #"{"id":"layer.remove","params":{"layerID":"wing","symbolID":["sym"]}}"#,
    ])
    func malformedSymbolEnvelopesThrow(_ json: String) {
        #expect(throws: CommandError.self) { try Self.registry.decode(Data(json.utf8)) }
    }

    @Test func fuzzedSymbolEnvelopesThrowInsteadOfCrashing() {
        var rng = SplitMix64(seed: 0x5B_0177)
        let ids = ["layer.add", "layer.remove", "layer.rename", "layer.reorder", "layer.setFlags"]
        let pieces = [#"""#, ":", ",", "{", "}", "[", "]", "symbolID", "sceneID", "layerID", "toIndex", "index",
                      "layer", "name", "isLocked", "sym", "wing", "null", "-1", "1e999", "true", "9223372036854775807"]
        for _ in 0..<3_000 {
            var params = "{"
            for _ in 0..<Int.random(in: 0...16, using: &rng) {
                params += pieces[Int.random(in: 0..<pieces.count, using: &rng)]
            }
            let id = ids[Int.random(in: 0..<ids.count, using: &rng)]
            let json = #"{"id":"\#(id)","params":\#(params)}"#
            guard let command = try? Self.registry.decode(Data(json.utf8)) else { continue }
            // Whatever decodes must perform or throw on a real document, never crash.
            var e = CommandEngine(document: Fixtures.withSymbol())
            if (try? e.perform(command)) != nil {
                #expect((try? FlareFormat.validate(e.document)) != nil, "\(json)")
                #expect((try? e.undo()) != nil)
                #expect(e.document == Fixtures.withSymbol(), "\(json)")
            }
        }
    }

    /// A seeded run of layer list commands against scene, symbol, shared-id and
    /// missing owners with extreme indices. Every accepted step leaves a document
    /// the full validator accepts, and undo-all gives back the start.
    @Test(arguments: [UInt64(1), 2, 3, 0xC0FFEE])
    func mixedOwnerFuzzKeepsTheDocumentValidAndUndoable(_ seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var start = Fixtures.withSymbol()
        start.symbols.append(Symbol(id: "s1", name: "Twin", layers: [Layer(id: "ball", name: "TwinBall")]))
        let owners: [LayerOwner] = [.scene("s1"), .symbol("sym"), .symbol("s1"), .symbol("ghost"), .scene("sym")]
        let indices = [Int.min, -1, 0, 1, 2, 5, Int.max]
        var e = CommandEngine(document: start)
        var performed = 0
        var next = 0
        for _ in 0..<300 {
            let owner = owners[Int.random(in: 0..<owners.count, using: &rng)]
            let existing = e.document.layers(of: owner)?.map(\.id) ?? []
            let pool = existing + ["ball", "wing", "missing"]
            let layer = pool[Int.random(in: 0..<pool.count, using: &rng)]
            let index = indices[Int.random(in: 0..<indices.count, using: &rng)]
            let before = e.document
            let command: any Command
            switch Int.random(in: 0..<5, using: &rng) {
            case 0:
                next += 1
                let id = Bool.random(using: &rng) ? "n\(next)" : layer
                command = AddLayer(owner: owner, layer: Layer(id: id, name: id), index: index)
            case 1: command = RemoveLayer(owner: owner, layerID: layer)
            case 2: command = RenameLayer(owner: owner, layerID: layer, name: "r\(next)")
            case 3: command = ReorderLayer(owner: owner, layerID: layer, toIndex: index)
            default:
                command = SetLayerFlags(owner: owner, layerID: layer,
                                        isVisible: Bool.random(using: &rng), isLocked: Bool.random(using: &rng))
            }
            do {
                try e.perform(command)
                performed += 1
                try FlareFormat.validate(e.document)
                // Only the addressed owner's list may change.
                for other in owners where other != owner {
                    #expect(e.document.layers(of: other) == before.layers(of: other), "\(command.label) on \(owner)")
                }
            } catch is CommandError {
                #expect(e.document == before)
            }
        }
        #expect(performed > 50)
        while e.canUndo { try e.undo() }
        #expect(e.document == start)
    }
}
