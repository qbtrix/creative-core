// TextLayoutTests.swift: TE-5's acceptance checks for `TextLayout.lay` on
// `FixedAdvances` (0.5 em advances, ascent 0.8 em, descent 0.2 em). Each case
// waits, disabled by name, until TE-5 builds `lay` and removes the trait.
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
    @Test(.disabled("waits on TE-5")) func wrapsAtTheSpace() throws {
        let lines = try Self.lay("abcd efghi", Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<5, 5..<10] && lines.map(\.width) == [24, 30])
        #expect(lines.last?.x == [0, 6, 12, 18, 24])
    }
    @Test(.disabled("waits on TE-5")) func longWordBreaksByGrapheme() throws {
        let lines = try Self.lay(String(repeating: "w", count: 20), Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<5, 5..<10, 10..<15, 15..<20])
        #expect(lines.allSatisfy { $0.width <= 30 })
    }
    @Test(.disabled("waits on TE-5")) func trailingSpaceDoesNotWrap() throws {
        let lines = try Self.lay("abcde fghij", Self.box(30)).lines
        #expect(lines.map(\.graphemes) == [0..<6, 6..<11] && lines.first?.width == 30)
    }
    @Test(.disabled("waits on TE-5")) func centreShiftsByHalfTheSlack() throws {
        let lines = try Self.lay("abcd efghi", Self.box(30, .center)).lines
        #expect(lines.first?.x.first == 3 && lines.last?.x.first == 0)
        #expect(try Self.lay("abcd efghi", Self.box(30, .trailing)).lines.first?.x.first == 6)
    }
    @Test(.disabled("waits on TE-5")) func lastLineNotJustified() throws {
        let lines = try Self.lay("ab cd efghi", Self.box(36, .justified)).lines
        #expect(lines.map(\.graphemes) == [0..<6, 6..<11])
        // The inner space stretches by the slack, 6, so "d" ends at the box edge, 36.
        #expect(lines.first.map { Array($0.x.prefix(5)) } == [0, 6, 12, 24, 30])
        #expect(lines.last?.x == [0, 6, 12, 18, 24])
    }
    @Test(.disabled("waits on TE-5")) func lineGapIsLineHeightTimesSize() throws {
        let lines = try Self.lay("ab cd", size: 24, ParagraphStyle(lineHeight: 1.5, boxWidth: 30)).lines
        #expect(Self.near(lines.map(\.baseline), [19.2, 19.2 + 36]))
    }
    @Test(.disabled("waits on TE-5")) func mixedSizesUseTallest() throws {
        let runs = [TextRun(start: 1, length: 1, fontSize: 48), TextRun(start: 4, length: 1, fontSize: 48)]
        let lines = try Self.lay("aB\ncD", size: 24, runs: runs, ParagraphStyle(lineHeight: 1)).lines
        #expect(Self.near(lines.map(\.baseline), [38.4, 38.4 + 48]))
    }
    @Test(.disabled("waits on TE-5")) func newlineAddsParagraphSpacing() throws {
        let lines = try Self.lay("ab\ncd", size: 24, ParagraphStyle(lineHeight: 1, paragraphSpacing: 10)).lines
        #expect(lines.map(\.graphemes.lowerBound) == [0, 3] && Self.near(lines.map(\.baseline), [19.2, 19.2 + 34]))
    }
    @Test(.disabled("waits on TE-5")) func trackingPerGrapheme() throws {
        let runs = [TextRun(start: 0, length: 4, tracking: 1)]
        #expect(try Self.lay("abcd", runs: runs, ParagraphStyle(tracking: 2)).lines.first?.x == [0, 9, 18, 27])
    }
    @Test(.disabled("waits on TE-5")) func tenThousandGraphemesLayOut() throws {
        let lines = try Self.lay(TextFixtures.longParagraph, Self.box(300)).lines
        #expect(lines.first?.graphemes.lowerBound == 0 && lines.last?.graphemes.upperBound == 10_000)
        #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.graphemes.upperBound == $1.graphemes.lowerBound })
        #expect(lines.allSatisfy { $0.width <= 300 })
    }
    @Test(.disabled("waits on TE-5")) func moreThanMaxGraphemesThrows() {
        #expect(throws: (any Error).self) { try Self.lay(String(repeating: "a", count: TextLayout.maxGraphemes + 1)) }
    }
    /// Seeded mismatched metrics, odd box widths and grapheme mixes throw or lay out inside the string.
    @Test(.disabled("waits on TE-5"), arguments: 0..<50 as Range<UInt64>) func fuzz(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let pieces = ["a", " ", "\n", "-", TextFixtures.emoji, TextFixtures.combining]
        let string = (0..<Int.random(in: 0...40, using: &rng)).map { _ in pieces.randomElement(using: &rng) ?? "" }.joined()
        let widths: [Double] = [-1, 0, .nan, .infinity, 1, 50]
        let width = widths.randomElement(using: &rng) ?? 1
        let text = TextFixtures.text(string, paragraph: ParagraphStyle(alignment: .justified, boxWidth: width))
        var measured = FixedAdvances.measure(text)
        if Bool.random(using: &rng) { measured.append(try GlyphRunMetrics(advances: [1], ascent: 1, descent: 1)) }
        guard let layout = try? TextLayout.lay(text, measured: measured) else { return }
        #expect(layout.lines.allSatisfy { $0.graphemes.upperBound <= string.count && $0.baseline.isFinite })
    }
}
