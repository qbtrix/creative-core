// LottieMaskExportTests.swift: MM-8 acceptance for Lottie masksProperties and
// track mattes (tt on the matted layer, td on the source above it), and refusals.
import Foundation
@testable import FlareCore
import Testing

@Suite struct LottieMaskExportTests {
    static func scene() throws -> Scene {
        var scene = try #require(MatteRenderListTests.fixture().scenes.first)
        scene.layers[0].masks[1].feather = 0
        return scene
    }

    static func layers(_ scene: Scene) throws -> [[String: Any]] {
        let json = try JSONSerialization.jsonObject(with: LottieExporter.export(scene: scene)) as? [String: Any]
        return try #require(json?["layers"] as? [[String: Any]])
    }

    @Test func modesMapExactly() throws {
        var scene = try Self.scene()
        let square = MatteRenderListTests.square(10, 90)
        scene.layers[0].masks = [MaskMode.add, .subtract, .intersect, .difference].enumerated().map {
            LayerMask(path: square, mode: $1, opacity: 0.25 * Double($0 + 1), inverted: $0 == 2)
        }
        let card = try #require(Self.layers(scene).last)
        let masks = try #require(card["masksProperties"] as? [[String: Any]])
        #expect(card["hasMask"] as? Bool == true)
        #expect(masks.map { $0["mode"] as? String } == ["a", "s", "i", "f"])
        #expect(masks.map { $0["inv"] as? Bool } == [false, false, true, false])
        #expect(masks.map { ($0["o"] as? [String: Any])?["k"] as? Double } == [25, 50, 75, 100])
        #expect(masks.allSatisfy { ($0["x"] as? [String: Any])?["k"] as? Double == 0 })
        let path = try #require(((masks.first?["pt"] as? [String: Any])?["k"]) as? [String: Any])
        #expect(path["c"] as? Bool == true && path["v"] as? [[Double]] == [[10, 10], [90, 10], [90, 90], [10, 90]])
        #expect(try Self.layers(Self.scene())[1]["masksProperties"] == nil)
    }

    @Test func sourceAboveMatted() throws {
        var scene = try Self.scene()
        var layers = try Self.layers(scene)
        #expect(layers.map { $0["nm"] as? String } == ["Lumen", "Photo", "Card"])
        #expect(layers.map { $0["td"] as? Int } == [1, nil, nil] && layers.map { $0["tt"] as? Int } == [nil, 3, nil])
        #expect(layers.first?["hd"] as? Bool == false)
        // A visible source, or one not directly above, is drawn in place and copied above as the matte.
        scene.layers[2].isVisible = true
        scene.layers[0].matte = TrackMatte(sourceLayerID: "lumen", kind: .alphaInverted)
        layers = try Self.layers(scene)
        #expect(layers.map { $0["nm"] as? String } == ["Lumen", "Lumen", "Photo", "Lumen", "Card"])
        #expect(layers.map { $0["td"] as? Int } == [nil, 1, nil, 1, nil])
        #expect(layers.map { $0["tt"] as? Int } == [nil, nil, 3, nil, 2])
        #expect(layers.map { $0["ind"] as? Int } == [3, 4, 2, 5, 1])
    }

    @Test func refusals() throws {
        var scene = try Self.scene()
        scene.layers[0].masks[1].feather = 8
        #expect(throws: LottieExportError.unsupported("mask feather")) { try LottieExporter.export(scene: scene) }
        scene.layers[0].masks[1].opacity = .nan
        #expect(throws: LottieExportError.nonFiniteValue) { try LottieExporter.export(scene: scene) }
        scene = try Self.scene()
        scene.layers[2].matte = TrackMatte(sourceLayerID: "card")
        #expect(throws: LottieExportError.unsupported("nested matte")) { try LottieExporter.export(scene: scene) }
        let symbol = Symbol(id: "sym", name: "Sym", layers: [try Self.scene().layers[0]])
        scene = Scene(id: "s", name: "S", layers: [Layer(id: "host", name: "Host", instances: [Instance(symbolID: "sym")])])
        #expect(throws: LottieExportError.unsupported("mask in symbol")) {
            try LottieExporter.export(scene: scene, symbols: [symbol])
        }
    }
}
