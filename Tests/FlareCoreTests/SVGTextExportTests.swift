// SVGTextExportTests.swift: TE-7's acceptance checks for SVG text (runs as
// tspans, lines at their layout baselines, alignment, justified x lists) and
// TE-8's for type on a path (`textPath`). Each case waits, disabled by name,
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
    @Test(.disabled("waits on TE-7")) func runWeightWritten() throws {
        let red = Fill.solid(Color(r: 1, g: 0, b: 0))
        let runs = [TextRun(start: 6, length: 5, fontFamily: "Mono", weight: 700, italic: true, fill: red,
                            tracking: 2, baselineShift: -3)]
        let svg = try Self.export(TextFixtures.text(runs: runs))
        #expect(Self.count("<text ", in: svg) == 1 && Self.count("<tspan", in: svg) >= 3)
        #expect(Self.count("font-weight=\"700\"", in: svg) == 1 && Self.count("font-style=\"italic\"", in: svg) == 1)
        for attribute in ["font-family=\"Inter\"", "font-family=\"Mono\"", "font-size=\"24\"", "fill=\"#ff0000\"",
                          "letter-spacing=\"2\"", "baseline-shift=\"-3\"", ">the l<"] {
            #expect(svg.contains(attribute), "\(attribute)")
        }
    }
    @Test(.disabled("waits on TE-7")) func baselinesFromLayout() throws {
        let text = Self.wrapped(.leading), layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        #expect(layout.lines.count == 2)
        let svg = try Self.export(text)
        for line in layout.lines { #expect(svg.contains("y=\"\(try SVGExporter.number(line.baseline))\""), "\(line)") }
    }
    @Test(.disabled("waits on TE-7")) func alignmentAsTextAnchor() throws {
        #expect(try Self.export(Self.wrapped(.center)).contains("text-anchor=\"middle\""))
        #expect(try Self.export(Self.wrapped(.trailing)).contains("text-anchor=\"end\""))
        #expect(!(try Self.export(Self.wrapped(.leading)).contains("text-anchor")))
    }
    @Test(.disabled("waits on TE-7")) func justifiedLineHasExplicitXList() throws {
        let text = Self.wrapped(.justified), layout = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        let first = try #require(layout.lines.first)
        let xs = try first.x.map { try SVGExporter.number($0) }.joined(separator: " ")
        let svg = try Self.export(text)
        #expect(svg.contains("x=\"\(xs)\""))
        #expect(Self.count("x=\"\(xs)\"", in: svg) == 1)
    }
    @Test(.disabled("waits on TE-7")) func byteStableAndNonFiniteThrows() throws {
        let text = TextFixtures.text(TextFixtures.emoji + " " + TextFixtures.combining, runs: [TextRun(start: 0, length: 1, weight: 700)])
        #expect(try Self.export(text) == Self.export(text))
        var bad = text
        bad.runs = [TextRun(start: 0, length: 1, tracking: .nan)]
        #expect(throws: SVGExportError.self) { try Self.export(bad) }
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
