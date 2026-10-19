// PathBooleanFuzzTests.swift: 500 seeded pairs (random, integer grid,
// identical, shifted, nested, repeated points; 1 in 25 non-finite, which must
// throw) through every op: area identities hold and sampled points match HitTest.
import FlareCore
import Testing

@Suite struct PathBooleanFuzzTests {
    static let ops: [BooleanOp] = [.union, .subtract, .intersect, .exclude], box = Rect(minX: -1, minY: -4, maxX: 13, maxY: 11)
    static func polygon(_ rng: inout SplitMix64) -> [Point] {
        let grid = Bool.random(using: &rng)
        var points = (0..<Int.random(in: 3...7, using: &rng)).map { _ in
            let x = Double.random(in: 0...10, using: &rng), y = Double.random(in: 0...10, using: &rng)
            return grid ? Point(x: x.rounded(), y: y.rounded()) : Point(x: x, y: y)
        }
        if let p = points.last, Int.random(in: 0..<4, using: &rng) == 0 { points.append(p) }
        return points
    }

    static func partner(of a: [Point], _ rng: inout SplitMix64) -> [Point] {
        switch Int.random(in: 0..<5, using: &rng) {
        case 0: return a
        case 1: return a.map { Point(x: $0.x + 2, y: $0.y - 3) }
        case 2: return a.map { Point(x: 5 + ($0.x - 5) / 2, y: 5 + ($0.y - 5) / 2) }
        default: return polygon(&rng)
        }
    }

    static func nearEdge(_ p: Point, _ polygon: [Point]) -> Bool {
        zip(polygon, polygon.dropFirst() + polygon.prefix(1)).contains { a, b in
            let dx = b.x - a.x, dy = b.y - a.y, length = dx * dx + dy * dy
            let t = length > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / length, 0), 1) : 0
            let ex = p.x - a.x - t * dx, ey = p.y - a.y - t * dy
            return ex * ex + ey * ey < 1e-12
        }
    }

    @Test func seededPairsThrowOrMatchSetAlgebra() throws {
        var rng = SplitMix64(seed: 430)
        for _ in 0..<500 {
            let pa = Self.polygon(&rng)
            var pb = Self.partner(of: pa, &rng)
            let rule: FillRule = Bool.random(using: &rng) ? .evenOdd : .nonZero
            if Int.random(in: 0..<25, using: &rng) == 0 { pb[0].y = Bool.random(using: &rng) ? .nan : .infinity }
            let a = Path(polyline: pa, closed: true), b = Path(polyline: pb, closed: true)
            guard pb.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
                #expect(throws: GeometryError.nonFinite) { try Path.combine(.union, a, b, rule: rule, tolerance: 0.01) }
                continue
            }
            let results = try Self.ops.map { try Path.combine($0, a, b, rule: rule, tolerance: 0.01) }
            let areas = try results.map { -(try PathArea.signedArea($0)) }
            let bMinusA = -(try PathArea.signedArea(Path.combine(.subtract, b, a, rule: rule, tolerance: 0.01)))
            #expect(abs(areas[0] - (areas[1] + areas[2] + bMinusA)) < 1e-6, "union = a-b + a&b + b-a")
            #expect(abs(areas[3] - (areas[1] + bMinusA)) < 1e-6, "exclude = a-b + b-a")
            for p in PathArea.points(in: Self.box, count: 64, rng: &rng) where !Self.nearEdge(p, pa) && !Self.nearEdge(p, pb) {
                let inA = PathArea.contains(a, p, rule: rule), inB = PathArea.contains(b, p, rule: rule)
                let want = [inA || inB, inA && !inB, inA && inB, inA != inB] // ops' order
                #expect(results.map { PathArea.contains($0, p, rule: .nonZero) } == want, "at \(p)")
            }
        }
    }
}
