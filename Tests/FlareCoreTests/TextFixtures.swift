// TextFixtures.swift: shared strings and shapes for the text-engine checks
// (TE-2): Latin, emoji, combining marks and a 10,000-grapheme paragraph, plus
// a document holding one text shape on the ball layer.
import FlareCore
import Testing

enum TextFixtures {
    static let latin = "Bring the light"
    /// Three graphemes: a toned thumbs-up, a family (ZWJ sequence) and a flag.
    static let emoji = "👍🏽👨‍👩‍👧🇳🇵"
    /// Three graphemes, each a base letter plus combining marks.
    static let combining = "e\u{301}a\u{308}\u{304}n\u{303}"
    /// 10,000 graphemes: "word " repeated, so it wraps at every fifth.
    static let longParagraph = String(repeating: "word ", count: 2_000)

    /// A 24 pt Inter text shape at the origin.
    static func text(_ string: String = latin, runs: [TextRun] = [], paragraph: ParagraphStyle? = nil,
                     onPath: TextOnPath? = nil) -> TextShape {
        TextShape(string: string, fontFamily: "Inter", fontSize: 24, position: Point(x: 0, y: 0),
                  runs: runs, paragraph: paragraph, onPath: onPath)
    }

    /// `Fixtures.document()` with `text` as the ball layer's only text.
    static func document(_ text: TextShape = text()) -> Document {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].texts = [text]
        return doc
    }

    /// The text at index 0 of the ball layer, if any.
    static func ballText(_ doc: Document) -> TextShape? { doc.scenes.first?.layers.last?.texts.first }
}

@Suite struct TextFixturesTests {
    @Test func fixturesCountGraphemes() {
        #expect(TextFixtures.latin.count == 15)
        #expect(TextFixtures.emoji.count == 3 && TextFixtures.emoji.utf16.count > 3)
        #expect(TextFixtures.combining.count == 3 && TextFixtures.combining.unicodeScalars.count == 7)
        #expect(TextFixtures.longParagraph.count == 10_000)
        #expect(TextFixtures.text(TextFixtures.longParagraph).resolvedRuns.map(\.length) == [10_000])
        #expect(TextFixtures.ballText(TextFixtures.document()) == TextFixtures.text())
    }
}
