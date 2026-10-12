// LayerOwnerAdversarialTests.swift: edge cases and fuzz for LayerOwner's flat
// Codable, the owner resolver, and owner-scoped validation: odd JSON, shared
// scene and symbol ids, huge ids, and a seeded check that the scoped
// validator agrees with the full one on random symbol layer edits.
@testable import FlareCore
import Foundation
import Testing

@Suite struct LayerOwnerAdversarialTests {
    private func decode(_ json: String) throws -> LayerOwner {
        try JSONDecoder().decode(LayerOwner.self, from: Data(json.utf8))
    }

    @Test func rejectsNonObjectsAndWrongTypes() {
        for json in [#"[]"#, #"["s1"]"#, #""s1""#, #"null"#, #"3"#, #"{"sceneID":null}"#,
                     #"{"symbolID":null}"#, #"{"sceneID":null,"symbolID":null}"#, #"{"sceneID":["s1"]}"#,
                     #"{"symbolID":{"id":"a"}}"#, #"{"sceneID":true}"#, #"{"sceneID":"s1","symbolID":""}"#,
                     #"{"sceneID":"","symbolID":"a"}"#, #"{"SceneID":"s1"}"#, #"{"sceneId":"s1"}"#] {
            #expect(throws: DecodingError.self, "\(json)") { try decode(json) }
        }
    }

    @Test func ignoresUnknownKeysAndKeepsOddIDs() throws {
        #expect(try decode(#"{"sceneID":"s1","layerID":"x","extra":[1,2]}"#) == .scene("s1"))
        // A null for the other key reads as absent, so one present id still decodes.
        #expect(try decode(#"{"sceneID":null,"symbolID":"a"}"#) == .symbol("a"))
        let huge = String(repeating: "é🙂\u{0}", count: 20_000)
        for owner in [LayerOwner.scene(""), .symbol(""), .scene(huge), .symbol(huge), .scene("symbol x"),
                      .symbol("\"}{\\")] {
            let data = try JSONEncoder().encode(owner)
            #expect(try JSONDecoder().decode(LayerOwner.self, from: data) == owner)
        }
        #expect(LayerOwner.scene("a") != LayerOwner.symbol("a"))
        #expect(Set([LayerOwner.scene("a"), .symbol("a"), .scene("a")]).count == 2)
    }

    @Test func fuzzedBytesThrowInsteadOfCrashing() {
        var rng = SplitMix64(seed: 0x1A7E_0001)
        let pieces = [#"{"#, #"}"#, #"""#, #":"#, ",", "sceneID", "symbolID", "null", "1e999", "[", "]",
                      "\\u0000", "s1", " ", "-", "true", "\u{FFFF}"]
        for _ in 0..<2_000 {
            var json = ""
            for _ in 0..<Int.random(in: 0...24, using: &rng) {
                json += pieces[Int.random(in: 0..<pieces.count, using: &rng)]
            }
            if let owner = try? decode(json) {
                // Whatever decodes must round-trip to the same owner.
                let back = try? JSONDecoder().decode(LayerOwner.self, from: JSONEncoder().encode(owner))
                #expect(back == owner, "\(json)")
            }
        }
    }

    @Test func sceneAndSymbolWithTheSameIDStayApart() throws {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].id = "s1"
        #expect(doc.layers(of: .scene("s1"))?.map(\.id) == ["bg", "ball"])
        #expect(doc.layers(of: .symbol("s1"))?.map(\.id) == ["wing", "tail"])
        try doc.withLayer(.symbol("s1"), layer: "wing") { $0.name = "Fin" }
        #expect(doc.scenes[0].layers.allSatisfy { $0.name != "Fin" })
        #expect(throws: ModelError.layerNotFound("ball")) { try doc.withLayer(.symbol("s1"), layer: "ball") { _ in } }
        #expect(throws: ModelError.layerNotFound("wing")) { try doc.withLayer(.scene("s1"), layer: "wing") { _ in } }
    }

    @Test func resolverOnEmptyListsAndFailedBodiesLeavesTheDocument() {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers = []
        #expect(doc.layers(of: .symbol("sym")) == [])
        #expect(throws: ModelError.layerNotFound("wing")) { try doc.withLayer(.symbol("sym"), layer: "wing") { _ in } }
        var empty = Document(scenes: [])
        #expect(empty.layers(of: .scene("s1")) == nil)
        #expect(throws: ModelError.sceneNotFound("")) { try empty.withLayers(.scene("")) { _ in } }
        #expect(throws: ModelError.symbolNotFound("")) { try empty.withLayers(.symbol("")) { _ in } }
        #expect(empty == Document(scenes: []))
    }

    @Test func scopedValidateCatchesSymbolBreakage() {
        let before = Fixtures.withSymbol()
        let sym = LayerOwner.symbol("sym")
        var appended = before
        appended.symbols[0].layers.append(Layer(id: "wing", name: "Copy"))
        #expect(throws: FormatError.invalid("symbol sym: duplicate layer id wing")) {
            try FlareFormat.validate(appended, layer: "wing", owner: sym, since: before)
        }
        var missing = before
        missing.symbols[0].layers[1].instances = [Instance(symbolID: "ghost")]
        #expect(throws: FormatError.self) { try FlareFormat.validate(missing, layer: "tail", owner: sym, since: before) }
        var nan = before
        nan.symbols[0].layers[0].tracks["x"] = [Keyframe(frame: 0, value: .nan)]
        #expect(throws: FormatError.self) { try FlareFormat.validate(nan, layer: "wing", owner: sym, since: before) }
        var inf = before
        inf.symbols[0].layers[0].shapes = [Shape(points: [Point(x: .infinity, y: 0)], fill: .solid(Color(r: 0, g: 0, b: 0)))]
        #expect(throws: FormatError.self) { try FlareFormat.validate(inf, layer: "wing", owner: sym, since: before) }

        // An indirect cycle: sym -> other already, and the edit makes other -> sym.
        var two = before
        two.symbols.append(Symbol(id: "other", name: "Other", layers: [Layer(id: "o", name: "O")]))
        two.symbols[0].layers[1].instances = [Instance(symbolID: "other")]
        var cycle = two
        cycle.symbols[1].layers[0].instances = [Instance(symbolID: "sym")]
        #expect(throws: FormatError.invalid("symbol cycle sym -> other -> sym")) {
            try FlareFormat.validate(cycle, layer: "o", owner: .symbol("other"), since: two)
        }
    }

    @Test func scopedValidateEnforcesTheLayerLimitOnSymbols() {
        var before = Fixtures.withSymbol()
        before.symbols[0].layers = (0..<FlareFormat.maxLayersPerScene).map { Layer(id: "l\($0)", name: "L") }
        var after = before
        after.symbols[0].layers.append(Layer(id: "extra", name: "E"))
        #expect(throws: FormatError.self) {
            try FlareFormat.validate(after, layer: "extra", owner: .symbol("sym"), since: before)
        }
    }

    @Test func scopedValidateFallsBackWhenTheOwnerIsMissing() {
        let before = Fixtures.withSymbol()
        var bad = before
        bad.scenes[0].layers[0].tracks["y"] = []
        // The owner names nothing, so the full validator runs and sees the scene.
        #expect(throws: FormatError.invalid("layer bg: empty track y")) {
            try FlareFormat.validate(bad, layer: "wing", owner: .symbol("ghost"), since: before)
        }
        #expect(throws: Never.self) {
            try FlareFormat.validate(before, layer: "wing", owner: .scene("sym"), since: before)
        }
    }

    /// Random edits to one symbol layer: the scoped validator throws exactly
    /// when the full validator does.
    @Test func scopedAgreesWithFullOnRandomSymbolEdits() {
        var rng = SplitMix64(seed: 0x1A7E_0002)
        var base = Fixtures.withSymbol()
        base.symbols.append(Symbol(id: "leaf", name: "Leaf", layers: [Layer(id: "v", name: "V")]))
        let ids = ["wing", "tail", "new"]
        for step in 0..<500 {
            var doc = base
            let id = ids[Int.random(in: 0..<ids.count, using: &rng)]
            let i = doc.symbols[0].layers.firstIndex { $0.id == id }
            switch Int.random(in: 0..<7, using: &rng) {
            case 0:
                let at = Int.random(in: 0...doc.symbols[0].layers.count, using: &rng)
                doc.symbols[0].layers.insert(Layer(id: id, name: "N"), at: at)
            case 1: if let i { doc.symbols[0].layers.remove(at: i) }
            case 2: if let i { doc.symbols[0].layers[i].tracks["y"] = [] }
            case 3:
                let v = [Double.nan, .infinity, -.infinity, 1e308, 0][Int.random(in: 0..<5, using: &rng)]
                if let i { doc.symbols[0].layers[i].tracks["y"] = [Keyframe(frame: 0, value: v)] }
            case 4:
                let target = ["sym", "leaf", "ghost", ""][Int.random(in: 0..<4, using: &rng)]
                if let i { doc.symbols[0].layers[i].instances.append(Instance(symbolID: target)) }
            case 5:
                if let i, doc.symbols[0].layers.count > 1 {
                    let layer = doc.symbols[0].layers.remove(at: i)
                    doc.symbols[0].layers.insert(layer, at: Int.random(in: 0...doc.symbols[0].layers.count, using: &rng))
                }
            default: if let i { doc.symbols[0].layers[i].name = "R\(step)" }
            }
            let full = (try? FlareFormat.validate(doc)) != nil
            let scoped = (try? FlareFormat.validate(doc, layer: id, owner: .symbol("sym"), since: base)) != nil
            #expect(full == scoped, "step \(step): full \(full), scoped \(scoped)")
        }
    }
}
