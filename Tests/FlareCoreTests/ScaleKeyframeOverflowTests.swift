// ScaleKeyframeOverflowTests.swift: a scaleX or scaleY keyframe that is finite
// but overflows when Lottie export writes it as percent (value × 100) is
// rejected (#208), so a document that validates always exports to Lottie.
@testable import FlareCore
import Testing

@Suite struct ScaleKeyframeOverflowTests {
    static let overflowing: [(String, Double)] = [
        ("scaleX", 1e307), ("scaleY", 1e307), ("scaleX", -1e307), ("scaleY", .greatestFiniteMagnitude),
    ]

    @Test(arguments: overflowing)
    func overflowingScaleKeyframeThrowsAndChangesNothing(_ property: String, _ value: Double) throws {
        var e = CommandEngine(document: Fixtures.document())
        let before = e.document
        #expect(throws: CommandError.invalidDocument(
            "Set Keyframe: invalid(\"layer ball: track \(property) × 100 overflows at frame 0\")")) {
            try e.perform(SetKeyframe(sceneID: Fixtures.sceneID, layerID: "ball", property: property,
                                      keyframe: Keyframe(frame: 0, value: value)))
        }
        #expect(e.document == before)
        #expect(e.undoStack.isEmpty)
    }

    @Test func documentWithOverflowingScaleFailsValidation() {
        var doc = Fixtures.withSymbol()
        doc.symbols[0].layers[1].tracks["scaleY"] = [Keyframe(frame: 3, value: -1e307)]
        #expect(throws: FormatError.invalid("layer tail: track scaleY × 100 overflows at frame 3")) {
            try FlareFormat.validate(doc)
        }
    }

    @Test func otherTracksMayHoldLargeValues() throws {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].tracks["rotation"] = [Keyframe(frame: 0, value: 1e307)]
        try FlareFormat.validate(doc)
    }

    @Test func boundaryScaleValidatesAndExportsToLottie() throws {
        var e = CommandEngine(document: Fixtures.document())
        for property in ["scaleX", "scaleY"] {
            try e.perform(SetKeyframe(sceneID: Fixtures.sceneID, layerID: "ball", property: property,
                                      keyframe: Keyframe(frame: 0, value: 1e306)))
        }
        let decoded = try FlareFormat.decode(FlareFormat.encode(e.document))
        #expect(decoded == e.document)
        let lottie = try LottieExporter.export(scene: e.document.scenes[0])
        #expect(!lottie.isEmpty)
    }

    @Test func overflowingInstanceScaleThrowsTypedError() throws {
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(ConvertToSymbol(sceneID: Fixtures.sceneID, layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
        var scene = e.document.scenes[0]
        scene.layers[1].instances[0].transform = Transform(scaleX: 1e307)
        #expect(throws: LottieExportError.nonFiniteValue) {
            try LottieExporter.export(scene: scene, symbols: e.document.symbols)
        }
    }
}
