import Foundation
import Testing
@testable import FlareCore

/// The Lottie reader's keyframes, easings, holds, masks, mattes and colour tracks (VI-7).
struct LottieImportAnimationTests {
    func animated() throws -> (Scene, ImportReport) {
        let (document, report) = try LottieImport.document(from: ImportFixture.data("animated.json"))
        return (try #require(document.scenes.first), report)
    }
    func layer(_ name: String) throws -> Layer { try #require(try animated().0.layers.first { $0.name == name }) }
    func file(_ top: String = "\"fr\":30,\"ip\":0,\"op\":10", layers: String) -> Data { Data("{\(top),\"w\":100,\"h\":100,\"layers\":[\(layers)]}".utf8) }
    func read(_ ks: String, shapes: String = "", extra: String = "") throws -> (Layer, ImportReport) {
        let (document, report) = try LottieImport.document(from: file(layers: "{\"ty\":4,\"ks\":\(ks),\"shapes\":[\(shapes)]\(extra)}"))
        return (try #require(document.scenes.first?.layers.first), report)
    }
    /// One coordinate of the cubic bezier (0, 0), c1, c2, (1, 1) at parameter s.
    static func bezier(_ c1: Double, _ c2: Double, _ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * c1 + 3 * (1 - s) * s * s * c2 + s * s * s }
    /// The eased progress at `u` of handles (0.4, 0) and (0.6, 1), by bisection.
    static func eased(_ u: Double) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<200 { let mid = (lo + hi) / 2; if bezier(0.4, 0.6, mid) < u { lo = mid } else { hi = mid } }
        return bezier(0, 1, (lo + hi) / 2)
    }
    /// The fixture's position keys (0, 0) to (100, 0) over frames 0...24 follow the file's bezier at 10 frames.
    @Test func positionFollowsBezier() throws {
        let ball = try layer("ball")
        for frame in [0, 1, 2.5, 5, 7.5, 10, 12, 15, 19, 23.5] {
            let t = ball.placement(at: frame).transform
            #expect(abs(t.x - 100 * Self.eased(frame / 24)) < 1e-9 && abs(t.y) < 1e-9, "frame \(frame): \(t.x)")
        }
        let (scene, report) = try animated()
        try FlareFormat.validate(Document(scenes: [scene]))
        #expect(report.skipped == [])
    }

    /// `o` is the first handle and `i` the second; (0, 0) and (1, 1) read as linear, bare numbers as one-element lists.
    @Test func easingHandles() throws {
        let keys = try #require(try layer("ball").tracks["x"])
        #expect(keys.map(\.frame) == [0, 24, 48] && keys.first?.easing == .cubicBezier(x1: 0.4, y1: 0, x2: 0.6, y2: 1))
        let p = "{\"p\":{\"a\":1,\"k\":[{\"t\":0,\"s\":[0,0],\"o\":{\"x\":0,\"y\":0},\"i\":{\"x\":1,\"y\":1}},"
            + "{\"t\":4,\"s\":[5,5],\"o\":{\"x\":0.1,\"y\":0.2},\"i\":{\"x\":[0.7],\"y\":[0.9]}},{\"t\":8,\"s\":[9,9]}]}}"
        let (layer, _) = try read(p)
        #expect(layer.tracks["y"]?.map(\.easing) == [.linear, .cubicBezier(x1: 0.1, y1: 0.2, x2: 0.7, y2: 0.9), .linear])
    }

    /// `h: 1` holds the key's value until the next key.
    @Test func holdKeys() throws {
        let ball = try layer("ball")
        #expect(ball.tracks["x"]?.dropFirst().first?.easing == .hold)
        for frame in [24, 30, 40, 47.9] {
            let t = ball.placement(at: frame).transform
            #expect(t.x == 100 && t.y == 0, "frame \(frame)")
        }
        #expect(ball.placement(at: 48).transform.x == 0 && ball.placement(at: 48).transform.y == 100)
    }

    /// The fixture's mask, and modes, inversion, opacity, the anchor fold and unsupported modes.
    @Test func masksImport() throws {
        let mask = try #require(try layer("ball").masks.first)
        #expect(mask.mode == .add && mask.opacity == 1 && !mask.inverted && mask.feather == 0)
        #expect(mask.path.elements == [.move(to: Point(x: 0, y: 0)), .line(to: Point(x: 100, y: 0)), .line(to: Point(x: 100, y: 100)), .line(to: Point(x: 0, y: 0)), .close])
        let pt = "\"pt\":{\"a\":0,\"k\":{\"c\":true,\"v\":[[10,10],[20,10],[20,20]],\"i\":[[0,0],[0,0],[0,0]],\"o\":[[0,0],[0,0],[0,0]]}}"
        let masks = ",\"masksProperties\":[{\"mode\":\"s\",\"inv\":true,\(pt),\"o\":{\"a\":0,\"k\":50}},{\"mode\":\"f\",\(pt)},"
            + "{\"mode\":\"n\",\(pt)},{\"mode\":\"i\",\(pt),\"x\":{\"a\":0,\"k\":3}}]"
        let (layer, report) = try read("{\"a\":{\"a\":0,\"k\":[10,10]}}", extra: masks)
        #expect(layer.masks.map(\.mode) == [.subtract, .difference, .intersect] && layer.masks.first?.inverted == true)
        #expect(layer.masks.first?.opacity == 0.5 && layer.masks.first?.path.elements.first == .move(to: Point(x: 0, y: 0)))
        #expect(report.skipped == ["mask expansion (1)", "mask mode (1)"])
    }

    /// `tt: 3` is a luma matte from the layer above, which stays hidden; other kinds, and `tp` by `ind`.
    @Test func lumaMatte() throws {
        let (scene, _) = try animated()
        let matte = try #require(scene.layers.first { $0.name == "matte" }), ball = try #require(scene.layers.first { $0.name == "ball" })
        #expect(ball.matte == TrackMatte(sourceLayerID: matte.id, kind: .luma) && !matte.isVisible && matte.matte == nil)
        let source = "{\"ty\":4,\"ind\":7,\"nm\":\"src\",\"td\":1,\"ks\":{},\"shapes\":[]}"
        func target(_ tt: Int, _ more: String = "") -> String { "{\"ty\":4,\"nm\":\"t\(tt)\",\"tt\":\(tt)\(more),\"ks\":{},\"shapes\":[]}" }
        let layers = [source, target(1), target(2, ",\"tp\":7"), target(4, ",\"tp\":7"), target(9), target(3, ",\"tp\":99")].joined(separator: ",")
        let (document, report) = try LottieImport.document(from: file(layers: layers))
        let out = try #require(document.scenes.first?.layers), id = try #require(out.first { $0.name == "src" }?.id)
        for (name, kind) in [("t1", MatteKind.alpha), ("t2", .alphaInverted), ("t4", .lumaInverted)] {
            #expect(out.first { $0.name == name }?.matte == TrackMatte(sourceLayerID: id, kind: kind), "\(name)")
        }
        #expect(out.filter { $0.matte == nil }.count == 3 && report.skipped == ["matte (2)"])
    }

    /// A keyed fill `c` becomes the shape's colour track, red to blue with its easing.
    @Test func colorTracks() throws {
        let ball = try layer("ball")
        let keys = try #require(ball.colorTracks[Layer.colorTrackKey(fillOf: 0)])
        #expect(keys == [ColorKeyframe(frame: 0, value: Color(r: 1, g: 0, b: 0), easing: .cubicBezier(x1: 0.5, y1: 0, x2: 0.5, y2: 1)),
                         ColorKeyframe(frame: 48, value: Color(r: 0, g: 0, b: 1))])
        #expect(ball.sampledColor(.fill(shape: 0), at: 24).map { abs($0.r - 0.5) < 1e-9 && abs($0.b - 0.5) < 1e-9 } == true)
    }

    /// A keyed `sh` becomes a shape track and a keyed stroke `w` a width track; split position reads x and y.
    @Test func pathWidthAndSplitPosition() throws {
        let key = { (t: Int, x: Int) in "{\"t\":\(t),\"s\":[{\"v\":[[0,0],[\(x),0]],\"i\":[[0,0],[0,0]],\"o\":[[0,0],[0,0]]}]}" }
        let shapes = "{\"ty\":\"gr\",\"it\":[{\"ty\":\"sh\",\"ks\":{\"a\":1,\"k\":[\(key(0, 10)),\(key(8, 30))]}},"
            + "{\"ty\":\"st\",\"c\":{\"a\":0,\"k\":[0,0,0,1]},\"w\":{\"a\":1,\"k\":[{\"t\":0,\"s\":[1]},{\"t\":8,\"s\":[5]}]}}]}"
        let ks = "{\"a\":{\"a\":0,\"k\":[5,0]},\"p\":{\"s\":true,\"x\":{\"a\":1,\"k\":[{\"t\":0,\"s\":[0]},{\"t\":8,\"s\":[80]}]},\"y\":{\"a\":0,\"k\":7}}}"
        let (layer, report) = try read(ks, shapes: shapes)
        #expect(report.skipped == [])
        let start = PathElement.move(to: Point(x: -5, y: 0))
        #expect(layer.shapeTracks.first?.keys.map(\.path.elements) == [[start, .line(to: Point(x: 5, y: 0))], [start, .line(to: Point(x: 25, y: 0))]])
        #expect(layer.tracks["strokeWidth.0"]?.map(\.value) == [1, 5] && layer.tracks["x"]?.map(\.value) == [0, 80])
        #expect(layer.placement(at: 4).transform.x == 40 && layer.placement(at: 4).transform.y == 7)
    }

    /// Key `t` is layer time, offset by `st`; keys out of order throw; keys outside the scene clamp and are counted.
    @Test func keyTimes() throws {
        let p = { (keys: String) in "{\"p\":{\"a\":1,\"k\":[\(keys)]}}" }
        let (offset, _) = try read(p("{\"t\":0,\"s\":[0,0]},{\"t\":4,\"s\":[4,0]}"), extra: ",\"st\":3")
        #expect(offset.tracks["x"]?.map(\.frame) == [3, 7])
        let (clamped, report) = try read(p("{\"t\":0,\"s\":[0,0]},{\"t\":6,\"s\":[6,0]},{\"t\":20,\"s\":[20,0]},{\"t\":30,\"s\":[30,0]}"))
        #expect(clamped.tracks["x"]?.map(\.frame) == [0, 6, 10] && clamped.tracks["x"]?.last?.value == 20)
        #expect(report.skipped == ["keyframe outside scene (4)"])  // two keys each of x and y
        let backwards = p("{\"t\":5,\"s\":[0,0]},{\"t\":2,\"s\":[1,0]}")
        #expect(ImportFixture.kind { _ = try read(backwards) } == "damaged")
        #expect(ImportFixture.kind { _ = try read(p("{\"t\":0},{\"t\":2,\"s\":[1,0]}")) } == "damaged")
    }
}
