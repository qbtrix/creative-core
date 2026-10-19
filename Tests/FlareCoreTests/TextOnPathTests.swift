// TextOnPathTests.swift: TE-6's acceptance checks for `TextLayout.onPath` on
// `FixedAdvances` (12 pt text advances 6 per grapheme). Each case waits,
// disabled by name, until TE-6 builds `onPath` and removes the trait.
import FlareCore
import Foundation
import Testing

@Suite struct TextOnPathTests {
    /// The straight line from (0, 0) to (100, 0).
    static let line = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false)

    /// `string` in 12 pt on `path` from `offset`, placed on its fixed advances.
    static func place(_ string: String, on path: Path = line, offset: Double,
                      flipped: Bool = false) throws -> [PlacedGlyph] {
        var text = TextFixtures.text(string, onPath: TextOnPath(path: path, startOffset: offset, flipped: flipped))
        text.fontSize = 12
        return try TextLayout.onPath(text, measured: FixedAdvances.measure(text), tolerance: 0.01)
    }
    /// Same count, and each point within 1e-9 on both axes.
    static func near(_ a: [Point], _ b: [Point]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 }
    }
    @Test(.disabled("waits on TE-6")) func glyphCentredOnPath() throws {
        let glyphs = try Self.place("ab", offset: 0.25)
        #expect(glyphs.map(\.index) == [0, 1] && glyphs.allSatisfy { abs($0.degrees) < 1e-9 })
        #expect(Self.near(glyphs.map(\.position), [Point(x: 25, y: 0), Point(x: 31, y: 0)]))
    }
    @Test(.disabled("waits on TE-6")) func tangentPerpendicularToRadiusOnACircle() throws {
        let circle = try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100))
        let glyphs = try Self.place("Bring the light", on: circle, offset: 0.1)
        #expect(glyphs.count == 15)
        for glyph in glyphs {
            let radians: Double = glyph.degrees * Double.pi / 180
            let tx: Double = cos(radians), ty: Double = sin(radians)
            let cx: Double = glyph.position.x + 3 * tx - 50, cy: Double = glyph.position.y + 3 * ty - 50
            let cosine: Double = (tx * cx + ty * cy) / (cx * cx + cy * cy).squareRoot()
            // Within 1e-3: the four cubics only approximate a circle.
            #expect(Swift.abs(cosine) < 1e-3, "\(glyph)")
        }
    }
    @Test(.disabled("waits on TE-6")) func flipReverses() throws {
        let glyphs = try Self.place("ab", offset: 0.25, flipped: true)
        #expect(Self.near(glyphs.map(\.position), [Point(x: 75, y: 0), Point(x: 69, y: 0)]))
        #expect(glyphs.allSatisfy { abs(abs($0.degrees) - 180) < 1e-9 })
    }
    /// Centres at 53, 59, ... : the ninth, at 101, falls past the end.
    @Test(.disabled("waits on TE-6")) func pastTheEndNotPlaced() throws {
        #expect(try Self.place("abcdefghij", offset: 0.5).map(\.index) == Array(0..<8))
    }
    @Test(.disabled("waits on TE-6")) func closedPathWraps() throws {
        let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100), Point(x: 0, y: 100)],
                          closed: true)
        let glyphs = try Self.place("abcdefghij", on: square, offset: 0.95)
        #expect(glyphs.map(\.index) == Array(0..<10))
        #expect(Self.near(glyphs.suffix(1).map(\.position), [Point(x: 34, y: 0)]))
    }
    @Test(.disabled("waits on TE-6")) func badInputThrows() {
        #expect(throws: (any Error).self) { try Self.place(String(repeating: "a", count: TextLayout.maxGraphemes + 1), offset: 0) }
        let text = TextFixtures.text(onPath: TextOnPath(path: Self.line))
        #expect(throws: (any Error).self) { try TextLayout.onPath(text, measured: [], tolerance: 0.01) }
        #expect(throws: (any Error).self) { try TextLayout.onPath(text, measured: FixedAdvances.measure(text), tolerance: .nan) }
    }
}
