// PathBooleanTests.swift: Path.combine on squares with known areas (PathArea
// shoelace oracle; outers run counter-clockwise, so area is minus signed area).
import Foundation
@testable import FlareCore
import Testing

@Suite struct PathBooleanTests {
    static func square(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Path {
        Path(polyline: [Point(x: x0, y: y0), Point(x: x1, y: y0), Point(x: x1, y: y1), Point(x: x0, y: y1)], closed: true)
    }

    static let a = square(0, 0, 10, 10), b = square(5, 5, 15, 15)

    static func area(_ op: BooleanOp, _ a: Path, _ b: Path, rule: FillRule = .nonZero) throws -> Double {
        -(try PathArea.signedArea(Path.combine(op, a, b, rule: rule, tolerance: 0.01)))
    }

    static func contourAreas(_ path: Path) throws -> [Double] {
        try path.flattened(tolerance: 0.01).map { try PathArea.signedArea(Path(polyline: $0, closed: true)) }.sorted()
    }

    @Test(arguments: zip([BooleanOp.union, .intersect, .subtract, .exclude], [175.0, 25, 75, 150]))
    func overlappingSquaresAreasAreExact(_ op: BooleanOp, _ expected: Double) throws {
        #expect(abs(try Self.area(op, Self.a, Self.b) - expected) < 1e-9)
        #expect(abs(try Self.area(op, Self.a, Self.b, rule: .evenOdd) - expected) < 1e-9)
    }

    @Test func excludeDropsOverlap() throws {
        let result = try Path.combine(.exclude, Self.a, Self.b, rule: .nonZero, tolerance: 0.01)
        #expect(PathArea.contains(result, Point(x: 2, y: 2), rule: .nonZero))
        #expect(PathArea.contains(result, Point(x: 12, y: 12), rule: .nonZero))
        #expect(!PathArea.contains(result, Point(x: 7, y: 7), rule: .nonZero))
    }

    @Test func nestedSubtractIsARingWithAClockwiseHole() throws {
        let inner = Self.square(3, 3, 7, 7)
        let ring = try Path.combine(.subtract, Self.a, inner, rule: .nonZero, tolerance: 0.01)
        // Outer counter-clockwise (negative shoelace), hole clockwise (positive).
        #expect(try Self.contourAreas(ring) == [-100, 16])
        #expect(try Self.area(.intersect, Self.a, inner) == 16)
        #expect(try Self.area(.union, Self.a, inner) == 100)
        #expect(try Self.area(.subtract, inner, Self.a) == 0)
    }

    @Test func disjointSquaresKeepBothOrNothing() throws {
        let far = Self.square(20, 20, 30, 30)
        #expect(try Self.contourAreas(Path.combine(.union, Self.a, far, rule: .nonZero, tolerance: 0.01)) == [-100, -100])
        #expect(try Path.combine(.intersect, Self.a, far, rule: .nonZero, tolerance: 0.01).elements.isEmpty)
        #expect(try Self.area(.subtract, Self.a, far) == 100)
    }

    @Test func touchingUnionIsOne() throws {
        // 0.1 + 0.2 is 5.6e-17 past 0.3: the shared edge merges under the 1e-9 snap.
        let left = Self.square(0, 0, 0.3, 1), right = Self.square(0.1 + 0.2, 0, 1, 1)
        let union = try Path.combine(.union, left, right, rule: .nonZero, tolerance: 0.01)
        #expect(try union.flattened(tolerance: 0.01).count == 1)
        #expect(abs(try Self.area(.union, left, right) - 1) < 1e-12)
    }

    @Test func partlySharedEdgeSplitsAtTheOtherEnds() throws {
        // The edges at x = 10 overlap on y 5...10; a's straight-through vertex
        // (10, 7) lies inside side's edge, which only the collinear split cuts.
        let a = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 7), Point(x: 10, y: 10),
                                Point(x: 0, y: 10)], closed: true)
        let side = Self.square(10, 5, 20, 15)
        let union = try Path.combine(.union, a, side, rule: .nonZero, tolerance: 0.01)
        #expect(try union.flattened(tolerance: 0.01).count == 1)
        #expect(try Self.area(.union, a, side) == 200)
        #expect(try Path.combine(.intersect, a, side, rule: .nonZero, tolerance: 0.01).elements.isEmpty)
        #expect(try Self.area(.exclude, a, side) == 200)
    }

    @Test func nonZeroDiffers() throws {
        // One path, two overlapping squares wound the same way: the overlap winds twice.
        let twice = Path(elements: Self.a.elements + Self.b.elements)
        #expect(abs(try Self.area(.union, twice, Path(), rule: .nonZero) - 175) < 1e-9)
        #expect(abs(try Self.area(.union, twice, Path(), rule: .evenOdd) - 150) < 1e-9)
        #expect(abs(try Self.area(.subtract, Self.square(-1, -1, 16, 16), twice, rule: .nonZero) - (289 - 175)) < 1e-9)
    }

    @Test func capThrows() throws {
        let max = Path.maxBooleanVertices
        // A closed polyline flattens to its points plus the repeated start; a adds 5.
        let spiky = { (count: Int) in Path(polyline: Array(repeating: Point(x: 0, y: 0), count: count - 4)
            + [Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10)], closed: true) }
        #expect(abs(try Self.area(.union, spiky(max), Path()) - 100) < 1e-9)
        #expect(throws: GeometryError.tooComplex(max)) { try Path.combine(.union, spiky(max - 4), Self.a, rule: .nonZero, tolerance: 0.01) }
        let bad = Path(polyline: [Point(x: 0, y: 0), Point(x: .nan, y: 1), Point(x: 1, y: 1)], closed: true)
        #expect(throws: GeometryError.nonFinite) { try Path.combine(.union, bad, Self.a, rule: .nonZero, tolerance: 0.01) }
        #expect(throws: GeometryError.invalidTolerance) { try Path.combine(.union, Self.a, Self.b, rule: .nonZero, tolerance: 0) }
    }

    /// A comb of `n` teeth 10 tall along x; `swapped` lays it along y instead.
    static func comb(_ n: Int, swapped: Bool = false) -> Path {
        let points = (0..<n).flatMap { k -> [Point] in
            let a = 2 * Double(k) + 0.5
            return [Point(x: a, y: 0), Point(x: a, y: 10), Point(x: a + 1, y: 10), Point(x: a + 1, y: 0)]
        } + [Point(x: 2 * Double(n) + 1, y: -1), Point(x: 0, y: -1)]
        return Path(polyline: swapped ? points.map { Point(x: $0.y, y: $0.x) } : points, closed: true)
    }

    @Test func crossingWorkIsCapped() throws {
        // 5 teeth each way cross 100 times: past a 50-step cap it throws instead of cutting on.
        let (x, y) = (Self.comb(5), Self.comb(5, swapped: true))
        #expect(throws: GeometryError.tooComplex(50)) { try Path.combine(.union, x, y, rule: .nonZero, tolerance: 0.01, workLimit: 50) }
        #expect(try !Path.combine(.union, x, y, rule: .nonZero, tolerance: 0.01).elements.isEmpty)
        #expect(try !Path.combine(.union, x, y, rule: .nonZero, tolerance: 0.01, workLimit: 10_000).elements.isEmpty)
        // Two overlapping 5,000-vertex circles (the logo budget) need under a tenth of the cap.
        let circle = { (cx: Double) in Path(polyline: (0..<5_000).map { k in
            let t = Double(k) / 5_000 * 2 * Double.pi
            return Point(x: cx + 100 * cos(t), y: 100 * sin(t))
        }, closed: true) }
        #expect(try !Path.combine(.union, circle(0), circle(50), rule: .nonZero, tolerance: 0.01,
                                  workLimit: Path.maxBooleanWork / 10).elements.isEmpty)
    }

    @Test func hugeCoordinatesThrowNotLoseCrossings() throws {
        // Edge norms near 1e155 square past Double's range.
        let big = Self.square(-1e155, -1e155, 1e155, 1e155), shifted = Self.square(0, 0, 2e155, 2e155)
        #expect(throws: GeometryError.nonFinite) { try Path.combine(.union, big, shifted, rule: .nonZero, tolerance: 0.01) }
    }
}
