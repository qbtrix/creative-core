// LottieTrackExportTests.swift: Lottie writes Fixtures/tracks.flare's fill, stroke, width and path keys (AP-7)
// with `t`, `s` and `o`/`i`, hold as `h: 1`, colours in 0...1, relative tangents, and stable bytes.
import FlareCore
import Foundation
import Testing

@Suite struct LottieTrackExportTests {
    /// The keys of animated property `property` (`a` is 1) on the shape group's item of type `type`.
    static func keys(_ type: String, _ property: String, scene: Scene? = nil) throws -> [[String: Any]] {
        let scene = try scene ?? TrackCommandsTests.fixtureScene()
        let json = try #require(try JSONSerialization.jsonObject(with: LottieExporter.export(scene: scene)) as? [String: Any])
        let group = try #require(((json["layers"] as? [[String: Any]])?.first?["shapes"] as? [[String: Any]])?.first)
        let item = try #require((group["it"] as? [[String: Any]])?.first { $0["ty"] as? String == type })
        let animated = try #require(item[property] as? [String: Any])
        #expect(animated["a"] as? Int == 1)
        return try #require(animated["k"] as? [[String: Any]])
    }

    /// The fixture's exported JSON text after `edit` changes its only layer.
    static func text(_ edit: (inout Layer) -> Void) throws -> String {
        var scene = try TrackCommandsTests.fixtureScene()
        edit(&scene.layers[0])
        return try #require(String(data: try LottieExporter.export(scene: scene), encoding: .utf8))
    }

    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 40, y: 0), Point(x: 40, y: 40), Point(x: 0, y: 40)], closed: true)

    @Test func fillColourKeys() throws {
        let keys = try Self.keys("fl", "c")
        #expect(keys.map { $0["t"] as? Int } == [0, 24] && keys.map { $0["s"] as? [Double] } == [[1, 0, 0, 1], [0, 0, 1, 1]])
        let o = try #require(keys[0]["o"] as? [String: Any]), i = try #require(keys[0]["i"] as? [String: Any])
        #expect(o["x"] as? [Double] == [0.42] && o["y"] as? [Double] == [0] && i["x"] as? [Double] == [0.58] && i["y"] as? [Double] == [1])
    }

    @Test func colourUnitRange() throws {
        let values = try (Self.keys("fl", "c") + Self.keys("st", "c")).flatMap { $0["s"] as? [Double] ?? [] }
        #expect(values.count == 16 && values.allSatisfy { (0...1).contains($0) })
    }

    @Test func strokeHoldAndWidth() throws {
        let (colour, width) = (try Self.keys("st", "c"), try Self.keys("st", "w"))
        #expect(colour.map { $0["s"] as? [Double] } == [[0, 0, 0, 1], [1, 1, 1, 1]] && colour[0]["h"] as? Int == 1 && colour[0]["o"] == nil)
        #expect(width.map { $0["t"] as? Int } == [0, 24] && width.map { $0["s"] as? [Double] } == [[2], [8]])
    }

    @Test func tangentsRelative() throws {
        let keys = try Self.keys("sh", "ks")
        let first = try #require((keys.first?["s"] as? [[String: Any]])?.first)
        #expect(first["v"] as? [[Double]] == [[0, 0], [20, 0], [40, 0], [40, 20], [40, 40], [20, 40], [0, 40], [0, 20]])
        // Straight sides: each tangent is the zero offset from its vertex, not the vertex itself.
        #expect(first["i"] as? [[Double]] == Array(repeating: [0, 0], count: 8) && first["o"] as? [[Double]] == Array(repeating: [0, 0], count: 8))
        #expect(first["c"] as? Bool == true && keys.map { $0["t"] as? Int } == [0, 24])
        // A curve's handles are written as offsets from the vertex they belong to.
        var scene = try TrackCommandsTests.fixtureScene()
        let curve = Path(elements: [.move(to: Point(x: 10, y: 10)), .cubic(control1: Point(x: 14, y: 10), control2: Point(x: 30, y: 26), to: Point(x: 30, y: 30)), .close])
        scene.layers[0].shapeTracks = [ShapeTrack(shapeIndex: 0, keys: [PathKeyframe(frame: 0, path: curve), PathKeyframe(frame: 24, path: curve)])]
        let bezier = try #require((try Self.keys("sh", "ks", scene: scene).first?["s"] as? [[String: Any]])?.first)
        #expect(bezier["o"] as? [[Double]] == [[4, 0], [0, 0]] && bezier["i"] as? [[Double]] == [[0, 0], [0, -4]])
    }

    @Test func byteStable() throws {
        let scene = try TrackCommandsTests.fixtureScene()
        #expect(try LottieExporter.export(scene: scene) == LottieExporter.export(scene: scene))
    }

    @Test func singleKeysWriteStaticValues() throws {
        let text = try Self.text { layer in
            layer.colorTracks = ["fill.0": [ColorKeyframe(frame: 6, value: Color(r: 0, g: 0, b: 1, a: 0.5))]]
            layer.tracks = ["strokeWidth.0": [Keyframe(frame: 6, value: 3)]]
            layer.shapeTracks = [ShapeTrack(shapeIndex: 0, keys: [PathKeyframe(frame: 6, path: Self.square)])]
        }
        #expect(text.contains(#""c":{"a":0,"k":[0,0,1,1]},"o":{"a":0,"k":50},"r":1,"ty":"fl""#))
        #expect(text.contains(#""w":{"a":0,"k":3}"#) && text.contains(#""v":[[0,0],[40,0],[40,40],[0,40]]"#) && !text.contains(#""a":1"#))
    }

    @Test func unmatchedPathKeysHold() throws {
        var scene = try TrackCommandsTests.fixtureScene()
        scene.layers[0].shapeTracks[0].keys[1].path = Self.square
        let keys = try Self.keys("sh", "ks", scene: scene)
        #expect(keys[0]["h"] as? Int == 1 && keys[0]["o"] == nil && keys.count == 2)
    }

    @Test func pathKeysWithDifferentPartCountsThrow() throws {
        var scene = try TrackCommandsTests.fixtureScene()
        scene.layers[0].shapeTracks[0].keys[1].path = Path(elements: Self.square.elements + Self.square.elements)
        #expect(throws: LottieExportError.unsupported("shape track")) { try LottieExporter.export(scene: scene) }
    }

    @Test func keyedFillPaintsAGradientSolid() throws {
        let text = try Self.text { layer in
            layer.shapes[0].fill = .linear(stops: [GradientStop(offset: 0, color: Color(r: 1, g: 1, b: 1))], start: Point(x: 0, y: 0), end: Point(x: 1, y: 0))
        }
        #expect(!text.contains(#""ty":"gf""#) && text.contains(#""ty":"fl""#))
    }

    @Test func nonFiniteKeysThrow() throws {
        var scene = try TrackCommandsTests.fixtureScene()
        scene.layers[0].colorTracks["stroke.0"]?[1].value.g = .nan
        #expect(throws: LottieExportError.nonFiniteValue) { try LottieExporter.export(scene: scene) }
    }

    @Test func symbolLayersWriteTheirFrame() throws {
        let inner = try #require(try TrackCommandsTests.fixtureScene().layers.first)
        let host = Layer(id: "host", name: "Host", instances: [Instance(symbolID: "sym", firstFrame: 12, loop: .singleFrame)])
        let scene = Scene(id: "s", name: "S", layers: [host])
        let data = try LottieExporter.export(scene: scene, symbols: [Symbol(id: "sym", name: "Sym", durationFrames: 24, layers: [inner])])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(#""w":{"a":0,"k":5}"#) && !text.contains(#""a":1"#))
    }
}
