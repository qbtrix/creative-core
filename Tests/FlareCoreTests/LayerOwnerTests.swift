// LayerOwnerTests.swift: LayerOwner resolves a scene's or a symbol's layer
// list, and encodes flat as exactly one of "sceneID" and "symbolID", beside
// the keys of the command that carries it.
@testable import FlareCore
import Foundation
import Testing

/// A minimal owner-carrying command, so the flat encoding is proven through
/// the registry before any built-in command takes an owner.
private struct RenameOwned: Command {
    static let id = "test.renameOwned"
    var label: String { "Rename" }
    var owner: LayerOwner
    var layerID: String
    var name: String

    private enum CodingKeys: String, CodingKey { case layerID, name }

    init(owner: LayerOwner, layerID: String, name: String) {
        self.owner = owner
        self.layerID = layerID
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        owner = try LayerOwner(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layerID = try c.decode(String.self, forKey: .layerID)
        name = try c.decode(String.self, forKey: .name)
    }

    func encode(to encoder: any Encoder) throws {
        try owner.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layerID, forKey: .layerID)
        try c.encode(name, forKey: .name)
    }

    func execute(_ document: inout Document) throws {
        try document.withLayer(owner, layer: layerID) { $0.name = name }
    }

    func undo(_ document: inout Document) throws {}
}

@Suite struct LayerOwnerTests {
    @Test func resolvesSceneAndSymbolLayers() throws {
        var doc = Fixtures.withSymbol()
        #expect(doc.layers(of: .symbol("sym"))?.map(\.id) == ["wing", "tail"])
        #expect(doc.layers(of: .scene("s1"))?.map(\.id) == ["bg", "ball"])
        #expect(doc.layers(of: .symbol("ghost")) == nil)
        #expect(doc.layers(of: .scene("sym")) == nil)

        try doc.withLayer(.symbol("sym"), layer: "tail") { $0.name = "Fin" }
        #expect(doc.symbols[0].layers[1].name == "Fin")
        let count = try doc.withLayers(.scene("s1")) { layers in
            layers.removeFirst()
            return layers.count
        }
        #expect(count == 1)
        #expect(doc.scenes[0].layers.map(\.id) == ["ball"])
    }

    @Test func missingOwnerOrLayerThrowsModelError() {
        var doc = Fixtures.withSymbol()
        let before = doc
        #expect(throws: ModelError.symbolNotFound("ghost")) { try doc.withLayer(.symbol("ghost"), layer: "wing") { _ in } }
        #expect(throws: ModelError.sceneNotFound("sym")) { try doc.withLayers(.scene("sym")) { _ in } }
        #expect(throws: ModelError.layerNotFound("ball")) { try doc.withLayer(.symbol("sym"), layer: "ball") { _ in } }
        doc.symbols[0].layers[0].isLocked = true
        #expect(throws: ModelError.layerLocked("wing")) {
            try doc.withEditableLayer(.symbol("sym"), layer: "wing") { $0.name = "X" }
        }
        doc.symbols[0].layers[0].isLocked = false
        #expect(doc == before)
    }

    @Test func decodesExactlyOneKey() throws {
        let decode = { (json: String) in try JSONDecoder().decode(LayerOwner.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"sceneID":"s1"}"#) == .scene("s1"))
        #expect(try decode(#"{"symbolID":"a"}"#) == .symbol("a"))
        #expect(throws: DecodingError.self) { try decode(#"{"sceneID":"s1","symbolID":"a"}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"sceneID":3}"#) }
        #expect(LayerOwner.scene("s1").description == "scene s1")
        #expect(LayerOwner.symbol("sym").description == "symbol sym")
    }

    @Test func encodesFlatBesideCommandKeysThroughTheRegistry() throws {
        var registry = CommandRegistry()
        registry.register(RenameOwned.self)
        let data = try registry.encode(RenameOwned(owner: .symbol("sym"), layerID: "wing", name: "Fin"))
        #expect(String(decoding: data, as: UTF8.self)
            == #"{"id":"test.renameOwned","params":{"layerID":"wing","name":"Fin","symbolID":"sym"}}"#)
        let back = try #require(try registry.decode(data) as? RenameOwned)
        #expect(back.owner == .symbol("sym"))
        #expect(back.layerID == "wing")
        #expect(back.name == "Fin")

        let scene = #"{"id":"test.renameOwned","params":{"layerID":"ball","name":"P","sceneID":"s1"}}"#
        #expect(try registry.encode(registry.decode(Data(scene.utf8))) == Data(scene.utf8))

        var engine = CommandEngine(document: Fixtures.withSymbol())
        try engine.perform(back)
        #expect(engine.document.symbols[0].layers[0].name == "Fin")

        let both = #"{"id":"test.renameOwned","params":{"layerID":"x","name":"n","sceneID":"s1","symbolID":"a"}}"#
        let neither = #"{"id":"test.renameOwned","params":{"layerID":"x","name":"n"}}"#
        for json in [both, neither] {
            #expect(throws: CommandError.self) { try registry.decode(Data(json.utf8)) }
        }
    }

    @Test func enginePerformMapsSymbolNotFound() {
        var engine = CommandEngine(document: Fixtures.withSymbol())
        #expect(throws: CommandError.symbolNotFound("ghost")) {
            try engine.perform(RenameOwned(owner: .symbol("ghost"), layerID: "wing", name: "X"))
        }
    }
}
