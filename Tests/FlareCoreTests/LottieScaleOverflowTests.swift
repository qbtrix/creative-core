import Foundation
import Testing
@testable import FlareCore

/// Issue #208: a finite scale whose Lottie percent (× 100) overflows throws
/// the typed export error, not a Foundation `EncodingError`.
struct LottieScaleOverflowTests {
    @Test func hugeLayerScaleThrowsNonFiniteValue() throws {
        for property in ["scaleX", "scaleY"] {
            var e = CommandEngine(document: Fixtures.document())
            try e.perform(SetKeyframe(sceneID: "s1", layerID: "ball", property: property,
                                      keyframe: Keyframe(frame: 0, value: 1e307)))
            // Validation, saving and SVG export stay as they are.
            _ = try FlareFormat.encode(e.document)
            _ = try SVGExporter.export(scene: e.document.scenes[0], frame: 0)
            #expect(throws: LottieExportError.nonFiniteValue) {
                try LottieExporter.export(scene: e.document.scenes[0])
            }
        }
    }

    @Test func hugeInstanceScaleThrowsNonFiniteValue() throws {
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(ConvertToSymbol(sceneID: "s1", layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
        var scene = e.document.scenes[0]
        scene.layers[1].instances[0].transform = Transform(scaleY: -1e307)
        #expect(throws: LottieExportError.nonFiniteValue) {
            try LottieExporter.export(scene: scene, symbols: e.document.symbols)
        }
    }

    @Test func largestScaleThatFitsStillExports() throws {
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(SetKeyframe(sceneID: "s1", layerID: "ball", property: "scaleX",
                                  keyframe: Keyframe(frame: 0, value: 1e306)))
        let data = try LottieExporter.export(scene: e.document.scenes[0])
        let layers = try #require(
            (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["layers"] as? [[String: Any]])
        let ball = try #require(layers.first { $0["nm"] as? String == "Ball" })
        let s = (ball["ks"] as? [String: Any])?["s"] as? [String: Any]
        #expect(s?["k"] as? [Double] == [1e306 * 100, 100])
    }
}
