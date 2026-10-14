// ScaleKeyframeOverflowTests.swift: a scaleX/scaleY keyframe whose Lottie
// value (value × 100, a percent) overflows (#208). Such a layer used to
// validate, save and export to SVG, while Lottie export threw EncodingError.
// Validation now rejects it, so every scale that validates exports to Lottie.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import FlareCore

@Suite struct ScaleKeyframeOverflowTests {
    /// The smallest scale whose × 100 overflows: the first step above
    /// greatestFiniteMagnitude / 100 that rounds to infinity.
    static let firstOverflow: Double = {
        var v = Double.greatestFiniteMagnitude / 100
        for _ in 0..<64 where (v * 100).isFinite { v = v.nextUp }
        return v
    }()

    static func doc(_ property: String, _ value: Double) -> Document {
        var d = Fixtures.document()
        d.scenes[0].layers[1].tracks[property] = [Keyframe(frame: 0, value: value)]
        return d
    }

    /// Just enough of the Lottie document to read each layer's scale.
    struct Lottie: Decodable {
        struct Layer: Decodable { let ks: Transform }
        struct Transform: Decodable { let s: Value }
        struct Value: Decodable { let k: [Double] }
        let layers: [Layer]
    }

    /// The issue's repro: SetKeyframe with scaleX 1e307 is refused and
    /// leaves the document as it was.
    @Test func issueReproIsRejected() throws {
        let original = Fixtures.document()
        var e = CommandEngine(document: original)
        #expect(throws: CommandError.self) {
            try e.perform(SetKeyframe(owner: .scene("s1"), layerID: "ball", property: "scaleX",
                                      keyframe: Keyframe(frame: 0, value: 1e307)))
        }
        #expect(e.document == original)
    }

    /// Both sides of the boundary, both axes, both signs: the first value whose
    /// × 100 overflows is rejected, the one below it validates and exports to
    /// Lottie with exactly value × 100.
    @Test(arguments: ["scaleX", "scaleY"], [1.0, -1.0])
    func boundary(property: String, sign: Double) throws {
        let over = sign * Self.firstOverflow
        let under = sign * Self.firstOverflow.nextDown
        #expect(!(over * 100).isFinite)
        #expect(throws: FormatError.invalid("layer ball: track \(property) value × 100 overflows at frame 0")) {
            try FlareFormat.validate(Self.doc(property, over))
        }
        try FlareFormat.validate(Self.doc(property, under))
        let data = try LottieExporter.export(scene: Self.doc(property, under).scenes[0])
        let lottie = try JSONDecoder().decode(Lottie.self, from: data)
        let scale = try #require(lottie.layers.first { $0.ks.s.k != [100, 100] }?.ks.s.k)
        #expect(scale == (property == "scaleX" ? [under * 100, 100] : [100, under * 100]))
    }

    /// A saved file holding the overflowing scale is refused on load.
    @Test func loadRejectsOverflowingScale() throws {
        let json = String(decoding: try FlareFormat.encode(Self.doc("scaleY", 1234.5)), as: UTF8.self)
        let bad = json.replacing("1234.5", with: "1e307")
        #expect(bad != json)
        #expect(throws: FormatError.invalid("layer ball: track scaleY value × 100 overflows at frame 0")) {
            _ = try FlareFormat.decode(Data(bad.utf8))
        }
    }

    /// The check covers symbol layers too, and only the scale tracks: an x of
    /// 1e307 is still a valid position.
    @Test func symbolLayersAndOtherTracks() throws {
        var d = Fixtures.withSymbol()
        d.symbols[0].layers[0].tracks["scaleX"] = [Keyframe(frame: 0, value: -1e307)]
        #expect(throws: FormatError.invalid("layer wing: track scaleX value × 100 overflows at frame 0")) {
            try FlareFormat.validate(d)
        }
        try FlareFormat.validate(Self.doc("x", 1e307))
    }
}
