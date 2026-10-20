// TextOnPathTests.swift: TE-6's acceptance checks for `TextLayout.onPath` on
// `FixedAdvances` (12 pt text advances 6 per grapheme).
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
    /// The circle of radius 50 about (50, 50) as 32 cubic arcs, whose normals
    /// are radial within about 4e-8; the four-arc ellipse's are off by 1.3e-3.
    static func circle() -> Path {
        let n = 32, r = 50.0, step = 2 * Double.pi / Double(n), k = 4.0 / 3.0 * tan(step / 4) * r
        func at(_ a: Double) -> Point { Point(x: 50 + r * cos(a), y: 50 + r * sin(a)) }
        var elements: [PathElement] = [.move(to: at(0))]
        for i in 0..<n {
            let a0 = Double(i) * step, a1 = a0 + step, p0 = at(a0), p1 = at(a1)
            elements.append(.cubic(control1: Point(x: p0.x - k * sin(a0), y: p0.y + k * cos(a0)),
                                   control2: Point(x: p1.x + k * sin(a1), y: p1.y - k * cos(a1)), to: p1))
        }
        return Path(elements: elements + [.close])
    }
    @Test func glyphCentredOnPath() throws {
        let glyphs = try Self.place("ab", offset: 0.25)
        #expect(glyphs.map(\.index) == [0, 1] && glyphs.allSatisfy { abs($0.degrees) < 1e-9 })
        #expect(Self.near(glyphs.map(\.position), [Point(x: 25, y: 0), Point(x: 31, y: 0)]))
    }
    @Test func tangentPerpendicularToRadiusOnACircle() throws {
        let glyphs = try Self.place("Bring the light", on: Self.circle(), offset: 0.1)
        #expect(glyphs.count == 15)
        for glyph in glyphs {
            let radians: Double = glyph.degrees * Double.pi / 180
            let tx: Double = cos(radians), ty: Double = sin(radians)
            let cx: Double = glyph.position.x + 3 * tx - 50, cy: Double = glyph.position.y + 3 * ty - 50
            let cosine: Double = (tx * cx + ty * cy) / (cx * cx + cy * cy).squareRoot()
            #expect(Swift.abs(cosine) < 1e-6, "\(glyph)")
        }
    }
    @Test func flipReverses() throws {
        let glyphs = try Self.place("ab", offset: 0.25, flipped: true)
        #expect(Self.near(glyphs.map(\.position), [Point(x: 75, y: 0), Point(x: 69, y: 0)]))
        #expect(glyphs.allSatisfy { abs(abs($0.degrees) - 180) < 1e-9 })
    }
    /// Centres at 53, 59, ... : the ninth, at 101, falls past the end.
    @Test func pastTheEndNotPlaced() throws {
        #expect(try Self.place("abcdefghij", offset: 0.5).map(\.index) == Array(0..<8))
    }
    @Test func closedPathWraps() throws {
        let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100), Point(x: 0, y: 100)],
                          closed: true)
        let glyphs = try Self.place("abcdefghij", on: square, offset: 0.95)
        #expect(glyphs.map(\.index) == Array(0..<10))
        #expect(Self.near(glyphs.suffix(1).map(\.position), [Point(x: 34, y: 0)]))
    }
    @Test func badInputThrows() {
        #expect(throws: (any Error).self) { try Self.place(String(repeating: "a", count: TextLayout.maxGraphemes + 1), offset: 0) }
        let text = TextFixtures.text(onPath: TextOnPath(path: Self.line))
        #expect(throws: (any Error).self) { try TextLayout.onPath(text, measured: [], tolerance: 0.01) }
        #expect(throws: (any Error).self) { try TextLayout.onPath(text, measured: FixedAdvances.measure(text), tolerance: .nan) }
        #expect(throws: (any Error).self) { try Self.place("ab", offset: .nan) }
        let bad = Path(polyline: [Point(x: 0, y: 0), Point(x: .infinity, y: 0)], closed: false)
        #expect(throws: (any Error).self) { try Self.place("ab", on: bad, offset: 0) }
        let plain = TextFixtures.text("ab")
        #expect(throws: (any Error).self) { try TextLayout.onPath(plain, measured: FixedAdvances.measure(plain), tolerance: 0.01) }
    }
}
