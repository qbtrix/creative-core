// LottieAnchorParentTests.swift: Lottie carries a layer's anchor (`ks.a`) and parent (`parent`, by `ind`) both
// ways. Export writes them; import keeps the anchor as `anchorX`/`anchorY` instead of baking it into the paths,
// links each parent, brings in a null layer a child follows as an empty layer, and drops a link that would close a
// cycle. A rig round-trips with every item where it was.
import Foundation
import Testing
@testable import FlareCore

struct LottieAnchorParentTests {
    static let unit = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    /// A spinning arm anchored at its centre and a hand 50 to its right that follows it.
    static func rig() -> Scene {
        var arm = Layer(id: "arm", name: "Arm", shapes: [Shape(points: [], path: unit)])
        arm.tracks = ["x": [Keyframe(frame: 0, value: 100)], "y": [Keyframe(frame: 0, value: 100)],
                      "anchorX": [Keyframe(frame: 0, value: 5)], "anchorY": [Keyframe(frame: 0, value: 5)],
                      "rotation": [Keyframe(frame: 0, value: 0), Keyframe(frame: 24, value: 90)]]
        var hand = Layer(id: "hand", name: "Hand", shapes: [Shape(points: [], path: unit)])
        hand.tracks = ["x": [Keyframe(frame: 0, value: 50)]]
        hand.parentID = "arm"
        return Scene(id: "s", name: "S", durationFrames: 24, layers: [arm, hand])
    }

    static func json(_ data: Data) throws -> [[String: Any]] {
        try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["layers"] as? [[String: Any]])
    }

    @Test func exportWritesTheParentAndTheAnchor() throws {
        let layers = try Self.json(try LottieExporter.export(scene: Self.rig()))
        let arm = try #require(layers.first { $0["nm"] as? String == "Arm" })
        let hand = try #require(layers.first { $0["nm"] as? String == "Hand" })
        #expect(hand["parent"] as? Int == arm["ind"] as? Int)
        #expect(arm["parent"] == nil)
        #expect(((arm["ks"] as? [String: Any])?["a"] as? [String: Any])?["k"] as? [Double] == [5, 5])
    }

    @Test func aRigRoundTripsWithEveryItemInPlace() throws {
        let scene = Self.rig()
        let back = try #require(try LottieImport.document(from: try LottieExporter.export(scene: scene)).0.scenes.first)
        let hand = try #require(back.layers.first { $0.name == "Hand" })
        let arm = try #require(back.layers.first { $0.name == "Arm" })
        #expect(hand.parentID == arm.id)
        #expect(arm.placement(at: 0).transform.anchorX == 5)
        for frame in [0.0, 12, 24] {
            let want = scene.renderList(at: frame, symbols: []).items.map { $0.outline.transformed(by: $0.matrix).bounds }
            let got = back.renderList(at: frame, symbols: []).items.map { $0.outline.transformed(by: $0.matrix).bounds }
            #expect(got.count == want.count)
            for (g, w) in zip(got, want) {
                let (g, w) = (try #require(g), try #require(w))
                #expect(abs(g.minX - w.minX) < 1e-6 && abs(g.minY - w.minY) < 1e-6 && abs(g.maxX - w.maxX) < 1e-6
                        && abs(g.maxY - w.maxY) < 1e-6, "frame \(frame): \(g) vs \(w)")
            }
        }
    }

    static func file(_ layers: String) -> Data {
        Data("{\"fr\":30,\"ip\":0,\"op\":10,\"w\":200,\"h\":200,\"layers\":[\(layers)]}".utf8)
    }
    static let square = #"{"ty":"gr","it":[{"ty":"rc","p":{"a":0,"k":[50,50]},"s":{"a":0,"k":[20,20]},"r":{"a":0,"k":0}},{"ty":"fl","c":{"a":0,"k":[1,0,0,1]},"o":{"a":0,"k":100}},{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}]}"#

    static func ks(p: [Double], a: [Double] = [0, 0], r: Double = 0) -> String {
        #"{"p":{"a":0,"k":[\#(p[0]),\#(p[1])]},"a":{"a":0,"k":[\#(a[0]),\#(a[1])]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":\#(r)},"o":{"a":0,"k":100}}"#
    }

    @Test func importKeepsTheAnchorInsteadOfBakingIt() throws {
        let data = Self.file(#"{"ty":4,"ind":1,"nm":"Box","ks":\#(Self.ks(p: [100, 100], a: [50, 50], r: 90)),"shapes":[\#(Self.square)]}"#)
        let scene = try #require(try LottieImport.document(from: data).0.scenes.first)
        let layer = try #require(scene.layers.first)
        #expect(layer.placement(at: 0).transform.anchorX == 50 && layer.placement(at: 0).transform.anchorY == 50)
        #expect(layer.shapes.first?.bounds == Rect(minX: 40, minY: 40, maxX: 60, maxY: 60), "the path stays as written")
        let item = try #require(scene.renderList(at: 0, symbols: []).items.first)
        let box = try #require(item.outline.transformed(by: item.matrix).bounds)
        #expect(abs(box.minX - 90) < 1e-9 && abs(box.maxY - 110) < 1e-9, "turned about the anchor, centred on p")
    }

    @Test func aNullAChildFollowsComesInAsAnEmptyLayer() throws {
        let data = Self.file(#"{"ty":4,"ind":2,"parent":1,"nm":"Child","ks":\#(Self.ks(p: [10, 0])),"shapes":[\#(Self.square)]},"#
                             + #"{"ty":3,"ind":1,"nm":"Rig","ks":\#(Self.ks(p: [30, 0]))},"#
                             + #"{"ty":3,"ind":3,"nm":"Unused","ks":\#(Self.ks(p: [0, 0]))}"#)
        let (document, report) = try LottieImport.document(from: data)
        let scene = try #require(document.scenes.first)
        let rig = try #require(scene.layers.first { $0.name == "Rig" })
        #expect(rig.shapes.isEmpty && scene.layers.first { $0.name == "Child" }?.parentID == rig.id)
        #expect(!scene.layers.contains { $0.name == "Unused" } && report.skipped.contains { $0.hasPrefix("null") })
        let item = try #require(scene.renderList(at: 0, symbols: []).items.first)
        #expect(item.outline.transformed(by: item.matrix).bounds?.minX == 80, "40 + 10 + 30")
    }

    @Test func aParentCycleInAFileIsDropped() throws {
        let data = Self.file(#"{"ty":4,"ind":1,"parent":2,"nm":"A","ks":\#(Self.ks(p: [0, 0])),"shapes":[\#(Self.square)]},"#
                             + #"{"ty":4,"ind":2,"parent":1,"nm":"B","ks":\#(Self.ks(p: [0, 0])),"shapes":[\#(Self.square)]}"#)
        let (document, report) = try LottieImport.document(from: data)
        let layers = try #require(document.scenes.first?.layers)
        #expect(layers.filter { $0.parentID != nil }.count == 1)
        #expect(report.skipped.contains { $0.hasPrefix("parent") })
        _ = try FlareFormat.encode(document)
    }
}
