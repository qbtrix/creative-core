// ShapeBoundsTests.swift: Shape.bounds hugs curves tighter than their control
// box, matches dense sampling, equals point min/max for polylines, and never
// crashes on empty or non-finite input.
import FlareCore
import Testing

@Suite struct ShapeBoundsTests {
    static func sampledBounds(_ path: Path, steps: Int = 20000) -> Rect? {
        var points: [Point] = []
        var current = Point(x: 0, y: 0)
        var start = current
        for element in path.elements {
            switch element {
            case .move(let to):
                points.append(to)
                current = to
                start = to
            case .line(let to):
                points.append(to)
                current = to
            case .quad(let c, let to):
                for i in 0...steps {
                    let t = Double(i) / Double(steps), u = 1 - t
                    points.append(Point(x: u * u * current.x + 2 * u * t * c.x + t * t * to.x,
                                        y: u * u * current.y + 2 * u * t * c.y + t * t * to.y))
                }
                current = to
            case .cubic(let c1, let c2, let to):
                for i in 0...steps {
                    let t = Double(i) / Double(steps), u = 1 - t
                    let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                    points.append(Point(x: w0 * current.x + w1 * c1.x + w2 * c2.x + w3 * to.x,
                                        y: w0 * current.y + w1 * c1.y + w2 * c2.y + w3 * to.y))
                }
                current = to
            case .close:
                current = start
            }
        }
        return Rect(enclosing: points)
    }

    static func expectClose(_ a: Rect?, _ b: Rect?, tolerance: Double = 1e-9) {
        guard let a, let b else {
            Issue.record("missing bounds: \(String(describing: a)) vs \(String(describing: b))")
            return
        }
        #expect(abs(a.minX - b.minX) <= tolerance)
        #expect(abs(a.minY - b.minY) <= tolerance)
        #expect(abs(a.maxX - b.maxX) <= tolerance)
        #expect(abs(a.maxY - b.maxY) <= tolerance)
    }

    @Test func cubicIsTighterThanControlBoxAndMatchesSampling() {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .cubic(control1: Point(x: -10, y: 30), control2: Point(x: 40, y: 30), to: Point(x: 30, y: 0)),
        ])
        let shape = Shape(points: [], path: path)
        let bounds = shape.bounds
        let controlBox = Rect(enclosing: [Point(x: 0, y: 0), Point(x: -10, y: 30), Point(x: 40, y: 30),
                                          Point(x: 30, y: 0)])
        #expect(bounds != nil && controlBox != nil)
        if let bounds, let controlBox {
            #expect(bounds.minX > controlBox.minX)
            #expect(bounds.maxX < controlBox.maxX)
            #expect(bounds.maxY < controlBox.maxY)
        }
        // Peak y at t = 0.5 is 22.5; dense sampling hits it exactly.
        #expect(bounds?.maxY == 22.5)
        Self.expectClose(bounds, Self.sampledBounds(path))
    }

    @Test func quadIsTighterThanControlBoxAndMatchesSampling() {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .quad(control: Point(x: 10, y: 20), to: Point(x: 20, y: 0)),
        ])
        let bounds = Shape(points: [], path: path).bounds
        #expect(bounds == Rect(minX: 0, minY: 0, maxX: 20, maxY: 10))
        Self.expectClose(bounds, Self.sampledBounds(path))
    }

    @Test func randomCurvesMatchDenseSampling() {
        var rng = SplitMix64(seed: 21)
        func p() -> Point {
            Point(x: Double.random(in: -100...100, using: &rng), y: Double.random(in: -100...100, using: &rng))
        }
        for _ in 0..<50 {
            let path = Path(elements: [
                .move(to: p()),
                .cubic(control1: p(), control2: p(), to: p()),
                .quad(control: p(), to: p()),
                .close,
                .quad(control: p(), to: p()),
            ])
            guard let bounds = path.bounds, let sampled = Self.sampledBounds(path, steps: 4000) else {
                Issue.record("missing bounds")
                continue
            }
            // Sampling only sees points on the curve, so it never exceeds the tight box.
            #expect(bounds.minX <= sampled.minX && bounds.maxX >= sampled.maxX)
            #expect(bounds.minY <= sampled.minY && bounds.maxY >= sampled.maxY)
            Self.expectClose(bounds, sampled, tolerance: 1e-3)
        }
    }

    @Test func polylineBoundsAreMinMaxOfPoints() {
        let points = [Point(x: 3, y: -2), Point(x: -7, y: 5), Point(x: 1, y: 9), Point(x: 4, y: 0)]
        let shape = Shape(points: points, closed: false)
        #expect(shape.bounds == Rect(minX: -7, minY: -2, maxX: 4, maxY: 9))
        #expect(shape.bounds?.width == 11)
        #expect(shape.bounds?.height == 11)
    }

    @Test func emptyShapeHasNoBounds() {
        #expect(Shape(points: []).bounds == nil)
        #expect(Shape(points: [], path: Path()).bounds == nil)
        #expect(Shape(points: [], path: Path(elements: [.close])).bounds == nil)
    }

    @Test func nonFinitePointsDoNotCrash() {
        let bad: [Double] = [.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude]
        var rng = SplitMix64(seed: 2121)
        func p() -> Point {
            let pick = { (rng: inout SplitMix64) -> Double in
                Bool.random(using: &rng) ? bad.randomElement(using: &rng) ?? 0 : Double.random(in: -10...10, using: &rng)
            }
            return Point(x: pick(&rng), y: pick(&rng))
        }
        for _ in 0..<200 {
            let path = Path(elements: [
                .move(to: p()),
                .cubic(control1: p(), control2: p(), to: p()),
                .quad(control: p(), to: p()),
                .line(to: p()),
                .close,
            ])
            if let bounds = Shape(points: [], path: path).bounds {
                #expect(!bounds.minX.isNaN && !bounds.maxX.isNaN && !bounds.minY.isNaN && !bounds.maxY.isNaN)
                #expect(bounds.minX <= bounds.maxX && bounds.minY <= bounds.maxY)
            }
            _ = Shape(points: [p(), p(), p()]).bounds
        }
        #expect(Shape(points: [Point(x: .nan, y: 0)]).bounds == nil)
    }
}
