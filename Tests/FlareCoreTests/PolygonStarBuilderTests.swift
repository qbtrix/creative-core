// PolygonStarBuilderTests.swift: PathBuilders.polygon and star put their
// vertices on the inscribed ellipse (inner star vertices at the ratio), start
// at the top centre, run clockwise on screen, and throw on bad counts, ratios
// and rects instead of trapping.
import FlareCore
import Testing

@Suite struct PolygonStarBuilderTests {
    static let rect = Rect(minX: 10, minY: 20, maxX: 210, maxY: 120)
    static let (cx, cy, rx, ry) = (110.0, 70.0, 100.0, 50.0)

    /// The vertices of a move + lines + close path; records an issue on any
    /// other shape.
    static func vertices(_ path: Path) -> [Point] {
        var points: [Point] = []
        for (i, element) in path.elements.enumerated() {
            switch element {
            case .move(let p) where i == 0: points.append(p)
            case .line(let p) where i > 0: points.append(p)
            case .close where i == path.elements.count - 1: break
            default: Issue.record("unexpected element \(element) at \(i)")
            }
        }
        #expect(path.elements.last == .close)
        return points
    }

    /// ((x - cx) / rx)² + ((y - cy) / ry)², 1 on the inscribed ellipse.
    static func ellipseValue(_ p: Point, scale: Double = 1) -> Double {
        let dx = (p.x - cx) / (rx * scale)
        let dy = (p.y - cy) / (ry * scale)
        return dx * dx + dy * dy
    }

    /// Twice the signed area in y-down coordinates: positive is clockwise on screen.
    static func signedArea(_ points: [Point]) -> Double {
        var sum = 0.0
        for (i, p) in points.enumerated() {
            let q = points[(i + 1) % points.count]
            sum += p.x * q.y - q.x * p.y
        }
        return sum
    }

    @Test func hexagonVerticesOnInscribedEllipse() throws {
        let points = Self.vertices(try PathBuilders.polygon(in: Self.rect, sides: 6))
        #expect(points.count == 6)
        for p in points {
            #expect(abs(Self.ellipseValue(p) - 1) <= 1e-9)
        }
        let first = try #require(points.first)
        #expect(abs(first.x - Self.cx) <= 1e-9)
        #expect(abs(first.y - Self.rect.minY) <= 1e-9)
    }

    @Test func polygonRunsClockwiseOnScreen() throws {
        let points = Self.vertices(try PathBuilders.polygon(in: Self.rect, sides: 5))
        #expect(Self.signedArea(points) > 0)
        // The second vertex is right of centre and above it (y down).
        #expect(points[1].x > Self.cx)
        #expect(points[1].y < Self.cy)
    }

    @Test(arguments: [Int.min, -1, 0, 1, 2, PathBuilders.maxSides + 1, Int.max])
    func badSideCountsThrow(_ count: Int) {
        #expect(throws: GeometryError.invalidSides) { try PathBuilders.polygon(in: Self.rect, sides: count) }
        #expect(throws: GeometryError.invalidSides) {
            try PathBuilders.star(in: Self.rect, points: count, innerRatio: 0.5)
        }
    }

    @Test func sideCountCapIsAccepted() throws {
        let polygon = try PathBuilders.polygon(in: Self.rect, sides: PathBuilders.maxSides)
        #expect(Self.vertices(polygon).count == PathBuilders.maxSides)
        let star = try PathBuilders.star(in: Self.rect, points: PathBuilders.maxSides, innerRatio: 1)
        #expect(Self.vertices(star).count == 2 * PathBuilders.maxSides)
    }

    @Test func fivePointStarAlternatesOuterAndInner() throws {
        let points = Self.vertices(try PathBuilders.star(in: Self.rect, points: 5, innerRatio: 0.5))
        #expect(points.count == 10)
        for (k, p) in points.enumerated() {
            let scale = k.isMultiple(of: 2) ? 1.0 : 0.5
            #expect(abs(Self.ellipseValue(p, scale: scale) - 1) <= 1e-9)
        }
        let first = try #require(points.first)
        #expect(abs(first.x - Self.cx) <= 1e-9)
        #expect(abs(first.y - Self.rect.minY) <= 1e-9)
        #expect(Self.signedArea(points) > 0)
        // On a circle the inner radius is exactly half the outer one.
        let square = Rect(minX: -50, minY: -50, maxX: 50, maxY: 50)
        let circle = Self.vertices(try PathBuilders.star(in: square, points: 5, innerRatio: 0.5))
        for (k, p) in circle.enumerated() {
            let r = (p.x * p.x + p.y * p.y).squareRoot()
            #expect(abs(r - (k.isMultiple(of: 2) ? 50 : 25)) <= 1e-9)
        }
    }

    @Test(arguments: [0.0, -0.5, 1.5, 1.0000001])
    func finiteRatioOutsideRangeThrowsInvalidSides(_ ratio: Double) {
        #expect(throws: GeometryError.invalidSides) {
            try PathBuilders.star(in: Self.rect, points: 5, innerRatio: ratio)
        }
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteRatioThrowsNonFinite(_ ratio: Double) {
        #expect(throws: GeometryError.nonFinite) {
            try PathBuilders.star(in: Self.rect, points: 5, innerRatio: ratio)
        }
    }

    @Test func nonFiniteRectThrowsNonFinite() {
        let bad = Rect(minX: .nan, minY: 0, maxX: 10, maxY: 10)
        #expect(throws: GeometryError.nonFinite) { try PathBuilders.polygon(in: bad, sides: 6) }
        #expect(throws: GeometryError.nonFinite) { try PathBuilders.star(in: bad, points: 5, innerRatio: 0.5) }
    }

    @Test func seededFuzzNeverTraps() {
        var rng = SplitMix64(seed: 0x5617)
        let specials: [Double] = [.nan, .infinity, -.infinity, 0, -0.0, .greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        func value() -> Double {
            Int.random(in: 0..<8, using: &rng) == 0
                ? specials[Int.random(in: 0..<specials.count, using: &rng)]
                : Double.random(in: -1e6...1e6, using: &rng)
        }
        for _ in 0..<1_000 {
            let rect = Rect(minX: value(), minY: value(), maxX: value(), maxY: value())
            let count = Int.random(in: -5...1_100, using: &rng)
            let ratio = Int.random(in: 0..<2, using: &rng) == 0 ? value() : Double.random(in: -0.5...1.5, using: &rng)
            for build in [{ try PathBuilders.polygon(in: rect, sides: count) },
                          { try PathBuilders.star(in: rect, points: count, innerRatio: ratio) }] {
                do {
                    let path = try build()
                    for p in Self.vertices(path) {
                        #expect(p.x.isFinite && p.y.isFinite)
                    }
                } catch {
                    #expect(error is GeometryError)
                }
            }
        }
    }
}
