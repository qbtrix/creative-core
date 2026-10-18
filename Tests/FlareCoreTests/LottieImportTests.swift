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
    @Test(.disabled("waits on VI-6")) func sceneSolidAndTransform() throws {
        let (scene, report) = try scene()
        #expect(scene.width == 400 && scene.height == 300 && scene.fps == 30 && scene.durationFrames == 60)
        #expect(report.skipped.contains { $0.contains("text") && $0.hasSuffix("(1)") })
        let solid = try layer("bottom")
        #expect(solid.shapes.count == 1 && solid.shapes.first?.fill == .solid(Self.green))
        #expect(ImportFixture.near(try ImportFixture.bounds(solid), 0, 0, 400, 300))
        let (t, opacity) = try layer("top").placement(at: 0)
        #expect(t == Transform(x: 100, y: 50, scaleX: 2, scaleY: 0.5, rotation: 30) && opacity == 0.5)
    }

    @Test(.disabled("waits on VI-6")) func bottomToTop() throws { #expect(try scene().0.layers.map(\.name) == ["bottom", "top"]) }

    @Test(.disabled("waits on VI-6")) func tangentsRelativeToVertex() throws {
        #expect(try shape { $0.stroke != nil }.outline.elements == [
            .move(to: Point(x: 0, y: 0)), .cubic(control1: Point(x: 10, y: 20), control2: Point(x: 90, y: 20), to: Point(x: 100, y: 0)),
        ])
    }

    @Test(.disabled("waits on VI-6")) func shapesAndStyles() throws {
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
}
