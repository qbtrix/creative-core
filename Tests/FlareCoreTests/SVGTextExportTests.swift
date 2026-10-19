// SVGTextExportTests.swift: TE-7's acceptance checks for SVG text (runs as
// tspans, lines at their layout baselines, alignment, justified x lists) and
// TE-8's for type on a path (`textPath`). TE-7 built its cases; each TE-8 case waits, disabled by name,
// until its task builds the writer and removes the trait.
@testable import FlareCore
import Testing

@Suite struct SVGTextExportTests {
    /// A 200 x 100 scene whose one layer holds `text`.
    static func export(_ text: TextShape) throws -> String {
        let layer = Layer(id: "t", name: "Text", texts: [text])
        return try SVGExporter.export(scene: Scene(id: "s", name: "S", width: 200, height: 100, layers: [layer]), frame: 0)
    }

    static func count(_ needle: String, in svg: String) -> Int { svg.components(separatedBy: needle).count - 1 }
    /// "Bring the light home" wrapped at 120 into two lines, 1.5 apart.
    static func wrapped(_ alignment: TextAlignment) -> TextShape {
        TextFixtures.text("Bring the light home", paragraph: ParagraphStyle(alignment: alignment, lineHeight: 1.5, boxWidth: 120))
    }
    @Test func runWeightWritten() throws {
        let red = Fill.solid(Color(r: 1, g: 0, b: 0))
        let runs = [TextRun(start: 6, length: 5, fontFamily: "Mono", weight: 700, italic: true, fill: red,
                            tracking: 2, baselineShift: -3)]
        let svg = try Self.export(TextFixtures.text(runs: runs))
        #expect(Self.count("<text ", in: svg) == 1 && Self.count("<tspan font-family", in: svg) == 3)
        // Every resolved run reaches the SVG as its own span, in order.
        let spans = [">Bring </tspan>", ">the l</tspan>", ">ight</tspan>"].map { svg.range(of: $0)?.lowerBound }
        let found = spans.compactMap { $0 }
        #expect(found.count == 3 && found == found.sorted(), "\(spans)")
        #expect(Self.count("font-weight=\"700\"", in: svg) == 1 && Self.count("font-style=\"italic\"", in: svg) == 1)
        for attribute in ["font-family=\"Inter\"", "font-family=\"Mono\"", "font-size=\"24\"", "fill=\"#ff0000\"",
                          "letter-spacing=\"2\"", "baseline-shift=\"-3\"", ">the l<"] {
            #expect(svg.contains(attribute), "\(attribute)")
        }
    }
    @Test func baselinesFromLayout() throws {
        let text = Self.wrapped(.leading), layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        #expect(layout.lines.count == 2)
        let svg = try Self.export(text)
        for line in layout.lines { #expect(svg.contains("y=\"\(try SVGExporter.number(line.baseline))\""), "\(line)") }
    }
    @Test func alignmentAsTextAnchor() throws {
        #expect(try Self.export(Self.wrapped(.center)).contains("text-anchor=\"middle\""))
        #expect(try Self.export(Self.wrapped(.trailing)).contains("text-anchor=\"end\""))
        #expect(!(try Self.export(Self.wrapped(.leading)).contains("text-anchor")))
    }
    /// A middle or end anchor sits at the line's centre or end, trailing spaces unwritten.
    @Test func anchoredXAtLineCentreAndEnd() throws {
        for (alignment, share) in [(TextAlignment.center, 0.5), (.trailing, 1.0)] {
            let text = Self.wrapped(alignment), layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
            let svg = try Self.export(text)
            for line in layout.lines {
                let x = try SVGExporter.number((line.x.first ?? 0) + line.width * share)
                #expect(svg.contains("<tspan x=\"\(x)\" y=\"\(try SVGExporter.number(line.baseline))\">"), "\(alignment)")
            }
            #expect(svg.contains(">Bring the</tspan>") && !svg.contains("the </tspan>"))
        }
    }
    @Test func justifiedLineHasExplicitXList() throws {
        let text = Self.wrapped(.justified), layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        let first = try #require(layout.lines.first)
        let xs = try first.x.map { try SVGExporter.number($0) }.joined(separator: " ")
        let svg = try Self.export(text)
        #expect(svg.contains("x=\"\(xs)\""))
        #expect(Self.count("x=\"\(xs)\"", in: svg) == 1)
    }
    /// A styled, wrapped, centred text with emoji and combining marks.
    static let styled = TextFixtures.text("Bring " + TextFixtures.emoji + " " + TextFixtures.combining + " home",
        runs: [TextRun(start: 0, length: 5, weight: 700),
               TextRun(start: 6, length: 2, italic: true, fill: .solid(Color(r: 1, g: 0, b: 0)), tracking: 1)],
        paragraph: ParagraphStyle(alignment: .center, tracking: 0.5, boxWidth: 120))
    /// `styled`'s SVG as recorded: any change to its bytes fails here.
    static let styledGolden = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
        <rect width="200" height="100" fill="#ffffff"/>
        <g id="t" data-name="Text" transform="matrix(1 0 0 1 0 0)">
        <text xml:space="preserve" text-anchor="middle">
        <tspan x="60" y="19.2"><tspan font-family="Inter" font-size="24" fill="#000000" font-weight="700" \#
        letter-spacing="0.5">Bring</tspan><tspan font-family="Inter" font-size="24" fill="#000000" letter-spacing="0.5"> \#
        </tspan><tspan font-family="Inter" font-size="24" fill="#ff0000" font-style="italic" letter-spacing="1.5">\#(String(TextFixtures.emoji.prefix(2)))\#
        </tspan><tspan font-family="Inter" font-size="24" fill="#000000" letter-spacing="0.5">\#
        \#(String(TextFixtures.emoji.suffix(1)))</tspan></tspan>
        <tspan x="60" y="48"><tspan font-family="Inter" font-size="24" fill="#000000" letter-spacing="0.5">\#(TextFixtures.combining) \#
        home</tspan></tspan>
        </text>
        </g>
        </svg>

        """#
    @Test func byteStableAndNonFiniteThrows() throws {
        let text = TextFixtures.text(TextFixtures.emoji + " " + TextFixtures.combining, runs: [TextRun(start: 0, length: 1, weight: 700)])
        #expect(try Self.export(text) == Self.export(text))
        #expect(try Self.export(Self.styled) == Self.styledGolden)
        var bad = text
        bad.runs = [TextRun(start: 0, length: 1, tracking: .nan)]
        #expect(throws: SVGExportError.self) { try Self.export(bad) }
    }
    /// Lines come from the metrics the caller measured, not from 0.5 em advances.
    @Test func justifiedUsesGivenMetrics() throws {
        let text = Self.wrapped(.justified)
        let ten = { (shape: TextShape) in
            shape.resolvedRuns.compactMap { try? GlyphRunMetrics(advances: Array(repeating: 10, count: $0.length), ascent: 19.2, descent: 4.8) }
        }
        let first = try #require(try TextLayout.lay(text, measured: ten(text)).lines.first)
        let fixed = try #require(try TextLayout.lay(text, measured: FixedAdvances.measure(text)).lines.first)
        #expect(first.x != fixed.x)
        let layer = Layer(id: "t", name: "Text", texts: [text])
        let svg = try SVGExporter.export(scene: Scene(id: "s", name: "S", width: 200, height: 100, layers: [layer]),
                                         frame: 0, measure: ten)
        #expect(svg.contains("x=\"\(try first.x.map { try SVGExporter.number($0) }.joined(separator: " "))\""))
    }
    /// A layout the text model refuses throws its `ModelError`, not an `SVGExportError`.
    @Test func refusedLayoutThrowsModelError() {
        #expect(throws: ModelError.self) { try Self.export(TextFixtures.text(paragraph: ParagraphStyle(lineHeight: .nan))) }
    }
    /// The shape's position offsets every line's x and baseline y.
    @Test func positionOffsetsLines() throws {
        var text = TextFixtures.text()
        text.position = Point(x: 10, y: 20)
        #expect(try Self.export(text).contains("<tspan x=\"10\" y=\"39.2\">"))
    }
    /// A gradient run fill writes its element before the <text>, numbered after a path's.
    @Test func gradientRunFillWritesItsElement() throws {
        let stops = [GradientStop(offset: 0, color: Color(r: 1, g: 0, b: 0)), GradientStop(offset: 1, color: Color(r: 0, g: 0, b: 1))]
        let linear = Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))
        let text = TextFixtures.text(runs: [TextRun(start: 0, length: 2, fill: linear)])
        let square = Shape(points: [Point(x: 0, y: 0), Point(x: 5, y: 0), Point(x: 5, y: 5)], fill: linear)
        let layer = Layer(id: "t", name: "Text", shapes: [square], texts: [text])
        let svg = try SVGExporter.export(scene: Scene(id: "s", name: "S", width: 200, height: 100, layers: [layer]), frame: 0)
        #expect(Self.count("id=\"g0\"", in: svg) == 1 && Self.count("id=\"g1\"", in: svg) == 1)
        let g1 = try #require(svg.range(of: "id=\"g1\""))
        let open = try #require(svg.range(of: "<text"))
        #expect(g1.lowerBound < open.lowerBound)
        #expect(svg.contains("<tspan font-family=\"Inter\" font-size=\"24\" fill=\"url(#g1)\">Br</tspan>"))
    }
    @Test func textContentEscaped() throws {
        let svg = try Self.export(TextFixtures.text("a<b&c"))
        #expect(svg.contains(">a&lt;b&amp;c</tspan>") && !svg.contains("a<b"))
        let family = try Self.export(TextFixtures.text("ab", runs: [TextRun(start: 0, length: 1, fontFamily: "A&\"B\"")]))
        #expect(family.contains("font-family=\"A&amp;&quot;B&quot;\""))
    }
    @Test func letterSpacingAddsParagraphTracking() throws {
        let svg = try Self.export(TextFixtures.text(runs: [TextRun(start: 6, length: 5, tracking: 2)],
                                                    paragraph: ParagraphStyle(tracking: 3)))
        #expect(Self.count("letter-spacing=\"5\"", in: svg) == 1 && Self.count("letter-spacing=\"3\"", in: svg) == 2)
    }
    /// Seeded random strings, runs and boxes: export writes or throws, never
    /// crashes, and the spans hold every non-whitespace grapheme once, in order.
    @Test func fuzzedRunsAndLinesWriteEveryGrapheme() throws {
        var rng = SplitMix64(seed: 0x5E7)
        let alphabet: [Character] = ["a", "b", " ", "\n", "-", "é", "👍🏽"]
        var exported = 0
        defer { #expect(exported > 150) }
        for _ in 0..<200 {
            let string = String((0..<Int.random(in: 0...40, using: &rng)).map { _ in alphabet.randomElement(using: &rng) ?? "a" })
            let runs = (0..<Int.random(in: 0...6, using: &rng)).map { _ in
                TextRun(start: Int.random(in: -2...42, using: &rng), length: Int.random(in: 1...8, using: &rng),
                        weight: Bool.random(using: &rng) ? 700 : nil, tracking: Double.random(in: -1...3, using: &rng))
            }
            let box: Double? = Bool.random(using: &rng) ? Double.random(in: 1...200, using: &rng) : nil
            let alignment = [TextAlignment.leading, .center, .trailing, .justified].randomElement(using: &rng) ?? .leading
            let text = TextFixtures.text(string, runs: runs, paragraph: ParagraphStyle(alignment: alignment, boxWidth: box))
            guard let svg = try? Self.export(text) else { continue }
            exported += 1
            let written = svg.components(separatedBy: "</tspan>").compactMap { $0.components(separatedBy: ">").last }
                .joined().filter { !$0.isWhitespace }
            #expect(written == string.filter { !$0.isWhitespace }, "\(string.debugDescription) \(runs)")
        }
    }
    /// TE-8: type on a path writes `textPath` with the path in `defs` and the offset as a percentage.
    @Test(.disabled("waits on TE-8")) func textPathInDefsWithPercentOffset() throws {
        let svg = try Self.export(TextFixtures.text(onPath: TextOnPath(path: TextOnPathTests.line, startOffset: 0.25)))
        #expect(svg.contains("<defs>") && svg.contains("d=\"M0 0 L100 0\"") && svg.contains("<textPath"))
        #expect(svg.contains("startOffset=\"25%\""))
    }
    @Test(.disabled("waits on TE-8")) func flipReversesPathData() throws {
        let svg = try Self.export(TextFixtures.text(onPath: TextOnPath(path: TextOnPathTests.line, flipped: true)))
        #expect(svg.contains("d=\"M100 0 L0 0\"") && !svg.contains("d=\"M0 0 L100 0\""))
    }
}
