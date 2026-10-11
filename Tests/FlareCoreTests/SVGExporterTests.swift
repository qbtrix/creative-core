import Testing
@testable import FlareCore

struct SVGExporterTests {
    private func squareScene() -> Scene {
        let square = Shape(points: [
            Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10),
        ], fill: .solid(Color(r: 1, g: 0, b: 0)))
        let layer = Layer(id: "sq", name: "Square", shapes: [square], tracks: [
            "x": [Keyframe(frame: 0, value: 0), Keyframe(frame: 10, value: 100)],
            "y": [Keyframe(frame: 0, value: 20)],
        ])
        return Scene(id: "s", name: "S", width: 200, height: 100,
                     background: Color(r: 0, g: 0, b: 1), layers: [layer])
    }

    @Test func squareMovesBetweenFrames() throws {
        let scene = squareScene()
        #expect(try SVGExporter.export(scene: scene, frame: 0) == """
            <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
            <rect width="200" height="100" fill="#0000ff"/>
            <g id="sq" data-name="Square" transform="matrix(1 0 0 1 0 20)">
            <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#ff0000"/>
            </g>
            </svg>

            """)
        #expect(try SVGExporter.export(scene: scene, frame: 5) == """
            <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
            <rect width="200" height="100" fill="#0000ff"/>
            <g id="sq" data-name="Square" transform="matrix(1 0 0 1 50 20)">
            <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#ff0000"/>
            </g>
            </svg>

            """)
    }

    @Test func layersRenderBottomToTopAndHiddenAreSkipped() throws {
        var scene = squareScene()
        let top = Layer(id: "top", name: "Top", shapes: [Shape(points: [Point(x: 1, y: 1)], fill: .solid(.white))],
                        tracks: ["opacity": [Keyframe(frame: 0, value: 0.5)], "rotation": [Keyframe(frame: 0, value: 90)]])
        let hidden = Layer(id: "h", name: "H", shapes: [Shape(points: [Point(x: 7, y: 7)])], isVisible: false)
        scene.layers += [top, hidden]
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        let lines = svg.split(separator: "\n").map(String.init)
        let bottom = try #require(lines.firstIndex(of: "<path d=\"M0 0 L10 0 L10 10 L0 10 Z\" fill=\"#ff0000\"/>"))
        let above = try #require(lines.firstIndex(of: "<path d=\"M1 1 Z\" fill=\"#ffffff\"/>"))
        #expect(bottom < above)
        #expect(lines.contains("<g id=\"top\" data-name=\"Top\" transform=\"matrix(0 1 -1 0 0 0)\" opacity=\"0.5\">"))
        #expect(!svg.contains("M7 7"))
    }

    @Test func curvesExportAsQuadAndCubic() throws {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .quad(control: Point(x: 5, y: 10), to: Point(x: 10, y: 0)),
            .cubic(control1: Point(x: 12.5, y: 1), control2: Point(x: 0.33333, y: 2), to: Point(x: -3, y: 4)),
            .close,
        ])
        #expect(try SVGExporter.pathData(path) == "M0 0 Q5 10 10 0 C12.5 1 0.3333 2 -3 4 Z")
    }

    @Test func translucentFillAndNumbers() throws {
        #expect(try SVGExporter.fill(Color(r: 0.5, g: 2, b: -1, a: 0.25)) == " fill=\"#80ff00\" fill-opacity=\"0.25\"")
        #expect(try SVGExporter.number(-0.00001) == "0")
        #expect(try SVGExporter.number(1e20) == "100000000000000000000")
    }

    @Test func layerIdAndNameAreEscaped() throws {
        var scene = squareScene()
        scene.layers[0].id = "a'b"
        scene.layers[0].name = "<a & \"b\">"
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(svg.contains("<g id=\"a&apos;b\" data-name=\"&lt;a &amp; &quot;b&quot;&gt;\" transform="))
        #expect(!svg.contains("<a &"))
    }

    @Test func numbersNeverUseExponents() throws {
        #expect(try SVGExporter.number(1e-7) == "0")
        #expect(try SVGExporter.number(0.0001) == "0.0001")
        #expect(try SVGExporter.number(-1.5e300) == "-15" + String(repeating: "0", count: 299))
        #expect(try SVGExporter.number(1.25e15) == "1250000000000000")
        #expect(SVGExporter.plainDecimal("-2.5e-05") == "-0.000025")
        #expect(SVGExporter.plainDecimal("1.5e+1") == "15")
        let path = Path(elements: [.move(to: Point(x: 1e-9, y: 3e22)), .line(to: Point(x: -4e18, y: 0.5))])
        let d = try SVGExporter.pathData(path)
        #expect(!d.contains("e"))
        #expect(d == "M0 30000000000000000000000 L-4000000000000000000 0.5")
    }

    @Test func nonFiniteValuesThrow() {
        var scene = squareScene()
        scene.layers[0].shapes[0].points[0].x = .nan
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.export(scene: scene, frame: 0) }
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.fill(Color(r: .infinity, g: 0, b: 0)) }
        var moved = squareScene()
        moved.layers[0].tracks["x"] = [Keyframe(frame: 0, value: .infinity)]
        #expect(throws: SVGExportError.nonFiniteValue) { try SVGExporter.export(scene: moved, frame: 0) }
    }

    @Test func emptyShapesAreSkipped() throws {
        var scene = squareScene()
        scene.layers[0].shapes = [Shape(points: [])]
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(!svg.contains("<path"))
    }
}
