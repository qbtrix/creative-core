// PathFlatteningTests.swift: flattened polylines stay within tolerance of
// random cubics, get denser as tolerance shrinks, bad tolerances throw, and
// straight paths pass through unchanged.
import FlareCore
import Testing

@Suite struct PathFlatteningTests {
    static func randomPoint(_ rng: inout SplitMix64) -> Point {
        Point(x: Double.random(in: -100...100, using: &rng), y: Double.random(in: -100...100, using: &rng))
    }

    static func cubicPoint(_ p: [Point], _ t: Double) -> Point {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return Point(
            x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x,
            y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y
        )
    }

    /// Distance from `q` to a dense sampling of the curve, joined by segments.
    static func distance(_ q: Point, toCubic p: [Point]) -> Double {
        let n = 4096
        var best = Double.infinity
        var prev = p[0]
        for i in 1...n {
            let next = cubicPoint(p, Double(i) / Double(n))
            let dx = next.x - prev.x, dy = next.y - prev.y
            let len2 = dx * dx + dy * dy
            let t = len2 > 0 ? min(1, max(0, ((q.x - prev.x) * dx + (q.y - prev.y) * dy) / len2)) : 0
            let ex = q.x - (prev.x + t * dx), ey = q.y - (prev.y + t * dy)
            best = min(best, (ex * ex + ey * ey).squareRoot())
            prev = next
        }
        return best
    }

    @Test func segmentMidpointsAreWithinToleranceOfRandomCubics() throws {
        var rng = SplitMix64(seed: 24)
        for _ in 0..<20 {
            let p = (0..<4).map { _ in Self.randomPoint(&rng) }
            let path = Path(elements: [.move(to: p[0]), .cubic(control1: p[1], control2: p[2], to: p[3])])
            for tolerance in [1.0, 0.1, 0.01] {
                let lines = try path.flattened(tolerance: tolerance)
                #expect(lines.count == 1)
                let points = try #require(lines.first)
                #expect(points.first == p[0])
                #expect(points.last == p[3])
                for (a, b) in zip(points, points.dropFirst()) {
                    let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    #expect(Self.distance(mid, toCubic: p) <= tolerance + 1e-4)
                }
            }
        }
    }

    @Test func pointCountGrowsAsToleranceShrinks() throws {
        var rng = SplitMix64(seed: 2424)
        for _ in 0..<20 {
            let p = (0..<4).map { _ in Self.randomPoint(&rng) }
            let path = Path(elements: [.move(to: p[0]), .cubic(control1: p[1], control2: p[2], to: p[3])])
            let counts = try [10.0, 1.0, 0.1, 0.01].map { try path.flattened(tolerance: $0)[0].count }
            for (a, b) in zip(counts, counts.dropFirst()) {
                #expect(a <= b)
            }
            #expect(counts[0] < counts[3])
        }
    }

    @Test func quadIsFlattenedWithinTolerance() throws {
        let p0 = Point(x: 0, y: 0), c = Point(x: 50, y: 100), p2 = Point(x: 100, y: 0)
        let lines = try Path(elements: [.move(to: p0), .quad(control: c, to: p2)]).flattened(tolerance: 0.05)
        let points = try #require(lines.first)
        #expect(points.count > 2)
        let asCubic = [p0, Point(x: 100.0 / 3, y: 200.0 / 3), Point(x: 200.0 / 3, y: 200.0 / 3), p2]
        for (a, b) in zip(points, points.dropFirst()) {
            let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            #expect(Self.distance(mid, toCubic: asCubic) <= 0.05 + 1e-4)
        }
    }

    @Test func badToleranceThrows() {
        let path = Path(polyline: [Point(x: 0, y: 0), Point(x: 1, y: 1)], closed: false)
        for tolerance in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            #expect(throws: GeometryError.invalidTolerance) { try path.flattened(tolerance: tolerance) }
        }
    }

    @Test func linesOnlyPathComesBackUnchanged() throws {
        let a = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)]
        let b = [Point(x: 20, y: 20), Point(x: 30, y: 25)]
        let path = Path(elements: Path(polyline: a, closed: false).elements + Path(polyline: b, closed: false).elements)
        #expect(try path.flattened(tolerance: 0.1) == [a, b])
    }

    @Test func closeRepeatsFirstPointAndMoveStartsNewSubpath() throws {
        let square = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)]
        let path = Path(elements: Path(polyline: square, closed: true).elements + [.line(to: Point(x: 5, y: 5))])
        let lines = try path.flattened(tolerance: 0.1)
        #expect(lines == [square + [square[0]], [square[0], Point(x: 5, y: 5)]])
        #expect(try Path().flattened(tolerance: 0.1) == [])
    }

    @Test func nonFiniteCoordinatesDoNotHang() throws {
        let bad = Point(x: .nan, y: .infinity)
        let path = Path(elements: [.move(to: Point(x: 0, y: 0)), .cubic(control1: bad, control2: bad, to: Point(x: 1, y: 1))])
        let lines = try path.flattened(tolerance: 0.1)
        #expect(lines.count == 1)
        #expect(lines[0].count <= (1 << 16) + 1)
    }
}
