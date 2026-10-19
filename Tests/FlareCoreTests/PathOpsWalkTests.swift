// PathOpsWalkTests.swift: the path-geometry journey (KJ-PG). One 5-point star
// goes through every op in turn, each step checked against the ruler or the
// area oracle (PathArea): its contours round-trip; a point inserted halfway
// along edge 2 keeps the area; dash [10, 5] cuts pieces 10 long; trim
// 0.25...0.75 keeps half the length; a width-4 round-join outline matches the
// analytic band; and subtracting a centred circle leaves star minus circle.
import FlareCore
import Foundation
import Testing

@Suite struct PathOpsWalkTests {
    static let tolerance = 0.01

    /// Length of one flattened piece.
    static func length(_ points: [Point]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Area a closed polygon's stroke of half-width `h` covers with round
    /// joins: each edge's rectangle, plus at every vertex turning by θ the
    /// outer sector (θh²/2) less the inner overlap (h² tan(θ/2)).
    static func roundBand(_ vertices: [Point], h: Double) -> Double {
        var area = 0.0
        for (i, b) in vertices.enumerated() {
            let a = vertices[(i + vertices.count - 1) % vertices.count], c = vertices[(i + 1) % vertices.count]
            let turn = abs(atan2((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x),
                                 (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y)))
            area += 2 * h * hypot(c.x - b.x, c.y - b.y) + h * h * (turn / 2 - tan(turn / 2))
        }
        return area
    }

    @Test func walk() throws {
        let star = try PathFixtures.star()
        let tol = Self.tolerance

        // Contours round-trip: the rebuilt path draws the same points.
        let rebuilt = Path(contours: star.contours)
        let drawn = try star.flattened(tolerance: tol), redrawn = try rebuilt.flattened(tolerance: tol)
        #expect(drawn.count == redrawn.count)
        for (p, q) in zip(drawn.joined(), redrawn.joined()) { #expect(hypot(p.x - q.x, p.y - q.y) <= 1e-9) }

        // Insert at t 0.5 of edge 2: one more anchor, area and length unchanged.
        let edited = try star.inserting(at: PathLocation(element: 2, t: 0.5, point: Point(x: 0, y: 0), distance: 0))
        let starArea = abs(try PathArea.signedArea(star, tolerance: tol))
        #expect(edited.contours.first?.anchors.count == (star.contours.first?.anchors.count ?? 0) + 1)
        #expect(abs(abs(try PathArea.signedArea(edited, tolerance: tol)) - starArea) <= 1e-9)
        let total = try edited.length(tolerance: tol)
        #expect(abs(total - (try star.length(tolerance: tol))) <= 1e-9)

        // Dash [10, 5]: every piece but the last is 10 long, the last at most 10.
        let dashes = try edited.dashed([10, 5], phase: 0, tolerance: tol).flattened(tolerance: tol)
        #expect(dashes.count == Int((total / 15).rounded(.up)))
        for (i, piece) in dashes.enumerated() {
            let d = Self.length(piece)
            if i < dashes.count - 1 { #expect(abs(d - 10) <= 1e-9, "dash \(i) is \(d) long") } else { #expect(d <= 10 + 1e-9) }
        }

        // Trim 0.25...0.75 keeps half the length.
        let trimmed = try edited.trimmed(start: 0.25, end: 0.75, offset: 0, mode: .together, tolerance: tol)
        #expect(abs(try trimmed.length(tolerance: tol) - total / 2) <= 1e-9 * total)

        // Outline at width 4, round joins: the analytic band within 1%.
        let outline = try edited.outlined(width: 4, join: .round, cap: .butt, miterLimit: 4, tolerance: tol)
        let band = Self.roundBand(try #require(drawn.first).dropLast(), h: 2)
        let outlineArea = abs(try PathArea.signedArea(outline, tolerance: tol))
        #expect(abs(outlineArea - band) <= 0.01 * band, "outline \(outlineArea), band \(band)")

        // Subtract a centred circle (radius 15, inside the inner pentagon).
        let circle = try PathBuilders.ellipse(in: Rect(minX: 35, minY: 35, maxX: 65, maxY: 65))
        let holed = try Path.combine(.subtract, edited, circle, rule: .nonZero, tolerance: tol)
        let expected = starArea - abs(try PathArea.signedArea(circle, tolerance: tol))
        let holedArea = abs(try PathArea.signedArea(holed, tolerance: tol))
        #expect(abs(holedArea - expected) <= 0.005 * expected, "star − circle \(holedArea), expected \(expected)")
        print("walk: star \(starArea), length \(total), dashes \(dashes.count), outline \(outlineArea) (band \(band)), star − circle \(holedArea)")
    }
}
