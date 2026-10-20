// PathOutlineTests.swift: Path.outlined turns a stroke into a fillable path
// whose area is the stroked area, for every join and cap (PathArea shoelace
// oracle; combine's outers run counter-clockwise, so area is minus signed area).
@testable import FlareCore
import Foundation
import Testing

@Suite struct PathOutlineTests {
    static let line = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0)], closed: false)
    /// Right, down, right: one turn each way, both 90°.
    static let zigzag = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100),
                                        Point(x: 200, y: 100)], closed: false)
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 100),
                                        Point(x: 0, y: 100)], closed: true)

    static func area(_ path: Path, width: Double = 10, join: Stroke.Join = .miter, cap: Stroke.Cap = .butt,
                     miterLimit: Double = 4) throws -> Double {
        let outline = try path.outlined(width: width, join: join, cap: cap, miterLimit: miterLimit, tolerance: 0.01)
        return -(try PathArea.signedArea(outline))
    }

    static func near(_ value: Double, _ expected: Double, _ relative: Double) -> Bool {
        abs(value - expected) <= relative * abs(expected)
    }

    @Test func buttCapIsTheBand() throws {
        #expect(Self.near(try Self.area(Self.line, cap: .butt), 1_000, 1e-9))
    }

    @Test func squareCapAddsHalf() throws {
        #expect(Self.near(try Self.area(Self.line, cap: .square), 1_100, 1e-9))
    }

    @Test func roundCapAddsADisk() throws {
        // Chords within 0.01 of the arc: inscribed, so a little under the disk.
        let area = try Self.area(Self.line, cap: .round)
        #expect(Self.near(area, 1_000 + 25 * Double.pi, 5e-4) && area <= 1_000 + 25 * Double.pi)
    }

    @Test func roundJoinArea() throws {
        // Two 90° corners: each loses the h × h inner overlap and gains its join
        // in the h × h outer gap (h = 5).
        let band = 300.0 * 10 - 2 * 25
        #expect(Self.near(try Self.area(Self.zigzag, join: .round), band + 2 * 25 * Double.pi / 4, 1e-4))
        #expect(Self.near(try Self.area(Self.zigzag, join: .bevel), band + 2 * 12.5, 1e-9))
        #expect(Self.near(try Self.area(Self.zigzag, join: .miter), band + 2 * 25, 1e-9))
        // Drawn backwards, the turns swap direction and the area stays.
        let reversed = Path(polyline: [Point(x: 200, y: 100), Point(x: 100, y: 100), Point(x: 100, y: 0),
                                       Point(x: 0, y: 0)], closed: false)
        #expect(Self.near(try Self.area(reversed, join: .round), band + 2 * 25 * Double.pi / 4, 1e-4))
    }

    @Test func miterLimitBevels() throws {
        // A 10° zig: the miter is h / sin(5°) ≈ 11.47 h long.
        let back = Point(x: 100 - 100 * cos(10 * Double.pi / 180), y: 100 * sin(10 * Double.pi / 180))
        let zig = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), back], closed: false)
        let bevel = try Self.area(zig, join: .bevel)
        #expect(Self.near(try Self.area(zig, join: .miter, miterLimit: 4), bevel, 1e-9))
        #expect(Self.near(try Self.area(zig, join: .miter, miterLimit: 11), bevel, 1e-9))
        // The miter adds the triangle past the bevel: h² sin³(θ/2) / cos(θ/2), θ = 170°.
        let half = 85 * Double.pi / 180
        let tip = 25 * pow(sin(half), 3) / cos(half)
        #expect(Self.near(try Self.area(zig, join: .miter, miterLimit: 12) - bevel, tip, 1e-6))
        #expect(Self.near(try Self.area(zig, join: .miter, miterLimit: 40) - bevel, tip, 1e-6))
    }

    @Test func shortLegInnerJoinPivots() throws {
        // A 150° turn onto a 4-long leg: the inner offsets cross ≈ 18.7 past the
        // vertex, beyond half the short leg, so the inner side pivots through it.
        let (c, s) = (cos(Double.pi / 6), sin(Double.pi / 6))
        let end = Point(x: 100 - 4 * c, y: 4 * s)
        let path = Path(polyline: [Point(x: 0, y: 0), Point(x: 100, y: 0), end], closed: false)
        // Oracle: the two butt bands and the bevel triangle on the outer side, unioned.
        let first = Path(polyline: [Point(x: 0, y: -5), Point(x: 100, y: -5), Point(x: 100, y: 5), Point(x: 0, y: 5)],
                         closed: true)
        let n = Point(x: 5 * s, y: 5 * c)
        let second = Path(polyline: [Point(x: 100 + n.x, y: n.y), Point(x: end.x + n.x, y: end.y + n.y),
                                     Point(x: end.x - n.x, y: end.y - n.y), Point(x: 100 - n.x, y: -n.y)], closed: true)
        let bevel = Path(polyline: [Point(x: 100, y: 0), Point(x: 100, y: -5), Point(x: 100 + n.x, y: n.y)], closed: true)
        let bands = try Path.combine(.union, first, second, rule: .nonZero, tolerance: 0.01)
        let expected = abs(try PathArea.signedArea(Path.combine(.union, bands, bevel, rule: .nonZero, tolerance: 0.01)))
        #expect(Self.near(try Self.area(path, join: .bevel), expected, 1e-6))
    }

    @Test func roundJoinsPastTheVertexCapThrowEarly() throws {
        // Round joins at a huge width and a fine tolerance take the most arc
        // points per corner (4096); 100 right-angle corners pass
        // maxBooleanVertices on the way, so the stroker stops there instead of
        // building every loop and leaving the count to combine (which throws
        // the same error, so the loops are checked before combine runs).
        let points = (0..<101).map { (k: Int) -> Point in
            let (x, y): (Int, Int) = ((k + 1) / 2 * 10, k / 2 * 10)
            return Point(x: Double(x), y: Double(y))
        }
        let path = Path(polyline: points, closed: false)
        #expect(throws: GeometryError.tooComplex(Path.maxBooleanVertices)) {
            try path.strokeLoops(width: 1e7, join: .round, cap: .round, miterLimit: 4, tolerance: 0.01)
        }
        #expect(throws: GeometryError.tooComplex(Path.maxBooleanVertices)) {
            try path.outlined(width: 1e7, join: .round, cap: .round, miterLimit: 4, tolerance: 0.01)
        }
    }

    @Test func outlineAtTheVertexCapIsAccepted() throws {
        // A closed convex n-gon with bevel joins strokes to two rings: 2 points
        // per vertex on the outer side, 1 on the inner, plus each ring's repeated
        // start, 3n + 2 as combine counts them. n = 66,666 lands exactly on
        // maxBooleanVertices; one more vertex is past it. (combine itself would
        // stop such a ring pair at maxBooleanWork, so the loops are checked.)
        let gon = { (n: Int) in Path(polyline: (0..<n).map { k in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return Point(x: 10_000 * cos(a), y: 10_000 * sin(a))
        }, closed: true) }
        let stroke = { (path: Path) in
            try path.strokeLoops(width: 10, join: .bevel, cap: .butt, miterLimit: 4, tolerance: 0.1)
        }
        var count = 0
        _ = try stroke(gon(66_666)).forEachFlattenedPoint(tolerance: 0.1) { _, _ in count += 1; return false }
        #expect(count == Path.maxBooleanVertices)
        #expect(throws: GeometryError.tooComplex(Path.maxBooleanVertices)) { try stroke(gon(66_667)) }
        // A straight open line of n points with butt caps is one loop of 2n:
        // n = 100,000 fills the cap only before its repeated start is counted.
        let line = Path(polyline: (0..<100_000).map { Point(x: Double($0), y: 0) }, closed: false)
        #expect(throws: GeometryError.tooComplex(Path.maxBooleanVertices)) { try stroke(line) }
    }

    @Test func closedSquareIsARing() throws {
        let ring = try Self.square.outlined(width: 10, join: .miter, cap: .round, miterLimit: 4, tolerance: 0.01)
        let contours = try ring.flattened(tolerance: 0.01)
        #expect(contours.count == 2)
        #expect(Self.near(try Self.area(Self.square, join: .miter, cap: .round), 110 * 110 - 90 * 90, 1e-9))
        #expect(Self.near(try Self.area(Self.square, join: .bevel), 4_000 - 4 * 12.5, 1e-9))
        #expect(Self.near(try Self.area(Self.square, join: .round), 4_000 - 4 * (25 - 25 * Double.pi / 4), 1e-4))
    }

    @Test func circleOutlineIsAnAnnulus() throws {
        let circle = try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100))
        let area = try circle.outlined(width: 10, join: .round, cap: .butt, miterLimit: 4, tolerance: 0.001)
        #expect(try area.flattened(tolerance: 0.001).count == 2)
        #expect(Self.near(-(try PathArea.signedArea(area)), 20 * Double.pi * 50, 2e-3))
    }

    @Test func emptyAndSinglePointPathsOutlineToNothing() throws {
        #expect(try Path().outlined(width: 4, join: .round, cap: .round, miterLimit: 4, tolerance: 0.1).elements.isEmpty)
        let dot = Path(polyline: [Point(x: 3, y: 3), Point(x: 3, y: 3)], closed: false)
        #expect(try dot.outlined(width: 4, join: .round, cap: .square, miterLimit: 4, tolerance: 0.1).elements.isEmpty)
    }

    @Test(arguments: [(0, GeometryError.invalidStroke), (-1, .invalidStroke), (.nan, .nonFinite),
                      (.infinity, .nonFinite)])
    func badWidthThrows(_ width: Double, _ error: GeometryError) {
        #expect(throws: error) {
            try Self.line.outlined(width: width, join: .miter, cap: .butt, miterLimit: 4, tolerance: 0.1)
        }
    }

    @Test func badMiterLimitAndToleranceThrow() {
        for (limit, error) in [(Double.nan, GeometryError.nonFinite), (0, .invalidStroke), (-1, .invalidStroke)] {
            #expect(throws: error) {
                try Self.line.outlined(width: 4, join: .miter, cap: .butt, miterLimit: limit, tolerance: 0.1)
            }
        }
        #expect(throws: GeometryError.invalidTolerance) {
            try Self.line.outlined(width: 4, join: .miter, cap: .butt, miterLimit: 4, tolerance: 0)
        }
    }

    @Test func seededPolylinesStayWithinTheirBound() throws {
        // Union of disks along the path: never more than length × w + π h².
        var rng = SplitMix64(seed: 430)
        for _ in 0..<40 {
            let points = (0..<6).map { _ in
                Point(x: Double.random(in: 0...100, using: &rng), y: Double.random(in: 0...100, using: &rng))
            }
            let length = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
            let area = try Self.area(Path(polyline: points, closed: false), width: 6, join: .round, cap: .round)
            #expect(area > 0 && area <= length * 6 + 9 * Double.pi + 1e-6)
        }
    }
}
