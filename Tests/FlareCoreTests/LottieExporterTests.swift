import Foundation
import Testing
@testable import FlareCore

struct LottieExporterTests {
    private func object(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fixtureScene() throws -> Scene {
        try #require(Fixtures.document().scenes.first)
    }

    @Test func fixtureTopLevelAndLayers() throws {
        let json = try object(LottieExporter.export(scene: fixtureScene()))
        #expect(json["v"] as? String == LottieExporter.version)
        #expect(json["fr"] as? Int == 24)
        #expect(json["ip"] as? Int == 0)
        #expect(json["op"] as? Int == 48)
        #expect(json["w"] as? Double == 550)
        #expect(json["h"] as? Double == 400)
        let layers = try #require(json["layers"] as? [[String: Any]])
        #expect(layers.count == 2)
        // Lottie's first layer is the top one: the ball, drawn last in Flare.
        #expect(layers.map { $0["nm"] as? String } == ["Ball", "Background"])
        #expect(layers.allSatisfy { $0["ty"] as? Int == 4 })
        let ball = try #require(layers.first)
        let groups = try #require(ball["shapes"] as? [[String: Any]])
        #expect(groups.count == 1)
        let items = try #require(groups.first?["it"] as? [[String: Any]])
        #expect(items.map { $0["ty"] as? String } == ["sh", "fl", "tr"])
        let fill = try #require(items[1]["c"] as? [String: Any])
        #expect(fill["k"] as? [Double] == [1, 0.5, 0.25, 1])
        let path = try #require((items[0]["ks"] as? [String: Any])?["k"] as? [String: Any])
        #expect(path["c"] as? Bool == true)
        #expect(path["v"] as? [[Double]] == [[0, 0], [10, 0], [10, 10], [0, 10]])
    }

    @Test func exportIsByteStableWithSortedKeys() throws {
        let scene = try fixtureScene()
        let first = try LottieExporter.export(scene: scene)
        #expect(first == (try LottieExporter.export(scene: scene)))
        let text = try #require(String(data: first, encoding: .utf8))
        #expect(text.hasPrefix("{\"assets\":[],\"ddd\":0,\"fr\":24,\"h\":400,\"ip\":0,\"layers\":["))
    }

    @Test func curvesBecomeRelativeTangents() throws {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .quad(control: Point(x: 3, y: 6), to: Point(x: 6, y: 0)),
            .cubic(control1: Point(x: 7, y: 1), control2: Point(x: 9, y: 2), to: Point(x: 10, y: 0)),
            .move(to: Point(x: 20, y: 20)),
            .line(to: Point(x: 30, y: 20)),
        ])
        let beziers = try LottieExporter.beziers(path)
        #expect(beziers.count == 2)
        let curve = try #require(beziers.first)
        #expect(curve.v == [[0, 0], [6, 0], [10, 0]])
        #expect(curve.o == [[2, 4], [1, 1], [0, 0]])
        #expect(curve.i == [[0, 0], [-2, 4], [-1, 2]])
        #expect(!curve.c)
        #expect(beziers.last?.v == [[20, 20], [30, 20]])
    }

    @Test func transformAndHiddenLayer() throws {
        let layer = Layer(id: "a", name: "A", tracks: [
            "x": [Keyframe(frame: 0, value: 5)], "scaleX": [Keyframe(frame: 0, value: 2)],
            "opacity": [Keyframe(frame: 0, value: 0.5)],
        ], isVisible: false)
        let scene = Scene(id: "s", name: "S", layers: [layer])
        let json = try object(LottieExporter.export(scene: scene))
        let out = try #require((json["layers"] as? [[String: Any]])?.first)
        #expect(out["hd"] as? Bool == true)
        let ks = try #require(out["ks"] as? [String: Any])
        #expect((ks["p"] as? [String: Any])?["k"] as? [Double] == [5, 0])
        #expect((ks["s"] as? [String: Any])?["k"] as? [Double] == [200, 100])
        #expect((ks["o"] as? [String: Any])?["k"] as? Double == 50)
    }

    @Test func nonFiniteThrows() {
        let scene = Scene(id: "s", name: "S", layers: [
            Layer(id: "a", name: "A", shapes: [Shape(points: [Point(x: .nan, y: 0)])]),
        ])
        #expect(throws: LottieExportError.nonFiniteValue) { try LottieExporter.export(scene: scene) }
        var wide = Scene(id: "s", name: "S")
        wide.width = .infinity
        #expect(throws: LottieExportError.nonFiniteValue) { try LottieExporter.export(scene: wide) }
    }
}
