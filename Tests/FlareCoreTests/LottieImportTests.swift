import Foundation
import Testing
@testable import FlareCore

/// The Lottie reader's shapes, solids, styles and static transform (VI-6).
/// Lottie lists layers and shapes top first; shapes are found by their style, not their index.
struct LottieImportTests {
    static let red = Color(r: 1, g: 0, b: 0), green = Color(r: 0, g: 1, b: 0), blue = Color(r: 0, g: 0, b: 1)

    func scene() throws -> (Scene, ImportReport) {
        let (document, report) = try LottieImport.document(from: ImportFixture.data("shapes.json"))
        #expect(document.scenes.count == 1)
        return (try #require(document.scenes.first), report)
    }

    func layer(_ name: String) throws -> Layer { try #require(try scene().0.layers.first { $0.name == name }) }
    func shape(_ match: (Shape) -> Bool) throws -> Shape { try #require(try layer("top").shapes.first(where: match)) }
    func bounds(_ shape: Shape) throws -> Rect { try #require(Rect(enclosing: shape.outline.flattened(tolerance: 1e-4).flatMap { $0 })) }

    /// Scene timing, the skipped text layer, the solid layer and the top layer's static transform.
    @Test func sceneSolidAndTransform() throws {
        let (scene, report) = try scene()
        #expect(scene.width == 400 && scene.height == 300 && scene.fps == 30 && scene.durationFrames == 60)
        #expect(report.skipped == ["text (1)"])
        let solid = try layer("bottom")
        #expect(solid.shapes.count == 1 && solid.shapes.first?.fill == .solid(Self.green))
        #expect(ImportFixture.near(try ImportFixture.bounds(solid), 0, 0, 400, 300))
        let (t, opacity) = try layer("top").placement(at: 0)
        #expect(t == Transform(x: 100, y: 50, scaleX: 2, scaleY: 0.5, rotation: 30) && opacity == 0.5)
    }

    @Test func bottomToTop() throws { #expect(try scene().0.layers.map(\.name) == ["bottom", "top"]) }

    @Test func tangentsRelativeToVertex() throws {
        #expect(try shape { $0.stroke != nil }.outline.elements == [
            .move(to: Point(x: 0, y: 0)), .cubic(control1: Point(x: 10, y: 20), control2: Point(x: 90, y: 20), to: Point(x: 100, y: 0)),
        ])
    }

    @Test func shapesAndStyles() throws {
        #expect(try shape { $0.stroke != nil }.stroke == Stroke(color: Self.blue, width: 4, join: .bevel, cap: .round))
        #expect(ImportFixture.near(try bounds(shape { $0.fill == .solid(Self.red) && $0.stroke == nil }), 30, 40, 70, 60))
        let stops = [GradientStop(offset: 0, color: Self.red), GradientStop(offset: 1, color: Self.blue)]
        let gradient = Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 100, y: 0))
        #expect(ImportFixture.near(try bounds(shape { $0.fill == gradient }), -10, -10, 10, 10))
        // The document validates; damaged JSON and other formats throw.
        #expect(throws: Never.self) { try FlareFormat.validate(LottieImport.document(from: ImportFixture.data("shapes.json")).0) }
        #expect(ImportFixture.kind { _ = try LottieImport.document(from: ImportFixture.data("damaged.json")) } == "damaged")
        #expect(ImportFixture.error { _ = try LottieImport.document(from: ImportFixture.data("shapes.svg")) } == .notThisFormat)
    }

    func file(_ top: String = "\"fr\":30,\"ip\":0,\"op\":10", layers: String = "") -> Data { Data("{\(top),\"w\":100,\"h\":100,\"layers\":[\(layers)]}".utf8) }

    /// Each vertex is stored as v - a, so the layer places it at R·S·(v - a) + p; keyframed anchors are counted.
    @Test func anchorFolded() throws {
        let line = "{\"ty\":\"gr\",\"it\":[{\"ty\":\"sh\",\"ks\":{\"a\":0,\"k\":{\"v\":[[30,40],[50,40]],\"i\":[[0,0],[0,0]],\"o\":[[0,0],[0,0]]}}},"
            + "{\"ty\":\"fl\",\"c\":{\"a\":0,\"k\":[1,0,0,1]}}]}"
        let ks = "{\"a\":{\"a\":1,\"k\":[{\"t\":0,\"s\":[10,20]}]},\"p\":{\"a\":0,\"k\":[100,50]},\"s\":{\"a\":0,\"k\":[200,50]},\"r\":{\"a\":0,\"k\":90}}"
        let (document, report) = try LottieImport.document(from: file(layers: "{\"ty\":4,\"ks\":\(ks),\"shapes\":[\(line)]}"))
        let layer = try #require(document.scenes.first?.layers.first)
        guard case .move(let v)? = layer.shapes.first?.path?.elements.first else { Issue.record("no move"); return }
        let placed = try layer.placement(at: 0).0.matrix.apply(v)
        #expect(v == Point(x: 20, y: 20) && abs(placed.x - 90) < 1e-9 && abs(placed.y - 90) < 1e-9, "\(v) \(placed)")
        #expect(report.skipped == ["anchor animation (1)"])
    }

    /// A 10 x 10 box under a group `tr` (scale 2, move (10, 10)), then the layer's -a and p; null layers are counted.
    @Test func groupTransform() throws {
        let box = "{\"ty\":\"gr\",\"it\":[{\"ty\":\"rc\",\"p\":{\"a\":0,\"k\":[0,0]},\"s\":{\"a\":0,\"k\":[10,10]}},"
            + "{\"ty\":\"fl\",\"c\":{\"a\":0,\"k\":[1,0,0,1]}},{\"ty\":\"tr\",\"p\":{\"a\":0,\"k\":[10,10]},\"s\":{\"a\":0,\"k\":[200,200]}}]}"
        let layers = "{\"ty\":3,\"ks\":{}},{\"ty\":4,\"nm\":\"a\",\"ks\":{\"a\":{\"a\":0,\"k\":[50,0]},\"p\":{\"a\":0,\"k\":[100,100]}},\"shapes\":[\(box)]}"
        let (document, report) = try LottieImport.document(from: file(layers: layers))
        let layer = try #require(document.scenes.first?.layers.first)
        #expect(ImportFixture.near(try ImportFixture.bounds(layer), 50, 100, 70, 120) && report.skipped == ["null (1)"])
    }

    /// Nested group transforms compose: the outer tr's T(p)·R·S·T(-a), then the inner tr's;
    /// strokes scale by sqrt|det|, gradient ends are placed, and opacities multiply.
    @Test func groupTransformFull() throws {
        let inner = #"{"ty":"gr","it":[{"ty":"rc","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[4,2]}},{"ty":"st","c":{"a":0,"k":[0,0,1,1]},"w":{"a":0,"k":2}},"#
            + #"{"ty":"gf","s":{"a":0,"k":[-2,0]},"e":{"a":0,"k":[2,0]},"t":1,"g":{"p":2,"k":{"a":0,"k":[0,1,0,0,1,0,0,1]}}},"#
            + #"{"ty":"tr","p":{"a":0,"k":[5,0]},"o":{"a":0,"k":50}}]}"#
        let tr = #"{"ty":"tr","a":{"a":0,"k":[10,0]},"p":{"a":0,"k":[50,50]},"r":{"a":0,"k":90},"s":{"a":0,"k":[200,100]},"o":{"a":0,"k":50}}"#
        let (document, _) = try LottieImport.document(from: file(layers: #"{"ty":4,"ks":{},"shapes":[{"ty":"gr","it":["# + inner + "," + tr + "]}]}"))
        let shape = try #require(document.scenes.first?.layers.first?.shapes.first)
        func near(_ a: Point, _ x: Double, _ y: Double) -> Bool { abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9 }
        // Box (-2,-1)...(2,1), +5 in x, -a, scale 2 in x, rotate 90, +p.
        let corners = [(49.0, 36.0), (51, 36), (51, 44), (49, 44)]
        let ends = (shape.path?.elements ?? []).compactMap { e -> Point? in
            switch e { case .move(to: let p), .line(to: let p): p; default: nil }
        }
        #expect(ends.allSatisfy { e in corners.contains { near(e, $0.0, $0.1) } } && corners.allSatisfy { c in ends.contains { near($0, c.0, c.1) } }, "\(ends)")
        #expect(abs((shape.stroke?.width ?? 0) - 2 * 2.0.squareRoot()) < 1e-12 && shape.stroke?.color.a == 0.25)
        guard case .linear(let stops, let start, let end) = shape.fill else { Issue.record("not linear: \(shape.fill)"); return }
        #expect(near(start, 50, 36) && near(end, 50, 44) && stops.map(\.color.a) == [0.25, 0.25], "\(start) \(end) \(stops)")
    }

    /// Each keyed group tr property is counted once; an item without `ty` is named as such.
    @Test func groupAnimationCounted() throws {
        let tr = #"{"ty":"tr","p":{"a":1,"k":[{"t":0,"s":[0,0]},{"t":5,"s":[10,0]}]},"r":{"a":1,"k":[{"t":0,"s":[0]},{"t":5,"s":[90]}]}}"#
        let group = #"{"ty":"gr","it":[{"ty":"rc","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[4,2]}},{"ty":"fl","c":{"a":0,"k":[1,0,0,1]}},{},"# + tr + "]}"
        let (_, report) = try LottieImport.document(from: file(layers: #"{"ty":4,"ks":{},"shapes":["# + group + "]}"))
        #expect(report.skipped == ["group animation (2)", "shape item without a type (1)"])
    }

    /// A group tr's opacity is clamped to 0...1, like a layer's.
    @Test func groupOpacityClamped() throws {
        func alpha(_ o: Int) throws -> Double? {
            let group = #"{"ty":"gr","it":[{"ty":"rc","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[4,2]}},{"ty":"fl","c":{"a":0,"k":[1,0,0,1]}},"#
                + #"{"ty":"tr","o":{"a":0,"k":"# + "\(o)}}]}"
            let (document, _) = try LottieImport.document(from: file(layers: #"{"ty":4,"ks":{},"shapes":["# + group + "]}"))
            guard case .solid(let c)? = document.scenes.first?.layers.first?.shapes.first?.fill else { return nil }
            return c.a
        }
        #expect(try alpha(150) == 1 && alpha(-50) == 0 && alpha(50) == 0.5)
    }

    /// Frame fields round, convert exactly and range-check; each bad field throws `damaged` naming it.
    @Test func frameRanges() throws {
        #expect(try LottieImport.document(from: file("\"fr\":29.97,\"ip\":0,\"op\":10")).0.scenes.first?.fps == 30)
        #expect(ImportFixture.error { _ = try LottieImport.document(from: file("\"fr\":0,\"ip\":0,\"op\":10")) } == .damaged("fr 0.0 is outside 1...240"))
        func failure(_ data: Data) -> String? {
            if case .damaged(let m)? = ImportFixture.error({ _ = try LottieImport.document(from: data) }) { m } else { nil }
        }
        func canvas(_ w: Int, _ h: Int) -> Data { Data("{\"fr\":30,\"ip\":0,\"op\":10,\"w\":\(w),\"h\":\(h),\"layers\":[]}".utf8) }
        func start(_ st: Int) -> Data { file(layers: "{\"ty\":4,\"st\":\(st),\"ks\":{},\"shapes\":[]}") }
        let keyed = "{\"ty\":4,\"ks\":{\"p\":{\"a\":1,\"k\":[{\"t\":1e300,\"s\":[1,2]}]}},\"shapes\":[]}"
        let bad = [("fr", file("\"fr\":241,\"ip\":0,\"op\":10")), ("fr", file("\"fr\":1e19,\"ip\":0,\"op\":10")), ("ip", file("\"fr\":30,\"ip\":-1,\"op\":10")),
                   ("op", file("\"fr\":30,\"ip\":0,\"op\":1000001")), ("op", file("\"fr\":30,\"ip\":0,\"op\":1e300")), ("ip/op", file("\"fr\":30,\"ip\":5,\"op\":1")),
                   ("keyframe t", file(layers: keyed)), ("w", canvas(0, 100)), ("h", canvas(100, -1)), ("st", start(-1_000_001))]
        for (field, data) in bad { #expect(failure(data)?.hasPrefix(field + " ") == true, "\(field): \(failure(data) ?? "no damaged")") }
        let good = [file("\"fr\":1,\"ip\":0,\"op\":10"), file("\"fr\":240,\"ip\":0,\"op\":10"), file("\"fr\":30,\"ip\":0,\"op\":1000000"), start(-30)]
        for data in good { #expect(ImportFixture.kind { _ = try LottieImport.document(from: data) } == nil) }
    }

    /// Exactly `maxDepth` nested groups read; one more, or 10,000, throws `tooLarge` (not the decoder's damaged).
    @Test func depthCapped() throws {
        func kind(_ n: Int) -> String? {
            let box = #"{"ty":"rc","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[4,2]}},{"ty":"fl","c":{"a":0,"k":[1,0,0,1]}}"#
            let layer = "{\"ty\":4,\"ks\":{},\"shapes\":[" + String(repeating: "{\"ty\":\"gr\",\"it\":[", count: n) + box + String(repeating: "]}", count: n) + "]}"
            return ImportFixture.kind { _ = try LottieImport.document(from: file(layers: layer)) }
        }
        let max = LottieImport.maxDepth
        #expect([kind(max), kind(max + 1), kind(max + 3), kind(10_000)] == [nil, "tooLarge", "tooLarge", "tooLarge"])
    }
}
