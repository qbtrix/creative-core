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

    /// Frame fields round, convert exactly and range-check, throwing `damaged` that names the field.
    @Test func frameRanges() throws {
        #expect(try LottieImport.document(from: file("\"fr\":29.97,\"ip\":0,\"op\":10")).0.scenes.first?.fps == 30)
        #expect(ImportFixture.error { _ = try LottieImport.document(from: file("\"fr\":0,\"ip\":0,\"op\":10")) } == .damaged("fr 0.0 is outside 1...240"))
        let keyed = "{\"ty\":4,\"ks\":{\"p\":{\"a\":1,\"k\":[{\"t\":1e300,\"s\":[1,2]}]}},\"shapes\":[]}"
        let bad = [file("\"fr\":241,\"ip\":0,\"op\":10"), file("\"fr\":1e19,\"ip\":0,\"op\":10"), file("\"fr\":30,\"ip\":-1,\"op\":10"),
                   file("\"fr\":30,\"ip\":0,\"op\":1000001"), file("\"fr\":30,\"ip\":0,\"op\":1e300"), file("\"fr\":30,\"ip\":5,\"op\":1"), file(layers: keyed)]
        for data in bad { #expect(ImportFixture.kind { _ = try LottieImport.document(from: data) } == "damaged") }
    }

    /// Groups nest at most `maxDepth` deep; past it, even 10,000 deep, the reader throws.
    @Test func depthCapped() throws {
        func kind(_ n: Int) -> String? {
            let layer = "{\"ty\":4,\"ks\":{},\"shapes\":[" + String(repeating: "{\"ty\":\"gr\",\"it\":[", count: n) + String(repeating: "]}", count: n) + "]}"
            return ImportFixture.kind { _ = try LottieImport.document(from: file(layers: layer)) }
        }
        #expect(kind(200) == nil && kind(300) == "tooLarge" && kind(10_000) == "tooLarge")
    }
}
