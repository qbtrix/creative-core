// TextLayoutTests.swift: TE-5's acceptance checks for `TextLayout.lay` on
// `FixedAdvances` (0.5 em advances, ascent 0.8 em, descent 0.2 em): wrapping,
// alignment, justification, line gaps, tracking, limits and a seeded fuzz.
import FlareCore
import Testing

@Suite struct TextLayoutTests {
    /// `string` at `size` points with `paragraph`, laid out on its fixed advances.
    static func lay(_ string: String, size: Double = 12, runs: [TextRun] = [],
                    _ paragraph: ParagraphStyle? = nil) throws -> TextLayout {
        var text = TextFixtures.text(string, runs: runs, paragraph: paragraph)
        text.fontSize = size
        return try TextLayout.lay(text, measured: FixedAdvances.measure(text))
    }

    static func box(_ width: Double, _ alignment: TextAlignment = .leading) -> ParagraphStyle {
        ParagraphStyle(alignment: alignment, lineHeight: 1, boxWidth: width)
    }
    /// Same count, and each value within 1e-9.
    static func near(_ a: [Double], _ b: [Double]) -> Bool { a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 } }
    @Test func wrapsAtTheSpace() throws {
        let lines = try Self.lay("abcd efghi", Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<5, 5..<10] && lines.map(\.width) == [24, 30])
        #expect(lines.last?.x == [0, 6, 12, 18, 24])
    }
    @Test func longWordBreaksByGrapheme() throws {
        let lines = try Self.lay(String(repeating: "w", count: 20), Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<5, 5..<10, 10..<15, 15..<20])
        #expect(lines.allSatisfy { $0.width <= 30 })
    }
    @Test func trailingSpaceDoesNotWrap() throws {
        let lines = try Self.lay("abcde fghij", Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<6, 6..<11] && lines.first?.width == 30)
    }
    @Test func centreShiftsByHalfTheSlack() throws {
        let lines = try Self.lay("abcd efghi", Self.box(30, .center)).lines
        #expect(lines.first?.x.first == 3 && lines.last?.x.first == 0)
        #expect(try Self.lay("abcd efghi", Self.box(30, .trailing)).lines.first?.x.first == 6)
        // With no box, lines align against the widest line (24 here).
        #expect(try Self.lay("ab\nabcd", ParagraphStyle(alignment: .center, lineHeight: 1)).lines.first?.x.first == 6)
        #expect(try Self.lay("ab\nabcd", ParagraphStyle(alignment: .trailing, lineHeight: 1)).lines.first?.x.first == 12)
    }
    @Test func lastLineNotJustified() throws {
        let lines = try Self.lay("ab cd efghi", Self.box(36, .justified)).lines
        #expect(lines.map(\.graphemes) == [0..<6, 6..<11])
        // The inner space stretches by the slack, 6, so "d" ends at the box edge, 36.
        #expect(lines.first.map { Array($0.x.prefix(5)) } == [0, 6, 12, 24, 30])
        #expect(lines.last?.x == [0, 6, 12, 18, 24])
        // A last line with a space of its own, and a paragraph's last line, stay unstretched too.
        #expect(try Self.lay("ab cd ef gh", Self.box(36, .justified)).lines.last?.x == [0, 6, 12, 18, 24])
        #expect(try Self.lay("a b\ncd", Self.box(36, .justified)).lines.first?.x == [0, 6, 12, 18])
    }
    @Test func lineGapIsLineHeightTimesSize() throws {
        let lines = try Self.lay("ab cd", size: 24, ParagraphStyle(lineHeight: 1.5, boxWidth: 30)).lines
        #expect(Self.near(lines.map(\.baseline), [19.2, 19.2 + 36]))
    }
    @Test func mixedSizesUseTallest() throws {
        let runs = [TextRun(start: 1, length: 1, fontSize: 48), TextRun(start: 4, length: 1, fontSize: 48)]
        let lines = try Self.lay("aB\ncD", size: 24, runs: runs, ParagraphStyle(lineHeight: 1)).lines
        #expect(Self.near(lines.map(\.baseline), [38.4, 38.4 + 48]))
    }
    @Test func newlineAddsParagraphSpacing() throws {
        let lines = try Self.lay("ab\ncd", size: 24, ParagraphStyle(lineHeight: 1, paragraphSpacing: 10)).lines
        #expect(lines.map(\.graphemes.lowerBound) == [0, 3] && Self.near(lines.map(\.baseline), [19.2, 19.2 + 34]))
        // A soft wrap adds no spacing; only the hard break does.
        let wrapped = try Self.lay("ab cd\nef", size: 24, ParagraphStyle(lineHeight: 1, paragraphSpacing: 10, boxWidth: 30))
        #expect(wrapped.lines.map(\.graphemes) == [0..<3, 3..<6, 6..<8])
        #expect(Self.near(wrapped.lines.map(\.baseline), [19.2, 43.2, 77.2]))
    }
    @Test func trackingPerGrapheme() throws {
        let runs = [TextRun(start: 0, length: 4, tracking: 1)]
        #expect(try Self.lay("abcd", runs: runs, ParagraphStyle(tracking: 2)).lines.first?.x == [0, 9, 18, 27])
    }
    @Test func tenThousandGraphemesLayOut() throws {
        let lines = try Self.lay(TextFixtures.longParagraph, Self.box(300)).lines
        #expect(lines.first?.graphemes.lowerBound == 0 && lines.last?.graphemes.upperBound == 10_000)
        #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.graphemes.upperBound == $1.graphemes.lowerBound })
        #expect(lines.allSatisfy { $0.width <= 300 })
    }
    @Test func moreThanMaxGraphemesThrows() throws {
        let count = TextLayout.maxGraphemes + 1, text = TextFixtures.text(String(repeating: "a", count: count))
        let measured = [try GlyphRunMetrics(advances: Array(repeating: 1, count: count), ascent: 1, descent: 1)]
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: measured) }
    }
    @Test func hugeStringThrowsBeforeBuildingIt() {
        let text = TextFixtures.text(String(repeating: "a", count: TextLayout.maxGraphemes * 50))
        #expect(FixedAdvances.measure(text).isEmpty)
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: FixedAdvances.measure(text)) }
    }
    @Test func lineHeightUsesAscentPlusDescent() throws {
        var text = TextFixtures.text("ab\ncd", paragraph: ParagraphStyle(lineHeight: 1))
        text.fontSize = 20
        let measured = [try GlyphRunMetrics(advances: Array(repeating: 10, count: 5), ascent: 18, descent: 6)]
        #expect(try TextLayout.lay(text, measured: measured).lines.map(\.baseline) == [18, 42])
    }
    @Test func lineGapTakesMaxAscentAndMaxDescentSeparately() throws {
        // Run A (ascent 10, descent 1) and run B (ascent 2, descent 8) share line 2: its gap is 10 + 8, not 11.
        var text = TextFixtures.text("ab\ncd", runs: [TextRun(start: 4, length: 1, fontSize: 30)],
                                     paragraph: ParagraphStyle(lineHeight: 2))
        text.fontSize = 20
        let measured = [try GlyphRunMetrics(advances: Array(repeating: 10, count: 4), ascent: 10, descent: 1),
                        try GlyphRunMetrics(advances: [10], ascent: 2, descent: 8)]
        #expect(try TextLayout.lay(text, measured: measured).lines.map(\.baseline) == [10, 10 + 2 * 18])
    }
    @Test func xHasOneEntryPerGraphemeWithTrailingSpace() throws {
        let lines = try Self.lay("abcde fghij", Self.box(30)).lines
        #expect(!lines.isEmpty && lines.allSatisfy { $0.x.count == $0.graphemes.count })
        #expect(lines.first?.x.count == 6)
    }
    @Test func advancesPerUTF16UnitThrowNamingTheFix() throws {
        let text = TextFixtures.text("a" + TextFixtures.emoji)
        let perUnit = [try GlyphRunMetrics(advances: Array(repeating: 1, count: text.string.utf16.count), ascent: 1, descent: 1)]
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: perUnit) }
        #expect(Self.message { try TextLayout.lay(text, measured: perUnit) }.contains("per Character"))
        #expect(Self.message { try TextLayout.lay(text, measured: perUnit + perUnit) }.contains("text.resolvedRuns"))
    }
    @Test func breaksAfterHyphen() throws {
        #expect(try Self.lay("abc-defgh", Self.box(30)).lines.map(\.graphemes) == [0..<4, 4..<9])
    }
    @Test func boundsAndTrailingNewline() throws {
        let bounds = try Self.lay("abcd efgh", Self.box(30, .center)).bounds
        #expect(Self.near([bounds.minX, bounds.minY, bounds.maxX, bounds.maxY], [3, 0, 27, 24]))
        let lines = try Self.lay("ab\n", ParagraphStyle(lineHeight: 1)).lines
        #expect(lines.map(\.graphemes) == [0..<3, 3..<3] && Self.near(lines.map(\.baseline), [9.6, 21.6]))
    }
    @Test func badInputThrows() throws {
        let text = TextFixtures.text("ab")
        let extra = try GlyphRunMetrics(advances: [1], ascent: 1, descent: 1)
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: FixedAdvances.measure(text) + [extra]) }
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: [extra]) }
        for paragraph in [ParagraphStyle(boxWidth: 0), ParagraphStyle(boxWidth: -1), ParagraphStyle(boxWidth: .nan),
                          ParagraphStyle(lineHeight: .infinity), ParagraphStyle(lineHeight: -1),
                          ParagraphStyle(paragraphSpacing: .nan)] {
            #expect(throws: ModelError.self) { try Self.lay("ab", paragraph) }
        }
        #expect(throws: ModelError.self) { try Self.lay("ab", size: -5) }
        let huge = [try GlyphRunMetrics(advances: [1e308, 1e308], ascent: 1e308, descent: 1e308)]
        #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: huge) }
    }
    @Test func badParagraphNamesField() {
        #expect(Self.message { try Self.lay("ab", ParagraphStyle(boxWidth: 0)) }.contains("boxWidth"))
        #expect(Self.message { try Self.lay("ab", ParagraphStyle(tracking: .nan)) }.contains("tracking"))
        #expect(Self.message { try Self.lay("ab", ParagraphStyle(lineHeight: -1)) }.contains("lineHeight"))
        #expect(Self.message { try Self.lay("ab", ParagraphStyle(paragraphSpacing: .nan)) }.contains("paragraphSpacing"))
    }
    /// The `ModelError.invalidText` message `body` throws, or "" for anything else.
    static func message(_ body: () throws -> Any) -> String {
        do { _ = try body() } catch ModelError.invalidText(let message) { return message } catch {}
        return ""
    }
    /// Seeded strings, box widths, font sizes, extra metrics and huge advances:
    /// a bad value throws, and every layout that succeeds is finite inside the string.
    @Test(arguments: 0..<50 as Range<UInt64>) func fuzz(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let pieces = ["a", " ", "\n", "-", TextFixtures.emoji, TextFixtures.combining]
        let string = (0..<Int.random(in: 0...40, using: &rng)).map { _ in pieces.randomElement(using: &rng) ?? "" }.joined()
        let widths: [Double] = [-1, 0, .nan, .infinity, 1, 50], sizes: [Double] = [24, -5]
        let width = widths.randomElement(using: &rng) ?? 1
        var text = TextFixtures.text(string, paragraph: ParagraphStyle(alignment: .justified, boxWidth: width))
        text.fontSize = sizes.randomElement(using: &rng) ?? 24
        var measured = FixedAdvances.measure(text)
        let big = Bool.random(using: &rng)
        if big {
            let values: [Double] = [0, 1, 1e308, .greatestFiniteMagnitude]
            let pick = { (rng: inout SplitMix64) in values.randomElement(using: &rng) ?? 0 }
            measured = try measured.map { m in
                try GlyphRunMetrics(advances: m.advances.map { _ in pick(&rng) }, ascent: pick(&rng), descent: pick(&rng))
            }
        }
        let padded = Bool.random(using: &rng)
        if padded { measured.append(try GlyphRunMetrics(advances: [1], ascent: 1, descent: 1)) }
        if padded || !(width.isFinite && width > 0) || (text.fontSize <= 0 && !string.isEmpty) {
            #expect(throws: ModelError.self) { try TextLayout.lay(text, measured: measured) }
            return
        }
        // Huge metrics may overflow and throw; ordinary ones must lay out.
        let result: TextLayout? = big ? try? TextLayout.lay(text, measured: measured) : try TextLayout.lay(text, measured: measured)
        guard let layout = result else { return }
        let b = layout.bounds, boundsFinite = [b.minX, b.minY, b.maxX, b.maxY].allSatisfy { $0.isFinite }
        let linesOK = layout.lines.allSatisfy { line in
            line.graphemes.upperBound <= string.count && line.baseline.isFinite && line.width.isFinite
                && line.x.allSatisfy { $0.isFinite }
        }
        #expect(boundsFinite && linesOK)
    }
}
