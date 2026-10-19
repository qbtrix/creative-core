// PathMeasureTests.swift: length and the point and unit tangent at a length,
// on a rectangle, a circle and a path of two contours; bad input throws.
import Foundation
import FlareCore
import Testing

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
private func near(_ a: Point, _ b: Point, _ eps: Double = 1e-9) -> Bool { abs(a.x - b.x) <= eps && abs(a.y - b.y) <= eps }

@Suite struct PathMeasureTests {
    static let rect = Rect(minX: 0, minY: 0, maxX: 100, maxY: 50)

    @Test func rectangleIs300Long() throws {
        #expect(abs(try PathBuilders.rectangle(in: Self.rect).length(tolerance: 0.1) - 300) <= 1e-9)
        #expect(try Path().length(tolerance: 0.1) == 0)
    }

    @Test func sampleAtCorner() throws {
        let path = try PathBuilders.rectangle(in: Self.rect)
        let corner = try #require(try path.sample(atLength: 150, tolerance: 0.1))
        #expect(near(corner.point, pt(100, 50)) && near(corner.tangent, pt(-1, 0)))
        let start = try #require(try path.sample(atLength: 0, tolerance: 0.1))
        #expect(near(start.point, pt(0, 0)) && near(start.tangent, pt(1, 0)))
        let mid = try #require(try path.sample(atLength: 125, tolerance: 0.1))
        #expect(near(mid.point, pt(100, 25)) && near(mid.tangent, pt(0, 1)))
        let end = try #require(try path.sample(atLength: 300, tolerance: 0.1))
        #expect(near(end.point, pt(0, 0)) && near(end.tangent, pt(0, -1)))
    }

    @Test func outsideTheRulerIsNil() throws {
        let path = try PathBuilders.rectangle(in: Self.rect)
        for s in [-1, 300.5, .nan, .infinity] { #expect(try path.sample(atLength: s, tolerance: 0.1) == nil) }
        #expect(try Path().sample(atLength: 0, tolerance: 0.1) == nil)
        #expect(try Path(elements: [.move(to: pt(1, 1))]).sample(atLength: 0, tolerance: 0.1) == nil)
    }

    @Test func circleLengthAndUnitTangent() throws {
        let circle = try PathBuilders.ellipse(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 100))
        let length = try circle.length(tolerance: 1e-4)
        #expect(abs(length - 100 * Double.pi) / (100 * Double.pi) < 1e-3)
        for k in 0...20 {
            let s = try #require(try circle.sample(atLength: length * Double(k) / 20, tolerance: 1e-4))
            #expect(abs(norm(s.tangent) - 1) <= 1e-9)
            #expect(abs(norm(pt(s.point.x - 50, s.point.y - 50)) - 50) < 0.05)
            // The tangent is perpendicular to the radius.
            #expect(abs((s.point.x - 50) * s.tangent.x + (s.point.y - 50) * s.tangent.y) / 50 < 1e-2)
        }
    }

    @Test func secondContourContinuesTheRuler() throws {
        let path = Path(elements: [.move(to: pt(0, 0)), .line(to: pt(10, 0)), .move(to: pt(0, 5)), .line(to: pt(0, 25))])
        #expect(try path.length(tolerance: 0.1) == 30)
        let join = try #require(try path.sample(atLength: 10, tolerance: 0.1))
        #expect(near(join.point, pt(0, 5)) && near(join.tangent, pt(0, 1)))
        let inSecond = try #require(try path.sample(atLength: 20, tolerance: 0.1))
        #expect(near(inSecond.point, pt(0, 15)))
    }

    @Test func badInputThrows() throws {
        let path = try PathBuilders.rectangle(in: Self.rect)
        #expect(throws: GeometryError.invalidTolerance) { try path.length(tolerance: 0) }
        #expect(throws: GeometryError.invalidTolerance) { try path.sample(atLength: 1, tolerance: .nan) }
        let nan = Path(elements: [.move(to: pt(0, 0)), .line(to: pt(.nan, 1))])
        #expect(throws: GeometryError.nonFinite) { try nan.length(tolerance: 0.1) }
        let huge = Path(polyline: [pt(-1e308, 0), pt(1e308, 0)], closed: false)
        #expect(throws: GeometryError.nonFinite) { try huge.sample(atLength: 0, tolerance: 0.1) }
    }
}

private func norm(_ p: Point) -> Double { (p.x * p.x + p.y * p.y).squareRoot() }
