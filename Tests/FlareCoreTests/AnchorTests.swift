// AnchorTests.swift: a layer's anchor point, keyed as `anchorX` and `anchorY` like any transform property, is the
// point rotation and scale turn about: the matrix is T(x, y) · R · S · T(−anchor). An anchor of 0 changes nothing,
// files without one load and save the same bytes, and the render list, SVG and Lottie all use it.
import Foundation
import Testing
@testable import FlareCore

struct AnchorTests {
    /// A 100 × 100 square drawn at 100...200 with its anchor at its centre, placed so it sits where it was drawn,
    /// turned 0 to 360 degrees over 24 frames.
    static func spinner() -> Scene {
        let square = Path(polyline: [Point(x: 100, y: 100), Point(x: 200, y: 100), Point(x: 200, y: 200),
                                     Point(x: 100, y: 200)], closed: true)
        var layer = Layer(id: "spin", name: "Spin", shapes: [Shape(points: [], path: square)])
        layer.tracks = ["anchorX": [Keyframe(frame: 0, value: 150)], "anchorY": [Keyframe(frame: 0, value: 150)],
                        "x": [Keyframe(frame: 0, value: 150)], "y": [Keyframe(frame: 0, value: 150)],
                        "rotation": [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: 360)]]
        return Scene(id: "s", name: "S", layers: [layer])
    }

    @Test func rotationTurnsAboutTheAnchor() throws {
        let scene = Self.spinner()
        for frame in [0.0, 6, 12, 18, 24] {
            let item = try #require(scene.renderList(at: frame, symbols: []).items.first)
            let box = try #require(item.outline.transformed(by: item.matrix).bounds)
            #expect(abs((box.minX + box.maxX) / 2 - 150) < 1e-9 && abs((box.minY + box.maxY) / 2 - 150) < 1e-9, "\(frame)")
        }
        let still = try #require(scene.renderList(at: 0, symbols: []).items.first)
        #expect(still.outline.transformed(by: still.matrix).bounds == Rect(minX: 100, minY: 100, maxX: 200, maxY: 200))
    }

    @Test func theMatrixMovesTheAnchorFirst() {
        let t = Transform(x: 10, y: 20, scaleX: 2, scaleY: 3, rotation: 30, anchorX: 5, anchorY: 7)
        let plain = Transform(x: 10, y: 20, scaleX: 2, scaleY: 3, rotation: 30)
        #expect(t.matrix == plain.matrix * Matrix.translation(x: -5, y: -7))
        let landed = t.matrix.apply(Point(x: 5, y: 7))
        #expect(abs(landed.x - 10) < 1e-9 && abs(landed.y - 20) < 1e-9, "the anchor lands on the position")
        #expect(Transform(x: 1, y: 2).matrix == Matrix.translation(x: 1, y: 2), "no anchor, no extra multiply")
    }

    @Test func layersSampleTheirAnchor() {
        let (t, _) = Self.spinner().layers[0].placement(at: 12)
        #expect(t.anchorX == 150 && t.anchorY == 150 && t.rotation == 180)
        #expect(Layer.standardDefaults["anchorX"] == 0 && Layer.standardDefaults["anchorY"] == 0)
    }

    @Test func aTransformWithoutAnAnchorReadsAndWritesAsBefore() throws {
        let old = Data(#"{"rotation":0,"scaleX":1,"scaleY":1,"x":3,"y":4}"#.utf8)
        let t = try JSONDecoder().decode(Transform.self, from: old)
        #expect(t == Transform(x: 3, y: 4))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(t) == old)
        let anchored = Transform(anchorX: 1.5, anchorY: -2)
        #expect(try JSONDecoder().decode(Transform.self, from: try encoder.encode(anchored)) == anchored)
    }

    @Test func aNonFiniteAnchorIsRefused() throws {
        let host = Layer(id: "h", name: "H", instances: [Instance(symbolID: "sym", transform: Transform(anchorX: .nan))])
        let document = Document(scenes: [Scene(id: "s", name: "S", layers: [host])],
                                symbols: [Symbol(id: "sym", name: "Sym", durationFrames: 1, layers: [])])
        // The check itself refuses it, not just JSON's refusal to write a NaN.
        #expect(throws: FormatError.self) { try FlareFormat.validate(document) }
    }

    @Test func svgWritesTheAnchoredMatrix() throws {
        let svg = try SVGExporter.export(scene: Self.spinner(), frame: 6)
        let t = Self.spinner().layers[0].placement(at: 6).transform
        #expect(svg.contains(try SVGExporter.matrix(t)))
        let centre = t.matrix.apply(Point(x: 150, y: 150))
        #expect(abs(centre.x - 150) < 1e-9 && abs(centre.y - 150) < 1e-9)
    }

    @Test func lottieWritesAStaticAnchorAndRefusesAKeyedOne() throws {
        let data = try LottieExporter.export(scene: Self.spinner())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layer = try #require((json["layers"] as? [[String: Any]])?.first)
        let a = try #require((layer["ks"] as? [String: Any])?["a"] as? [String: Any])
        #expect(a["k"] as? [Double] == [150, 150])
        var keyed = Self.spinner()
        keyed.layers[0].tracks["anchorX"] = [Keyframe(frame: 0, value: 0), Keyframe(frame: 12, value: 150)]
        #expect(throws: LottieExportError.self) { try LottieExporter.export(scene: keyed) }
    }
}
