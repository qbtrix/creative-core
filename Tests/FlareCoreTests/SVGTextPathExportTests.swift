// SVGTextPathExportTests.swift: TE-8's acceptance checks for type on a path
// in SVG: one `<textPath>` naming its path in `<defs>`, `startOffset` as a
// percentage of the path's length, a flipped path written reversed, runs as
// `tspan`s, and byte-stable output.
@testable import FlareCore
import Testing

@Suite struct SVGTextPathExportTests {
    static func export(_ text: TextShape) throws -> String { try SVGTextExportTests.export(text) }

    @Test func textPathInDefsWithPercentOffset() throws {
        let svg = try Self.export(TextFixtures.text(onPath: TextOnPath(path: TextOnPathTests.line, startOffset: 0.25)))
        #expect(svg.contains("<defs><path id=\"tp0\" d=\"M0 0 L100 0\"/></defs>"))
        #expect(svg.contains("<textPath href=\"#tp0\" startOffset=\"25%\">"))
        #expect(SVGTextExportTests.count("<textPath", in: svg) == 1 && !svg.contains("<tspan x="))
    }

    @Test func flipReversesPathData() throws {
        let svg = try Self.export(TextFixtures.text(onPath: TextOnPath(path: TextOnPathTests.line, flipped: true)))
        #expect(svg.contains("d=\"M100 0 L0 0\"") && !svg.contains("d=\"M0 0 L100 0\""))
    }

    /// Curves swap their controls, contours run last first, and a closed
    /// contour starts where it did and walks its closing edge first.
    @Test func reversedPathWalksBackwards() throws {
        let p = { (x: Double, y: Double) in Point(x: x, y: y) }
        let path = Path(elements: [.move(to: p(0, 0)), .quad(control: p(5, 5), to: p(10, 0)),
                                   .cubic(control1: p(11, 1), control2: p(12, 2), to: p(13, 3)),
                                   .move(to: p(20, 0)), .line(to: p(30, 0)), .line(to: p(30, 10)), .close])
        #expect(try SVGExporter.pathData(SVGExporter.reversed(path))
                == "M20 0 L30 10 L30 0 L20 0 Z M13 3 C12 2 11 1 10 0 Q5 5 0 0")
        let open = Path(elements: [.move(to: p(0, 0)), .line(to: p(1, 0)), .cubic(control1: p(2, 1), control2: p(3, 1), to: p(4, 0))])
        #expect(SVGExporter.reversed(SVGExporter.reversed(open)) == open)
    }

    /// The reversed path, read forwards, places the glyphs flip places on the original.
    @Test func reversedPathMatchesFlippedPlacement() throws {
        let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 80, y: 0), Point(x: 80, y: 60), Point(x: 0, y: 60)], closed: true)
        for path in [TextOnPathTests.line, square] {
            let flipped = TextFixtures.text(onPath: TextOnPath(path: path, startOffset: 0.1, flipped: true))
            var plain = flipped
            plain.onPath = TextOnPath(path: SVGExporter.reversed(path), startOffset: 0.1)
            let a = try TextLayout.onPath(flipped, measured: FixedAdvances.measure(flipped), tolerance: 0.1)
            let b = try TextLayout.onPath(plain, measured: FixedAdvances.measure(plain), tolerance: 0.1)
            #expect(a.count == b.count && !a.isEmpty)
            for (g, h) in zip(a, b) {
                #expect(g.index == h.index && abs(g.position.x - h.position.x) < 1e-9 && abs(g.position.y - h.position.y) < 1e-9)
            }
        }
    }

    /// A styled run on a path, as recorded: any change to its bytes fails here.
    static let styled = TextFixtures.text("Bring " + TextFixtures.emoji,
        runs: [TextRun(start: 0, length: 5, weight: 700, fill: .solid(Color(r: 1, g: 0, b: 0)))],
        paragraph: ParagraphStyle(alignment: .center, tracking: 0.5),
        onPath: TextOnPath(path: TextOnPathTests.line, startOffset: 0.125))
    static let styledGolden = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
        <rect width="200" height="100" fill="#ffffff"/>
        <g id="t" data-name="Text" transform="matrix(1 0 0 1 0 0)">
        <defs><path id="tp0" d="M0 0 L100 0"/></defs>
        <text xml:space="preserve"><textPath href="#tp0" startOffset="12.5%"><tspan font-family="Inter" font-size="24" \#
        fill="#ff0000" font-weight="700" letter-spacing="0.5">Bring</tspan><tspan font-family="Inter" font-size="24" \#
        fill="#000000" letter-spacing="0.5"> \#(TextFixtures.emoji)</tspan></textPath></text>
        </g>
        </svg>

        """#
    @Test func byteStable() throws {
        #expect(try Self.export(Self.styled) == Self.export(Self.styled))
        #expect(try Self.export(Self.styled) == Self.styledGolden)
    }

    /// Two texts on paths get their own ids; a gradient run takes the next one after.
    @Test func idsDistinctAcrossTexts() throws {
        let stops = [GradientStop(offset: 0, color: Color(r: 1, g: 0, b: 0)), GradientStop(offset: 1, color: Color(r: 0, g: 0, b: 1))]
        let linear = Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))
        let a = TextFixtures.text("ab", onPath: TextOnPath(path: TextOnPathTests.line))
        let b = TextFixtures.text("cd", runs: [TextRun(start: 0, length: 1, fill: linear)], onPath: TextOnPath(path: TextOnPathTests.line))
        let layer = Layer(id: "t", name: "Text", texts: [a, b])
        let svg = try SVGExporter.export(scene: Scene(id: "s", name: "S", width: 200, height: 100, layers: [layer]), frame: 0)
        for needle in ["id=\"tp0\"", "href=\"#tp0\"", "id=\"g1\"", "id=\"tp2\"", "href=\"#tp2\"", "fill=\"url(#g1)\""] {
            #expect(SVGTextExportTests.count(needle, in: svg) == 1, "\(needle)")
        }
    }

    @Test func nonFiniteThrows() {
        let bad = Path(elements: [.move(to: Point(x: 0, y: 0)), .line(to: Point(x: .infinity, y: 0))])
        #expect(throws: SVGExportError.nonFiniteValue) { try Self.export(TextFixtures.text(onPath: TextOnPath(path: bad))) }
        #expect(throws: SVGExportError.nonFiniteValue) {
            try Self.export(TextFixtures.text(onPath: TextOnPath(path: TextOnPathTests.line, startOffset: .nan)))
        }
        #expect(throws: ModelError.self) {
            try Self.export(TextFixtures.text(paragraph: ParagraphStyle(lineHeight: .nan), onPath: TextOnPath(path: TextOnPathTests.line)))
        }
    }

    /// Seeded random paths and strings: export writes or throws, never crashes,
    /// and the spans hold the whole string once, in order.
    @Test func fuzzedPathsWriteOrThrow() throws {
        var rng = SplitMix64(seed: 0x7E8)
        let alphabet: [Character] = ["a", " ", "\n", "é", "👍🏽", "<"]
        var exported = 0
        defer { #expect(exported > 100) }
        for _ in 0..<150 {
            let pt = { (rng: inout SplitMix64) in Point(x: Double.random(in: -50...50, using: &rng), y: Double.random(in: -50...50, using: &rng)) }
            var elements: [PathElement] = []
            for _ in 0..<Int.random(in: 0...6, using: &rng) {
                switch Int.random(in: 0...4, using: &rng) {
                case 0: elements.append(.move(to: pt(&rng)))
                case 1: elements.append(.line(to: pt(&rng)))
                case 2: elements.append(.quad(control: pt(&rng), to: pt(&rng)))
                case 3: elements.append(.cubic(control1: pt(&rng), control2: pt(&rng), to: pt(&rng)))
                default: elements.append(.close)
                }
            }
            let path = Path(elements: elements)
            let string = String((0..<Int.random(in: 0...20, using: &rng)).map { _ in alphabet.randomElement(using: &rng) ?? "a" })
            let text = TextFixtures.text(string, runs: [TextRun(start: Int.random(in: -2...20, using: &rng), length: 3, weight: 700)],
                                         onPath: TextOnPath(path: path, startOffset: Double.random(in: 0...1, using: &rng),
                                                            flipped: Bool.random(using: &rng)))
            guard let svg = try? Self.export(text) else { continue }
            exported += 1
            let spans = svg.components(separatedBy: "</tspan>").dropLast().compactMap { $0.components(separatedBy: ">").last }.joined()
            #expect(spans == SVGExporter.escape(string), "\(string.debugDescription)")
        }
    }
}
