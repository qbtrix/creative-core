// SVGRenderListTests.swift: the SVG exporter walks the scene's render list
// and writes the same bytes it wrote when it walked the layers itself. The
// golden strings below were recorded from the exporter before it moved onto
// the render list; a text layer and a missing symbol still throw.
import FlareCore
import Testing

@Suite struct SVGRenderListTests {
    /// `Fixtures.document()` (and `withSymbol()`, whose scene is the same) with
    /// the ball's x translation for the frame.
    static let document: [Double: String] = [
        0: #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="550" height="400" viewBox="0 0 550 400">
        <rect width="550" height="400" fill="#ffffff"/>
        <g id="bg" data-name="Background" transform="matrix(1 0 0 1 0 0)">
        </g>
        <g id="ball" data-name="Ball" transform="matrix(1 0 0 1 0 0)">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#ff8040"/>
        </g>
        </svg>

        """#,
        12: #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="550" height="400" viewBox="0 0 550 400">
        <rect width="550" height="400" fill="#ffffff"/>
        <g id="bg" data-name="Background" transform="matrix(1 0 0 1 0 0)">
        </g>
        <g id="ball" data-name="Ball" transform="matrix(1 0 0 1 50 0)">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#ff8040"/>
        </g>
        </svg>

        """#,
        23: #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="550" height="400" viewBox="0 0 550 400">
        <rect width="550" height="400" fill="#ffffff"/>
        <g id="bg" data-name="Background" transform="matrix(1 0 0 1 0 0)">
        </g>
        <g id="ball" data-name="Ball" transform="matrix(1 0 0 1 99.6658 0)">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#ff8040"/>
        </g>
        </svg>

        """#,
    ]

    /// `NestedScene.scene(withText: false, withMissing: false)`: its tracks
    /// are constant, so frames 0, 12 and 23 write the same bytes.
    static let nested = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <rect width="100" height="100" fill="#ffffff"/>
        <g id="main" data-name="Main" transform="matrix(1 0 0 1 0 0)">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#000000"/>
        <path d="M0 0 C1 2 3 4 5 0 Z" fill="#0000ff" stroke="#000000" stroke-width="2" stroke-linejoin="miter" stroke-linecap="butt"/>
        </g>
        <g id="host" data-name="Host" transform="matrix(1 0 0 1 10 0)" opacity="0.5">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#000000"/>
        <g data-symbol="outer" transform="matrix(1 0 0 1 5 0)">
        <g data-id="outerLayer" data-name="Outer" transform="matrix(0 1 -1 0 0 0)" opacity="0.5">
        <path d="M0 0 L10 0 L10 10 L0 10 Z" fill="#000000"/>
        <g data-symbol="inner" transform="matrix(2 0 0 2 0 0)">
        <g data-id="innerLayer" data-name="Inner" transform="matrix(1 0 0 1 0 3)" opacity="0.8">
        <path d="M0 0 C1 2 3 4 5 0 Z" fill="#0000ff" stroke="#000000" stroke-width="2" stroke-linejoin="miter" stroke-linecap="butt"/>
        </g>
        </g>
        </g>
        </g>
        </g>
        </svg>

        """#

    @Test(arguments: [0.0, 12, 23])
    func fixturesMatchRecordedBytes(frame: Double) throws {
        let doc = Fixtures.document(), sym = Fixtures.withSymbol()
        let expected = try #require(Self.document[frame])
        #expect(try SVGExporter.export(scene: doc.scenes[0], frame: frame, symbols: doc.symbols) == expected)
        #expect(try SVGExporter.export(scene: sym.scenes[0], frame: frame, symbols: sym.symbols) == expected)
    }

    @Test(arguments: [0.0, 12, 23])
    func nestedSceneMatchesRecordedBytes(frame: Double) throws {
        let scene = NestedScene.scene(withText: false, withMissing: false)
        #expect(try SVGExporter.export(scene: scene, frame: frame, symbols: NestedScene.symbols) == Self.nested)
    }

    @Test func textAndMissingSymbolStillThrow() {
        let withText = NestedScene.scene(withText: true, withMissing: false)
        #expect(throws: SVGExportError.unsupported("text")) {
            try SVGExporter.export(scene: withText, frame: 0, symbols: NestedScene.symbols)
        }
        let withMissing = NestedScene.scene(withText: false, withMissing: true)
        #expect(throws: SVGExportError.unresolvedSymbol("missing")) {
            try SVGExporter.export(scene: withMissing, frame: 0, symbols: NestedScene.symbols)
        }
        // A missing symbol inside a symbol throws too, from inside the nested walk.
        var outer = NestedScene.outer
        outer.layers[0].instances.append(Instance(symbolID: "gone"))
        let scene = NestedScene.scene(withText: false, withMissing: false)
        #expect(throws: SVGExportError.unresolvedSymbol("gone")) {
            try SVGExporter.export(scene: scene, frame: 0, symbols: [outer, NestedScene.inner])
        }
        // The text check comes first, as before: a layer holding both text and
        // a missing instance reports the text.
        var both = scene
        both.layers[0].texts = [TextShape(string: "a", fontFamily: "Serif", fontSize: 9, position: Point(x: 0, y: 0))]
        both.layers[0].instances = [Instance(symbolID: "missing")]
        #expect(throws: SVGExportError.unsupported("text")) {
            try SVGExporter.export(scene: both, frame: 0, symbols: NestedScene.symbols)
        }
    }
}
