// PathFlatteningTests.swift: Path.flattened(tolerance:) stays within tolerance
// of random cubics, refines as tolerance shrinks, rejects bad tolerances and
// leaves straight paths alone.
import FlareCore
import Testing

@Suite struct PathFlatteningTests {
    static func random(_ rng: inout SplitMix64) -> Point {
        Point(x: Double.random(in: -200...200, using: &rng), y: Double.random(in: -200...200, using: &rng))
    }

    static func cubicAt(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point, _ t: Double) -> Point {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        return Point(
            x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
            y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y
        )
    }

    static func distance(_ a: Point, _ b: Point) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    @Test func randomCubicSegmentMidpointsAreWithinTolerance() throws {
        var rng = SplitMix64(seed: 24)
        for _ in 0..<200 {
            let (p0, p1, p2, p3) = (Self.random(&rng), Self.random(&rng), Self.random(&rng), Self.random(&rng))
            let tolerance = Double.random(in: 0.01...5, using: &rng)
            let path = Path(elements: [.move(to: p0), .cubic(control1: p1, control2: p2, to: p3)])
            let lines = try path.flattened(tolerance: tolerance)
            #expect(lines.count == 1)
            let points = lines[0]
            #expect(points.first == p0)
            #expect(points.last == p3)
            let n = points.count - 1
            #expect(n >= 1)
            // Midpoint of each chord vs the curve at the mid parameter.
            for i in 0..<n {
                let a = points[i], b = points[i + 1]
                let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                let onCurve = Self.cubicAt(p0, p1, p2, p3, (Double(i) + 0.5) / Double(n))
                #expect(Self.distance(mid, onCurve) <= tolerance * (1 + 1e-9))
            }
        }
    }

    @Test func pointCountGrowsAsToleranceShrinks() throws {
        var rng = SplitMix64(seed: 7)
        for _ in 0..<50 {
            let path = Path(elements: [
                .move(to: Self.random(&rng)),
                .cubic(control1: Self.random(&rng), control2: Self.random(&rng), to: Self.random(&rng)),
            ])
            var previous = 0
            for tolerance in [10.0, 1, 0.1, 0.01] {
                let count = try path.flattened(tolerance: tolerance)[0].count
                #expect(count >= previous)
                previous = count
            }
            let coarse = try path.flattened(tolerance: 10)[0].count
            let fine = try path.flattened(tolerance: 0.01)[0].count
            #expect(fine > coarse)
        }
    }

    @Test func badTolerancesThrow() {
        let path = PathTests.everyKind
        for tolerance in [0, -1, Double.nan, .infinity, -.infinity] {
            #expect(throws: GeometryError.invalidTolerance) { try path.flattened(tolerance: tolerance) }
        }
    }

    @Test func linesComeBackUnchanged() throws {
        let points = [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 3, y: 7)]
        #expect(try Path(polyline: points, closed: false).flattened(tolerance: 0.5) == [points])
        #expect(try Path(polyline: points, closed: true).flattened(tolerance: 0.5) == [points + [points[0]]])
    }

    @Test func eachMoveStartsANewPolyline() throws {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)), .line(to: Point(x: 1, y: 0)), .close,
            .line(to: Point(x: 0, y: 1)),
            .move(to: Point(x: 5, y: 5)),
            .quad(control: Point(x: 6, y: 8), to: Point(x: 7, y: 5)),
        ])
        let lines = try path.flattened(tolerance: 0.1)
        #expect(lines.count == 3)
        #expect(lines[0] == [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 0, y: 0)])
        #expect(lines[1] == [Point(x: 0, y: 0), Point(x: 0, y: 1)])
        #expect(lines[2].first == Point(x: 5, y: 5))
        #expect(lines[2].last == Point(x: 7, y: 5))
        #expect(lines[2].count > 2)
    }

    @Test func degenerateInputDoesNotCrash() throws {
        var rng = SplitMix64(seed: 99)
        let specials: [Double] = [.nan, .infinity, -.infinity, 1e308, -1e308, 0]
        for _ in 0..<200 {
            func value() -> Double {
                Bool.random(using: &rng) ? specials[Int.random(in: 0..<specials.count, using: &rng)]
                    : Double.random(in: -1e6...1e6, using: &rng)
            }
            func point() -> Point { Point(x: value(), y: value()) }
            let path = Path(elements: [
                .quad(control: point(), to: point()),
                .cubic(control1: point(), control2: point(), to: point()),
                .close, .close,
            ])
            let lines = try path.flattened(tolerance: 1e-9)
            for line in lines {
                #expect(line.count <= 1 + 2 * Path.maxFlattenSegments)
            }
        }
        #expect(try Path().flattened(tolerance: 1) == [])
    }
}
