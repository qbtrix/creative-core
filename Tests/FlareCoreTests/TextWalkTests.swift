// TextWalkTests.swift: KJ-TE, the text-engine walk (TE-9). A 24 pt text shape
// "Bring the light home" on the fixture's ball layer is styled, wrapped,
// justified and spaced through commands and checked against the layout on
// `FixedAdvances` (12 per grapheme); its string is edited with the bold run
// kept on "light"; it is set on a circle of diameter 200 from offset 0.25,
// which puts the first glyph at the circle's bottom; the scene is written to
// SVG and the document round-trips through the file format; then every step
// undoes, in order, back to the plain shape.
@testable import FlareCore
import Foundation
import Testing

@Suite struct TextWalkTests {
    static let o = LayerOwner.scene(Fixtures.sceneID)
    static let bold = TextRunStyle(weight: 700)
    static let radius = 100.0
    static let center = Point(x: 100, y: 100)

    /// The circle of `radius` about `center` as 32 cubic arcs from its right
    /// point, clockwise on screen (y down): a quarter of the way round is its bottom.
    static func circle() -> Path {
        let n = 32, step = 2 * Double.pi / Double(n), k = 4.0 / 3.0 * tan(step / 4) * radius
        func at(_ a: Double) -> Point { Point(x: center.x + radius * cos(a), y: center.y + radius * sin(a)) }
        var elements: [PathElement] = [.move(to: at(0))]
        for i in 0..<n {
            let a0 = Double(i) * step, a1 = a0 + step, p0 = at(a0), p1 = at(a1)
            elements.append(.cubic(control1: Point(x: p0.x - k * sin(a0), y: p0.y + k * cos(a0)),
                                   control2: Point(x: p1.x + k * sin(a1), y: p1.y - k * cos(a1)), to: p1))
        }
        return Path(elements: elements + [.close])
    }

    static func text(_ doc: Document) throws -> TextShape { try #require(TextFixtures.ballText(doc)) }
    static func layout(_ doc: Document) throws -> TextLayout {
        let text = try text(doc)
        return try TextLayout.lay(text, measured: FixedAdvances.measure(text))
    }
    static func paragraph(_ p: ParagraphStyle) -> SetParagraphStyle {
        SetParagraphStyle(owner: o, layerID: "ball", textIndex: 0, paragraph: p)
    }
    /// The graphemes `word` covers in `string`.
    static func graphemes(of word: String, in string: String) throws -> Range<Int> {
        let r = try #require(string.range(of: word))
        let start = string.distance(from: string.startIndex, to: r.lowerBound)
        return start..<(start + word.count)
    }

    @Test func walk() throws {
        let plain = TextFixtures.document(TextFixtures.text("Bring the light home"))
        var engine = CommandEngine(document: plain)
        var states = [plain]
        func step(_ command: some Command) throws {
            try engine.perform(command)
            states.append(engine.document)
        }

        // 1. Bold on "light": three runs that tile the string, the middle one bold.
        let light = try Self.graphemes(of: "light", in: "Bring the light home")
        try step(ApplyTextStyle(owner: Self.o, layerID: "ball", textIndex: 0, range: light, style: Self.bold))
        let runs = try Self.text(engine.document).resolvedRuns
        #expect(runs.map(\.start) == [0, 10, 15] && runs.map(\.length) == [10, 5, 5])
        #expect(runs.map(\.weight) == [400, 700, 400])

        // 2. Box width 120: two lines, broken after "the ".
        var style = ParagraphStyle(boxWidth: 120)
        try step(Self.paragraph(style))
        var laid = try Self.layout(engine.document)
        #expect(laid.lines.map(\.graphemes) == [0..<10, 10..<20])

        // 3. Justified: the first line's last grapheme ends at x 120; the last line is not stretched.
        style.alignment = .justified
        try step(Self.paragraph(style))
        laid = try Self.layout(engine.document)
        let first = try #require(laid.lines.first)
        #expect(abs(first.x[8] + 12 - 120) < 1e-9 && abs(first.width - 120) < 1e-9)
        #expect(laid.lines.last?.x.first == 0)

        // 4. Line height 1.5: the baseline gap is 1.5 × 24.
        style.lineHeight = 1.5
        try step(Self.paragraph(style))
        laid = try Self.layout(engine.document)
        let baselines = laid.lines.map(\.baseline)
        #expect(baselines.count == 2 && abs(baselines[0] - 19.2) < 1e-9 && abs(baselines[1] - baselines[0] - 36) < 1e-9)

        // 5. "warm " inserted before "light": bold stays on "light".
        let warm = "Bring the warm light home"
        try step(EditTextString(owner: Self.o, layerID: "ball", textIndex: 0, replacing: 10..<10, with: "warm "))
        let edited = try Self.text(engine.document)
        #expect(edited.string == warm)
        let boldRuns = edited.resolvedRuns.filter { $0.weight == 700 }
        #expect(boldRuns.map { $0.start..<($0.start + $0.length) } == [try Self.graphemes(of: "light", in: warm)])

        // 6. On the circle from offset 0.25: the first glyph's pen point is the
        // circle's bottom, and its centre, half an advance on, lies on the
        // circle with the tangent there, near horizontal (running leftwards).
        try step(SetTextOnPath(owner: Self.o, layerID: "ball", textIndex: 0,
                               onPath: TextOnPath(path: Self.circle(), startOffset: 0.25)))
        let onCircle = try Self.text(engine.document)
        let glyphs = try TextLayout.onPath(onCircle, measured: FixedAdvances.measure(onCircle), tolerance: 0.01)
        #expect(glyphs.map(\.index) == Array(0..<warm.count))
        let g = try #require(glyphs.first)
        let angle = Double.pi / 2 + 6 / Self.radius
        let tx = cos(g.degrees * Double.pi / 180), ty = sin(g.degrees * Double.pi / 180)
        let mid = Point(x: g.position.x + 6 * tx, y: g.position.y + 6 * ty)
        // Within the flattening's arc-length error at tolerance 0.01.
        #expect(abs(mid.x - (Self.center.x + Self.radius * cos(angle))) < 1e-3, "\(mid)")
        #expect(abs(mid.y - (Self.center.y + Self.radius * sin(angle))) < 1e-3, "\(mid)")
        // Degrees compared modulo 360, so 183.4 and -176.6 are the same heading.
        let turn = { (d: Double) in abs(remainder(d, 360)) }
        #expect(turn(g.degrees - (angle * 180 / Double.pi + 90)) < 1e-2 && turn(g.degrees - 180) < 4, "\(g.degrees)")
        #expect(abs(g.position.x - Self.center.x) < 0.25 && abs(g.position.y - (Self.center.y + Self.radius)) < 0.25)

        // 7. SVG: one text on one textPath at 25%, the circle in defs, "light" bold; byte-stable.
        let scene = try #require(engine.document.scenes.first)
        let svg = try SVGExporter.export(scene: scene, frame: 0)
        #expect(SVGTextExportTests.count("<text ", in: svg) == 1 && SVGTextExportTests.count("<textPath", in: svg) == 1)
        #expect(svg.contains("<textPath href=\"#tp0\" startOffset=\"25%\">") && svg.contains("<defs><path id=\"tp0\" d=\"M200 100 C"))
        #expect(svg.contains("font-weight=\"700\">light</tspan>"))
        #expect(try SVGExporter.export(scene: scene, frame: 0) == svg)

        // 8. The file round-trips with every text field.
        let decoded = try FlareFormat.decode(FlareFormat.encode(engine.document))
        #expect(decoded == engine.document && TextFixtures.ballText(decoded) == onCircle)

        // 9. Undo every step, each back to the state before it, to the plain shape.
        #expect(states.count == 7)
        for expected in states.dropLast().reversed() {
            try engine.undo()
            #expect(engine.document == expected)
        }
        #expect(!engine.canUndo && engine.document == plain)
    }

    /// The walk's justified step in SVG: the stretched first line carries its
    /// per-grapheme x list, the last line starts at 0, at the layout's baselines.
    @Test func justifiedLinesExport() throws {
        let runs = [TextRun(start: 10, length: 5, weight: 700)]
        let text = TextFixtures.text("Bring the light home", runs: runs,
                                     paragraph: ParagraphStyle(alignment: .justified, lineHeight: 1.5, boxWidth: 120))
        let laid = try TextLayout.lay(text, measured: FixedAdvances.measure(text))
        let svg = try SVGTextExportTests.export(text)
        #expect(laid.lines.count == 2 && SVGTextExportTests.count("<tspan x=", in: svg) == 2)
        #expect(svg.contains("y=\"19.2\"") && svg.contains("y=\"55.2\""))
        #expect(svg.contains("font-weight=\"700\">light</tspan>"))
    }
}
