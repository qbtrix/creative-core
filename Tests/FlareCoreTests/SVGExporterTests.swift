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

    @Test func tinyValidRadialRadiusExportsPositive() throws {
        let fill = Fill.radial(stops: [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)],
                               center: Point(x: 5, y: 5), radius: 0.00001)
        try fill.validate()
        let svg = try SVGExporter.gradient(fill, id: "g0")
        #expect(svg.contains(#"cx="5" cy="5" r="0.00001">"#))
        #expect(try SVGExporter.gradient(.radial(stops: [], center: Point(x: 0, y: 0), radius: 0.00006), id: "g")
            .contains(#"r="0.0001">"#))
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

    @Test func convertToSymbolKeepsContentInExports() throws {
        var e = CommandEngine(document: Fixtures.document())
        let before = try SVGExporter.export(scene: e.document.scenes[0], frame: 0)
        try e.perform(ConvertToSymbol(sceneID: "s1", layerIDs: ["ball"], symbolID: "sym", name: "Sym"))
        let after = try SVGExporter.export(scene: e.document.scenes[0], frame: 0, symbols: e.document.symbols)
        let paths = { (s: String) in s.components(separatedBy: "<path").count - 1 }
        #expect(paths(before) == 1 && paths(after) == paths(before))
    }

    @Test func instanceDrawsSymbolLayersAtTheSymbolFrame() throws {
        let inner = Layer(id: "in", name: "In", shapes: [Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 0)])],
                          tracks: ["x": [Keyframe(frame: 0, value: 0), Keyframe(frame: 4, value: 8)]])
        let symbol = Symbol(id: "sym", name: "Sym", durationFrames: 4, layers: [inner])
        let host = Layer(id: "h", name: "H", instances: [
            Instance(symbolID: "sym", transform: Transform(x: 5, y: 6), firstFrame: 1, loop: .playOnce),
        ])
        let svg = try SVGExporter.export(scene: Scene(id: "s", name: "S", layers: [host]), frame: 1.5, symbols: [symbol])
        // Host frame 1.5 rounds down to 1; playOnce from 1 gives symbol frame 2, so x = 4.
        #expect(svg.contains("""
        <g id="h" data-name="H" transform="matrix(1 0 0 1 0 0)">
        <g data-symbol="sym" transform="matrix(1 0 0 1 5 6)">
        <g data-id="in" data-name="In" transform="matrix(1 0 0 1 4 0)">
        <path d="M0 0 L1 0 Z" fill="#000000"/>
        </g>
        </g>
        </g>
        """))
    }

    @Test func strokeIsExported() throws {
        var scene = squareScene()
        scene.layers[0].shapes[0].stroke = Stroke(color: Color(r: 0, g: 0, b: 0, a: 0.5), width: 2,
                                                  join: .round, cap: .square)
        #expect(try SVGExporter.export(scene: scene, frame: 0).contains(" stroke=\"#000000\" stroke-opacity=\"0.5\""
            + " stroke-width=\"2\" stroke-linejoin=\"round\" stroke-linecap=\"square\"/>"))
    }

    @Test func missingOrCyclicSymbolsThrow() {
        let scene = Scene(id: "s", name: "S", layers: [Layer(id: "h", name: "H", instances: [Instance(symbolID: "a")])])
        #expect(throws: SVGExportError.unresolvedSymbol("a")) { try SVGExporter.export(scene: scene, frame: 0) }
        let loop = Symbol(id: "a", name: "A", layers: scene.layers)
        #expect(throws: SVGExportError.unresolvedSymbol("a")) {
            try SVGExporter.export(scene: scene, frame: 0, symbols: [loop])
        }
    }
}
