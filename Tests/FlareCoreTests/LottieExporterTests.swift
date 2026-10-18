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

    @Test func gradientFillsBecomeGF() throws {
        let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]
        let square = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1)]
        let scene = Scene(id: "s", name: "S", layers: [Layer(id: "a", name: "A", shapes: [
            Shape(points: square, fill: .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 4, y: 0))),
            Shape(points: square, fill: .radial(stops: stops, center: Point(x: 2, y: 3), radius: 5)),
        ])])
        let json = try object(LottieExporter.export(scene: scene))
        let groups = try #require((json["layers"] as? [[String: Any]])?.first?["shapes"] as? [[String: Any]])
        // Lottie lists items top first, so the groups run last shape first.
        let fills = try groups.reversed().map { try #require(($0["it"] as? [[String: Any]])?[1]) }
        #expect(fills.map { $0["ty"] as? String } == ["gf", "gf"])
        #expect(fills.map { $0["t"] as? Int } == [1, 2])
        #expect((fills[1]["e"] as? [String: Any])?["k"] as? [Double] == [7, 3])
        let g = try #require(fills[0]["g"] as? [String: Any])
        #expect(g["p"] as? Int == 2)
        #expect((g["k"] as? [String: Any])?["k"] as? [Double] == [0, 0, 0, 0, 1, 1, 1, 1])
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

    private func position(_ data: Data) throws -> [String: Any] {
        let layer = try #require((try object(data)["layers"] as? [[String: Any]])?.first)
        return try #require((layer["ks"] as? [String: Any])?["p"] as? [String: Any])
    }

    @Test func ballEaseInOutBecomesTangents() throws {
        let p = try position(LottieExporter.export(scene: fixtureScene()))
        #expect(p["s"] as? Bool == true)
        let x = try #require(p["x"] as? [String: Any])
        #expect(x["a"] as? Int == 1)
        let keys = try #require(x["k"] as? [[String: Any]])
        #expect(keys.map { $0["t"] as? Int } == [0, 24])
        #expect(keys.map { $0["s"] as? [Double] } == [[0], [100]])
        let o = try #require(keys[0]["o"] as? [String: Any])
        let i = try #require(keys[0]["i"] as? [String: Any])
        #expect(o["x"] as? [Double] == [0.42] && o["y"] as? [Double] == [0])
        #expect(i["x"] as? [Double] == [0.58] && i["y"] as? [Double] == [1])
        #expect(keys[1]["o"] == nil && keys[1]["h"] == nil)
        let y = try #require(p["y"] as? [String: Any])
        #expect(y["a"] as? Int == 0)
        #expect(y["k"] as? Double == 0)
    }

    @Test func holdAndLinearKeyframes() throws {
        let layer = Layer(id: "a", name: "A", tracks: [
            "y": [Keyframe(frame: 0, value: 1, easing: .hold), Keyframe(frame: 5, value: 2),
                  Keyframe(frame: 9, value: 3)],
        ])
        let data = try LottieExporter.export(scene: Scene(id: "s", name: "S", layers: [layer]))
        let keys = try #require((try position(data)["y"] as? [String: Any])?["k"] as? [[String: Any]])
        #expect(keys.count == 3)
        #expect(keys[0]["h"] as? Int == 1)
        #expect(keys[0]["o"] == nil)
        #expect((keys[1]["o"] as? [String: Any])?["x"] as? [Double] == [0])
        #expect((keys[1]["i"] as? [String: Any])?["y"] as? [Double] == [1])
        #expect(data == (try LottieExporter.export(scene: Scene(id: "s", name: "S", layers: [layer]))))
        let bad = Layer(id: "b", name: "B", tracks: [
            "x": [Keyframe(frame: 0, value: .nan), Keyframe(frame: 5, value: 2)],
        ])
        #expect(throws: LottieExportError.nonFiniteValue) {
            try LottieExporter.export(scene: Scene(id: "s", name: "S", layers: [bad]))
        }
    }

    @Test func strokeIsAnStItem() throws {
        var scene = try fixtureScene()
        scene.layers[1].shapes[0].stroke = Stroke(color: Color(r: 1, g: 0, b: 0, a: 0.5), width: 2,
                                                  join: .bevel, cap: .round)
        let layers = try #require(try object(LottieExporter.export(scene: scene))["layers"] as? [[String: Any]])
        let group = try #require((layers[0]["shapes"] as? [[String: Any]])?.first)
        let items = try #require(group["it"] as? [[String: Any]])
        #expect(items.compactMap { $0["ty"] as? String } == ["sh", "st", "fl", "tr"])
        #expect((items[1]["c"] as? [String: Any])?["k"] as? [Double] == [1, 0, 0, 1])
        #expect((items[1]["o"] as? [String: Any])?["k"] as? Double == 50)
        #expect((items[1]["w"] as? [String: Any])?["k"] as? Double == 2)
        #expect(items[1]["lc"] as? Int == 2 && items[1]["lj"] as? Int == 3)
    }

    @Test func instancesBecomeNestedGroups() throws {
        var e = CommandEngine(document: Fixtures.document())
        try e.perform(ConvertToSymbol(sceneID: "s1", layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
        var scene = e.document.scenes[0]
        scene.layers[1].instances[0].transform = Transform(x: 7, y: 8)
        let data = try LottieExporter.export(scene: scene, symbols: e.document.symbols)
        let layers = try #require(try object(data)["layers"] as? [[String: Any]])
        let instance = try #require((layers[0]["shapes"] as? [[String: Any]])?.first)
        #expect(instance["ty"] as? String == "gr")
        let items = try #require(instance["it"] as? [[String: Any]])
        #expect(items.compactMap { $0["ty"] as? String } == ["gr", "tr"])
        #expect((items[1]["p"] as? [String: Any])?["k"] as? [Double] == [7, 8])
        let ball = try #require(items[0]["it"] as? [[String: Any]])
        #expect(ball.compactMap { $0["ty"] as? String } == ["gr", "tr"])
        #expect((ball[0]["it"] as? [[String: Any]])?.first?["ty"] as? String == "sh")
        #expect(throws: LottieExportError.unresolvedSymbol("sym")) {
            try LottieExporter.export(scene: scene)
        }
    }
}
