import Foundation
import Testing
@testable import FlareCore

/// The fixtures under Fixtures/import/, read by path next to this file, and helpers the import suites share.
enum ImportFixture {
    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/import/\(name)"))
    }

    /// The `ImportError` `body` throws; nil when it returns or throws something else.
    static func error(_ body: () throws -> Void) -> ImportError? {
        do { try body() } catch let e as ImportError { return e } catch { return nil }
        return nil
    }

    /// The case name of the `ImportError` `body` throws, without its message.
    static func kind(_ body: () throws -> Void) -> String? { error(body).map { String(String(describing: $0).prefix { $0 != "(" }) } }

    /// Every point of the layer's shapes, flattened and placed by its frame-0 transform.
    static func points(_ layer: Layer) throws -> [Point] {
        let m = layer.placement(at: 0).transform.matrix
        return try layer.shapes.flatMap { try $0.outline.flattened(tolerance: 1e-4).joined().map(m.apply) }
    }

    static func bounds(_ layer: Layer) throws -> Rect { try #require(Rect(enclosing: points(layer))) }

    static func near(_ layer: Layer, _ xy: [(Double, Double)]) throws -> Bool {
        let a = try points(layer)
        return a.count == xy.count && zip(a, xy).allSatisfy { abs($0.x - $1.0) <= 1e-6 && abs($0.y - $1.1) <= 1e-6 }
    }

    static func near(_ r: Rect, _ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Bool {
        zip([r.minX, r.minY, r.maxX, r.maxY], [minX, minY, maxX, maxY]).allSatisfy { abs($0 - $1) <= 1e-3 }
    }
}

/// The SVG reader (VI-5) over the hand-written fixtures.
struct SVGImportTests {
    static let red = Color(r: 1, g: 0, b: 0), green = Color(r: 0, g: 1, b: 0), blue = Color(r: 0, g: 0, b: 1)

    func scene(_ name: String) throws -> (Scene, ImportReport) { try SVGImport.scene(from: ImportFixture.data(name), name: "Scene 1") }
    func layers(_ name: String) throws -> [Layer] { try scene(name).0.layers }

    @Test func fixturesLoad() throws {
        for name in ["shapes.svg", "groups.svg", "paint.svg", "skipped.svg", "damaged.svg", "shapes.json", "animated.json", "damaged.json"] {
            #expect(try !ImportFixture.data(name).isEmpty, "\(name)")
        }
    }

    @Test func basicShapesAndSize() throws {
        let (scene, report) = try scene("shapes.svg")
        let layers = scene.layers
        #expect(scene.name == "Scene 1" && scene.width == 200 && scene.height == 100 && report.skipped.isEmpty)
        #expect(layers.count == 7 && layers.allSatisfy { $0.shapes.count == 1 })
        #expect(try layers[0].shapes[0].fill == .solid(Self.red) && ImportFixture.near(ImportFixture.bounds(layers[0]), 10, 10, 40, 30))
        #expect(try layers[1].shapes[0].fill == .solid(Self.blue) && ImportFixture.near(ImportFixture.bounds(layers[1]), 90, 40, 110, 60))
        #expect(ImportFixture.near(try ImportFixture.bounds(layers[2]), 130, 40, 170, 60))
        #expect(layers[2].shapes[0].stroke == Stroke(color: .black, width: 3, join: .round, cap: .square))
        #expect(layers[3].shapes[0].stroke == Stroke(color: Self.green, width: 1))
        #expect(try ImportFixture.near(layers[4], [(0, 0), (10, 5), (20, 0)]))
        let sized = try self.scene("skipped.svg").0
        #expect(sized.layers.count == 1 && sized.width == 300 && sized.height == 150)
        let bare = try SVGImport.scene(from: Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8), name: "s").0
        #expect(bare.width == 1000 && bare.height == 1000)
    }

    @Test func fillOpacity() throws { #expect(try layers("shapes.svg")[5].shapes[0].fill == .solid(Color(r: 1, g: 0, b: 0, a: 0.5))) }

    @Test func styleWinsOverAttribute() throws { #expect(try layers("shapes.svg")[6].shapes[0].fill == .solid(Self.blue)) }

    /// translate(100,0) then scale(2) on the child; then rotate, rotate about (50, 50), skewX over a translate;
    /// then a rotated group over a translated child, and translate then skewX in one list, where order matters.
    @Test func groupTransformOrder() throws {
        let layers = try layers("groups.svg")
        #expect(layers.count == 6)
        #expect(try ImportFixture.near(layers[4], [(0, 10), (-10, 10)]) && ImportFixture.near(layers[5], [(10, 10), (20, 10)]))
        #expect(try ImportFixture.near(layers[0], [(120, 0), (140, 0)]) && ImportFixture.near(layers[1], [(0, 10), (0, 20)]))
        #expect(try ImportFixture.near(layers[2], [(50, 60), (50, 70)]) && ImportFixture.near(layers[3], [(15, 10), (25, 20)]))
    }

    /// Gradients inherit stops through href, the clip path is one add mask, and text keeps its font and entity.
    @Test func gradientsClipAndText() throws {
        let layers = try layers("paint.svg")
        let stops = [GradientStop(offset: 0, color: Self.red), GradientStop(offset: 1, color: Self.blue)]
        #expect(layers[0].shapes[0].fill == .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 100, y: 0)))
        #expect(layers[1].shapes[0].fill == .radial(stops: stops, center: Point(x: 60, y: 50), radius: 10))
        let mask = try #require(layers[1].masks.first)
        #expect(layers[1].masks.count == 1 && mask.mode == .add)
        #expect(ImportFixture.near(try #require(Rect(enclosing: mask.path.flattened(tolerance: 1e-4).flatMap { $0 })), 0, 0, 50, 50))
        let text = try #require(layers[2].texts.first)
        #expect(text.string == "Hi & bye" && text.fontFamily == "Serif" && text.fontSize == 12)
        #expect(text.position == Point(x: 10, y: 20) && text.fill == .solid(Self.red))
    }

    @Test func reportValidateAndDamageThrows() throws {
        #expect(try Set(scene("skipped.svg").1.skipped) == ["filter (3)", "pattern (1)", "use (1)"])
        for name in ["shapes.svg", "groups.svg", "paint.svg", "skipped.svg"] {
            #expect(throws: Never.self, "\(name)") { try FlareFormat.validate(Document(scenes: [try scene(name).0])) }
        }
        #expect(ImportFixture.kind { _ = try scene("damaged.svg") } == "damaged")
        #expect(ImportFixture.error { _ = try SVGImport.scene(from: ImportFixture.data("shapes.json"), name: "s") } == .notThisFormat)
    }

    func svg(_ body: String) throws -> (Scene, ImportReport) {
        try SVGImport.scene(from: Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\">\(body)</svg>".utf8), name: "s")
    }

    @Test func missingFillIsBlack() throws { #expect(try svg("<rect width='1' height='1'/>").0.layers[0].shapes[0].fill == .solid(.black)) }

    @Test func fillNoneIsClear() throws {
        #expect(try svg("<rect width='1' height='1' fill='none'/>").0.layers[0].shapes[0].fill == .solid(Color(r: 0, g: 0, b: 0, a: 0)))
    }

    /// rx and ry round the corners apart; one alone sets both, then each clamps to half its side.
    @Test func rectRxRy() throws {
        let shapes = try svg("<rect width='40' height='20' rx='10' ry='5'/><rect width='40' height='20' ry='30'/>").0.layers.map { $0.shapes[0] }
        let corners = shapes.map { $0.path.map { [$0.elements[0], $0.elements[2]].compactMap(\.endPoint) } ?? [] }
        #expect(corners == [[Point(x: 10, y: 0), Point(x: 40, y: 5)], [Point(x: 20, y: 0), Point(x: 40, y: 10)]])
    }

    /// A gradient href loop and a clip-path loop end, each counted; a chain of maxDepth links reads, one more is a cycle.
    @Test func referenceCyclesEnd() throws {
        let loops = """
            <linearGradient id='a' href='#b'><stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></linearGradient>
            <linearGradient id='b' href='#a'/><clipPath id='c' clip-path='url(#d)'><rect width='5' height='5'/></clipPath>
            <clipPath id='d' clip-path='url(#c)'><rect width='9' height='9'/></clipPath><rect width='10' height='10' fill='url(#b)' clip-path='url(#c)'/>
            """
        var result: (Scene, ImportReport)?
        #expect(try ContinuousClock().measure { result = try svg(loops) } < .seconds(1))
        let (scene, report) = try #require(result)
        #expect(report.skipped == ["reference cycle (2)"] && scene.layers[0].masks.map(\.mode) == [.add, .intersect])
        #expect(scene.layers[0].shapes[0].fill == .linear(stops: [GradientStop(offset: 0, color: Self.red), GradientStop(offset: 1, color: Self.blue)],
                                                         start: Point(x: 0, y: 0), end: Point(x: 10, y: 0)))
        func chain(_ n: Int) throws -> [String] {
            let gradients = (0..<n).map { "<linearGradient id='g\($0)'" + ($0 + 1 < n ? " href='#g\($0 + 1)'/>" : "/>") }.joined()
            let clips = (0..<n).map { "<clipPath id='k\($0)'" + ($0 + 1 < n ? " clip-path='url(#k\($0 + 1))'/>" : "/>") }.joined()
            return try svg(gradients + clips + "<rect width='1' height='1' fill='url(#g0)' clip-path='url(#k0)'/>").1.skipped
        }
        #expect(try chain(SVGImport.maxDepth) == [] && chain(SVGImport.maxDepth + 1) == ["reference cycle (2)"])
    }

    @Test func addSceneThenUndoRestores() throws {
        let before = Document(scenes: [Scene(id: "existing", name: "A")])
        var document = before, add = AddScene(scene: try scene("paint.svg").0)
        try add.execute(&document)
        #expect(document.scenes.map(\.id) == ["existing", "scene-1"] && document.scenes[1].layers.count == 3)
        try add.undo(&document)
        #expect(document == before)
    }

    @Test func reportIsSortedAndExact() throws {
        let (scene, report) = try svg("""
            <use/><filter/><g clip-path='url(#x)'><path d='M0 0h1' clip-path='url(#x)' stroke='url(#x)'/></g>
            <text x='1' y='2' transform='rotate(10)'>a <tspan>b</tspan></text><image/><use/>
            """)
        #expect(report.skipped == ["filter (1)", "gradient stroke (1)", "image (1)", "missing reference (2)", "nested clip-path (1)",
                                   "rotated or skewed text (1)", "tspan (1)", "use (2)"])
        #expect(scene.layers.count == 2 && scene.layers[1].texts.map(\.string) == ["a b"])
    }

    @Test func nonFiniteCoordinatesThrowDamaged() {
        for body in ["<path transform='scale(1e300)' d='M1e300 0 L0 0'/>", "<g transform='scale(1e300) scale(1e300)'/>", "<path transform='skewX(90)' d='M0 0 L1 1'/>"] {
            #expect(ImportFixture.kind { _ = try svg(body) } == "damaged", "\(body)")
        }
    }
}
