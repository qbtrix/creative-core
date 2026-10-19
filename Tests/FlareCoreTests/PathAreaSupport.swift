// PathAreaSupport.swift: area oracles for the outline and boolean checks.
// `signedArea` is the shoelace area of the flattened path; `sampledArea` and
// `insideCount` count seeded or grid points that `Shape.contains` (HitTest)
// puts inside. PathAreaSupportTests checks both against ShapeBounds.
import FlareCore
import Testing

enum PathArea {
    /// Sum of the shoelace areas of every flattened subpath, each closed back
    /// to its first point. Positive when the subpath runs x toward y (clockwise
    /// on screen, where y points down).
    static func signedArea(_ path: Path, tolerance: Double = 1e-3) throws -> Double {
        var total = 0.0
        for polyline in try path.flattened(tolerance: tolerance) {
            guard var a = polyline.last else { continue }
            for b in polyline {
                total += a.x * b.y - b.x * a.y
                a = b
            }
        }
        return total / 2
    }

    /// Whether HitTest puts `p` in the fill of `path` under `rule`.
    static func contains(_ path: Path, _ p: Point, rule: FillRule) -> Bool {
        Shape(points: [], path: path).contains(p, rule: rule)
    }

    /// Filled area of `path` under `rule`, by HitTest at the centres of an
    /// n × n grid over `rect`.
    static func sampledArea(_ path: Path, rule: FillRule, in rect: Rect, grid n: Int = 200) -> Double {
        let dx = rect.width / Double(n), dy = rect.height / Double(n)
        var inside = 0
        for i in 0..<n {
            for j in 0..<n {
                let p = Point(x: rect.minX + (Double(i) + 0.5) * dx, y: rect.minY + (Double(j) + 0.5) * dy)
                if contains(path, p, rule: rule) { inside += 1 }
            }
        }
        return Double(inside) * dx * dy
    }

    /// `count` points drawn uniformly from `rect` with `rng`.
    static func points(in rect: Rect, count: Int, rng: inout SplitMix64) -> [Point] {
        (0..<count).map { _ in
            Point(x: Double.random(in: rect.minX...rect.maxX, using: &rng),
                  y: Double.random(in: rect.minY...rect.maxY, using: &rng))
        }
    }
}

@Suite struct PathAreaSupportTests {
    static let box = Rect(minX: 10, minY: 20, maxX: 110, maxY: 70)

    @Test func rectangleAreaIsItsBoundsArea() throws {
        let path = try PathBuilders.rectangle(in: Self.box)
        let bounds = try #require(path.bounds)
        let area = bounds.width * bounds.height
        #expect(abs(abs(try PathArea.signedArea(path)) - area) < 1e-9)
        #expect(abs(PathArea.sampledArea(path, rule: .nonZero, in: bounds, grid: 100) - area) < 1e-6)
    }

    @Test func ellipseAreaIsAQuarterPiOfItsBounds() throws {
        let path = try PathBuilders.ellipse(in: Self.box)
        let bounds = try #require(path.bounds)
        let expected = Double.pi * bounds.width * bounds.height / 4
        #expect(abs(abs(try PathArea.signedArea(path)) - expected) / expected < 1e-3)
        #expect(abs(PathArea.sampledArea(path, rule: .evenOdd, in: bounds) - expected) / expected < 1e-2)
    }

    @Test func reversingAPathFlipsTheSign() throws {
        let points = [Point(x: 0, y: 0), Point(x: 4, y: 0), Point(x: 4, y: 3)]
        let forward = try PathArea.signedArea(Path(polyline: points, closed: true))
        let backward = try PathArea.signedArea(Path(polyline: points.reversed(), closed: true))
        #expect(forward == 6)
        #expect(backward == -6)
    }

    @Test func starSamplesAgreeWithShoelaceAndStayInBounds() throws {
        let path = try PathBuilders.star(in: Self.box, points: 5, innerRatio: 0.5)
        let bounds = try #require(path.bounds)
        let shoelace = abs(try PathArea.signedArea(path))
        #expect(abs(PathArea.sampledArea(path, rule: .nonZero, in: bounds) - shoelace) / shoelace < 1e-2)
        var rng = SplitMix64(seed: 7)
        let wide = Rect(minX: bounds.minX - 50, minY: bounds.minY - 50, maxX: bounds.maxX + 50, maxY: bounds.maxY + 50)
        for p in PathArea.points(in: wide, count: 500, rng: &rng) where PathArea.contains(path, p, rule: .nonZero) {
            #expect(p.x >= bounds.minX && p.x <= bounds.maxX && p.y >= bounds.minY && p.y <= bounds.maxY)
        }
    }
}
