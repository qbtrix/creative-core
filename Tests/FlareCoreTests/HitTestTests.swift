// HitTestTests.swift: Shape.contains under even-odd and nonzero rules for a
// square, a concave L, a self-intersecting star and a curved path; open shapes
// contain nothing; points on vertices and edges and random points never crash.
// Path.isWithin streams the flattened outline: it agrees with a check over
// every segment of `flattened` and stops at the first segment in reach.
@testable import FlareCore
import Testing

@Suite struct HitTestTests {
    static let rules: [FillRule] = [.evenOdd, .nonZero]

    static let square = Shape(points: [
        Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10),
    ])

    // L: a 10x10 box with the top-right 5x5 quadrant cut away.
    static let lShape = Shape(points: [
        Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 5),
        Point(x: 5, y: 5), Point(x: 5, y: 10), Point(x: 0, y: 10),
    ])

    // Five-point star: a radius-10 pentagon's vertices joined every second one.
    static let star = Shape(points: [
        Point(x: 0, y: -10), Point(x: 5.8779, y: 8.0902), Point(x: -9.5106, y: -3.0902),
        Point(x: 9.5106, y: -3.0902), Point(x: -5.8779, y: 8.0902),
    ])

    @Test func square() {
        for rule in Self.rules {
            #expect(Self.square.contains(Point(x: 5, y: 5), rule: rule))
            #expect(Self.square.contains(Point(x: 0.1, y: 9.9), rule: rule))
            #expect(!Self.square.contains(Point(x: -1, y: 5), rule: rule))
            #expect(!Self.square.contains(Point(x: 11, y: 5), rule: rule))
            #expect(!Self.square.contains(Point(x: 5, y: 10.5), rule: rule))
        }
    }

    @Test func concaveL() {
        for rule in Self.rules {
            #expect(Self.lShape.contains(Point(x: 2, y: 2), rule: rule))
            #expect(Self.lShape.contains(Point(x: 8, y: 2), rule: rule))
            #expect(Self.lShape.contains(Point(x: 2, y: 8), rule: rule))
            #expect(!Self.lShape.contains(Point(x: 8, y: 8), rule: rule))
        }
    }

    @Test func starCentreDependsOnRule() {
        let centre = Point(x: 0, y: 0)
        #expect(!Self.star.contains(centre, rule: .evenOdd))
        #expect(Self.star.contains(centre, rule: .nonZero))
        // A point inside a tip is in under both rules; far away is out under both.
        for rule in Self.rules {
            #expect(Self.star.contains(Point(x: 0, y: -8), rule: rule))
            #expect(!Self.star.contains(Point(x: 20, y: 20), rule: rule))
        }
    }

    @Test func openShapeContainsNothing() {
        var open = Self.square
        open.closed = false
        for rule in Self.rules {
            #expect(!open.contains(Point(x: 5, y: 5), rule: rule))
        }
        let openPath = Shape(points: [], path: Path(elements: [
            .move(to: Point(x: 0, y: 0)), .line(to: Point(x: 10, y: 0)), .line(to: Point(x: 10, y: 10)),
        ]))
        #expect(!openPath.contains(Point(x: 8, y: 2), rule: .nonZero))
        #expect(!Shape(points: []).contains(Point(x: 0, y: 0), rule: .evenOdd))
    }

    @Test func curvedPath() {
        // Square whose right side bulges out to x = 15 at y = 5 via a quad.
        let shape = Shape(points: [], path: Path(elements: [
            .move(to: Point(x: 0, y: 0)), .line(to: Point(x: 10, y: 0)),
            .quad(control: Point(x: 20, y: 5), to: Point(x: 10, y: 10)),
            .line(to: Point(x: 0, y: 10)), .close,
        ]))
        #expect(shape.contains(Point(x: 14, y: 5), rule: .nonZero))
        #expect(!shape.contains(Point(x: 16, y: 5), rule: .nonZero))
        #expect(!shape.contains(Point(x: 11.5, y: 0.5), rule: .evenOdd))
    }

    @Test func verticesEdgesAndOddInputDoNotCrash() {
        for shape in [Self.square, Self.lShape, Self.star] {
            for p in shape.points {
                for rule in Self.rules {
                    _ = shape.contains(p, rule: rule)
                    _ = shape.contains(Point(x: p.x, y: p.y + 1e-12), rule: rule)
                }
            }
        }
        _ = Self.square.contains(Point(x: 5, y: 0), rule: .evenOdd)
        _ = Self.square.contains(Point(x: 10, y: 5), rule: .nonZero)
        #expect(!Self.square.contains(Point(x: .nan, y: 5), rule: .nonZero))
        #expect(!Self.square.contains(Point(x: .infinity, y: 5), rule: .evenOdd))
        let bad = Shape(points: [Point(x: .nan, y: 0), Point(x: 1, y: .infinity), Point(x: 0, y: 1)])
        _ = bad.contains(Point(x: 0, y: 0), rule: .nonZero)
    }

    @Test func randomPointsAgreeWithSquareBounds() {
        var rng = SplitMix64(seed: 23)
        for _ in 0..<500 {
            let p = Point(x: Double.random(in: -5...15, using: &rng), y: Double.random(in: -5...15, using: &rng))
            let inside = p.x > 0 && p.x < 10 && p.y > 0 && p.y < 10
            let onBoundary = p.x == 0 || p.x == 10 || p.y == 0 || p.y == 10
            if !onBoundary {
                #expect(Self.square.contains(p, rule: .evenOdd) == inside)
                #expect(Self.square.contains(p, rule: .nonZero) == inside)
            }
        }
    }

    @Test func strokeMakesOpenShapesHittable() {
        let line = Shape(points: [Point(x: 0, y: 0), Point(x: 10, y: 0)], closed: false, stroke: Stroke(width: 2))
        for rule in Self.rules {
            #expect(!line.contains(Point(x: 5, y: 0.5), rule: rule))
            #expect(line.hits(Point(x: 5, y: 0.5), rule: rule))
            #expect(line.hits(Point(x: 10.9, y: 0), rule: rule))
            #expect(!line.hits(Point(x: 5, y: 1.5), rule: rule))
            #expect(!Shape(points: line.points, closed: false).hits(Point(x: 5, y: 0), rule: rule))
        }
    }

    @Test func layersHitThroughInstances() {
        let inner = Layer(id: "in", name: "In", shapes: [Self.square])
        let symbol = Symbol(id: "sym", name: "Sym", layers: [inner])
        let host = Layer(id: "h", name: "H", tracks: ["x": [Keyframe(frame: 0, value: 100)]],
                         instances: [Instance(symbolID: "sym", transform: Transform(x: 0, y: 50, scaleX: 2, scaleY: 2))])
        #expect(host.hits(Point(x: 119, y: 69), at: 0, symbols: [symbol], rule: .nonZero))
        #expect(!host.hits(Point(x: 121, y: 69), at: 0, symbols: [symbol], rule: .nonZero))
        #expect(!host.hits(Point(x: 119, y: 69), at: 0, symbols: [], rule: .nonZero))
        var hidden = host
        hidden.isVisible = false
        #expect(!hidden.hits(Point(x: 119, y: 69), at: 0, symbols: [symbol], rule: .nonZero))
        // A symbol that shows itself is cut off instead of recursing forever.
        let loop = Symbol(id: "sym", name: "Loop", layers: [Layer(id: "l", name: "L", instances: [Instance(symbolID: "sym")])])
        #expect(!host.hits(Point(x: 119, y: 69), at: 0, symbols: [loop], rule: .nonZero))
    }

    /// The reference isWithin: every segment of the fully flattened outline.
    static func flattenAllIsWithin(_ path: Path, _ reach: Double, of p: Point, flatness: Double) -> Bool {
        guard let lines = try? path.flattened(tolerance: flatness) else { return false }
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) {
                let dx = b.x - a.x, dy = b.y - a.y, ls = dx * dx + dy * dy
                let t = ls > 0 ? min(max(((p.x - a.x) * dx + (p.y - a.y) * dy) / ls, 0), 1) : 0
                let ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy)
                if (ex * ex + ey * ey).squareRoot() <= reach { return true }
            }
        }
        return false
    }

    @Test func streamedIsWithinEqualsFlattenAll() {
        var rng = SplitMix64(seed: 61)
        func point() -> Point { Point(x: Double.random(in: -20...20, using: &rng), y: Double.random(in: -20...20, using: &rng)) }
        for _ in 0..<300 {
            var elements: [PathElement] = []
            for _ in 0..<Int.random(in: 0...8, using: &rng) {
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: elements.append(.move(to: point()))
                case 1: elements.append(.line(to: point()))
                case 2: elements.append(.quad(control: point(), to: point()))
                case 3: elements.append(.cubic(control1: point(), control2: point(), to: point()))
                default: elements.append(.close)
                }
            }
            let path = Path(elements: elements)
            let flatness = [0.01, 0.5, 4, 0, -1, .nan].randomElement(using: &rng) ?? 0.5
            for _ in 0..<10 {
                let p = point(), reach = Double.random(in: 0...6, using: &rng)
                #expect(path.isWithin(reach, of: p, flatness: flatness)
                        == Self.flattenAllIsWithin(path, reach, of: p, flatness: flatness))
            }
        }
    }

    @Test func hugeOutlineHitNearFirstSegmentReturnsQuickly() {
        // 20,000 huge cubics at flatness 1e-3 each flatten to 4,096 segments:
        // 80 million points if the whole outline were built first.
        var elements: [PathElement] = [.move(to: Point(x: 0, y: 0))]
        for i in 0..<20_000 {
            let s = Double(i % 2 == 0 ? 1 : -1) * 1e9
            elements.append(.cubic(control1: Point(x: s, y: 0), control2: Point(x: s, y: s), to: Point(x: 0, y: s)))
        }
        let path = Path(elements: elements)
        let clock = ContinuousClock()
        var hit = false
        let elapsed = clock.measure { hit = path.isWithin(1, of: Point(x: 0, y: 0.5), flatness: 1e-3) }
        #expect(hit)
        #expect(elapsed < .milliseconds(200))
    }
}
