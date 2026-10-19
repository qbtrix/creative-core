// PathEditTests.swift: the anchors view round-trips every fixture, nearest
// finds the analytic foot on a cubic, inserting keeps the drawn shape and adds
// one anchor, removing and converting anchors, and bad indices throw.
import Foundation
@testable import FlareCore
import Testing

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

/// The cubic of a line or cubic element starting at `p0`.
private func cubicOf(_ e: PathElement, from p0: Point) -> (Point, Point, Point, Point)? {
    switch e {
    case .line(let to):
        return (p0, pt(p0.x + (to.x - p0.x) / 3, p0.y + (to.y - p0.y) / 3),
                pt(p0.x + 2 * (to.x - p0.x) / 3, p0.y + 2 * (to.y - p0.y) / 3), to)
    case .cubic(let c1, let c2, let to): return (p0, c1, c2, to)
    default: return nil
    }
}

/// Exact signed area of a path of lines and cubics: half the integral of
/// x dy - y dx, by 3-point Gauss-Legendre, exact for these degree-5 terms.
private func exactArea(_ path: Path) -> Double {
    let nodes = [(0.5 - 0.15.squareRoot() / 2, 5.0 / 18), (0.5, 8.0 / 18), (0.5 + 0.15.squareRoot() / 2, 5.0 / 18)]
    var total = 0.0
    var pen = pt(0, 0), start = pen
    for e in path.elements {
        if case .move(let to) = e { (pen, start) = (to, to); continue }
        let el = e == .close ? PathElement.line(to: start) : e
        guard let (p0, p1, p2, p3) = cubicOf(el, from: pen) else { continue }
        for (t, w) in nodes {
            let q = cubicAt(p0, p1, p2, p3, t), u = 1 - t
            let dx = 3 * (u * u * (p1.x - p0.x) + 2 * u * t * (p2.x - p1.x) + t * t * (p3.x - p2.x))
            let dy = 3 * (u * u * (p1.y - p0.y) + 2 * u * t * (p2.y - p1.y) + t * t * (p3.y - p2.y))
            total += w * (q.x * dy - q.y * dx) / 2
        }
        pen = p3
    }
    return total
}

private func anchorCount(_ path: Path) -> Int { path.contours.reduce(0) { $0 + $1.anchors.count } }

@Suite struct PathEditTests {
    @Test func anchorsViewRoundTripsEveryFixture() throws {
        for (name, path) in try PathFixtures.all() {
            let a = try path.flattened(tolerance: 0.05)
            let b = try Path(contours: path.contours).flattened(tolerance: 0.05)
            #expect(a.count == b.count && a.map(\.count) == b.map(\.count), "\(name)")
            for (pa, pb) in zip(a.joined(), b.joined()) {
                #expect(abs(pa.x - pb.x) <= 1e-9 && abs(pa.y - pb.y) <= 1e-9, "\(name)")
            }
        }
        #expect(anchorCount(PathFixtures.scribble()) == PathFixtures.scribbleAnchors)
        #expect(try PathFixtures.ring().contours.allSatisfy { $0.closed && $0.anchors.count == 4 })
        #expect(try PathFixtures.ring().contours[0].anchors.allSatisfy { $0.kind == .symmetric })
        #expect(try PathFixtures.star().contours[0].anchors.allSatisfy { $0.kind == .corner && $0.handleIn == nil })
    }

    @Test func quadIsRaisedToACubic() throws {
        let path = Path(elements: [.move(to: pt(0, 0)), .quad(control: pt(10, 0), to: pt(10, 10))])
        let anchors = try #require(path.contours.first).anchors
        let out = try #require(anchors.first?.handleOut), into = try #require(anchors.last?.handleIn)
        #expect(abs(out.x - 20.0 / 3) < 1e-12 && out.y == 0)
        #expect(into.x == 10 && abs(into.y - 10.0 / 3) < 1e-12)
    }

    @Test func nearestFindsTheAnalyticFoot() throws {
        // x = 2t - 1, y = x^2; the foot from (2, 0) solves x^3 + x/2 - 1 = 0.
        let parabola = Path(elements: [.move(to: pt(-1, 1)),
                                       .cubic(control1: pt(-1.0 / 3, -1.0 / 3), control2: pt(1.0 / 3, -1.0 / 3), to: pt(1, 1))])
        let r = (0.25 + 1.0 / 216).squareRoot()
        let x = cbrt(0.5 + r) + cbrt(0.5 - r)
        let hit = try #require(try parabola.nearest(to: pt(2, 0), tolerance: 0.01))
        #expect(hit.element == 1 && abs(hit.t - (x + 1) / 2) < 1e-6)
        #expect(abs(hit.point.x - x) < 1e-6 && abs(hit.point.y - x * x) < 1e-6)
        #expect(abs(hit.distance - ((x - 2) * (x - 2) + x * x * x * x).squareRoot()) < 1e-9)
        let square = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)], closed: true)
        let side = try #require(try square.nearest(to: pt(-3, 4), tolerance: 0.01))
        #expect(side.element == 4 && abs(side.point.x) < 1e-9 && abs(side.point.y - 4) < 1e-6)
        #expect(try Path().nearest(to: pt(0, 0), tolerance: 0.1) == nil)
        #expect(throws: GeometryError.invalidTolerance) { try square.nearest(to: pt(0, 0), tolerance: 0) }
        #expect(throws: GeometryError.nonFinite) { try square.nearest(to: pt(.nan, 0), tolerance: 0.1) }
    }

    @Test func insertKeepsShape() throws {
        for path in [PathFixtures.figureEight(), PathFixtures.glyph()] {
            for (element, t) in [(1, 0.3), (2, 0.75), (4, 0.5)] where element < path.elements.count {
                let pen = try #require(path.elements[element - 1].endPoint ?? path.elements.first?.endPoint)
                let split = try path.inserting(at: PathLocation(element: element, t: t, point: pen, distance: 0))
                #expect(abs(exactArea(split) - exactArea(path)) < 1e-9)
                #expect(anchorCount(split) == anchorCount(path) + 1)
                guard let whole = cubicOf(path.elements[element], from: pen),
                      let left = cubicOf(split.elements[element], from: pen),
                      let right = cubicOf(split.elements[element + 1], from: left.3) else { continue }
                for u in stride(from: 0.0, through: 1, by: 0.125) {
                    let l = cubicAt(left.0, left.1, left.2, left.3, u), r = cubicAt(right.0, right.1, right.2, right.3, u)
                    let wl = cubicAt(whole.0, whole.1, whole.2, whole.3, t * u)
                    let wr = cubicAt(whole.0, whole.1, whole.2, whole.3, t + (1 - t) * u)
                    #expect(abs(l.x - wl.x) < 1e-9 && abs(l.y - wl.y) < 1e-9)
                    #expect(abs(r.x - wr.x) < 1e-9 && abs(r.y - wr.y) < 1e-9)
                }
            }
        }
    }

    @Test func removingAnchorJoinsNeighbours() throws {
        let square = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)], closed: true)
        let three = try square.removingAnchor(contour: 0, index: 1)
        #expect(three.contours == [PathContour(anchors: [pt(0, 0), pt(10, 10), pt(0, 10)].map { PathAnchor(point: $0) }, closed: true)])
        let dot = Path(elements: [.move(to: pt(1, 1))])
        #expect(try dot.removingAnchor(contour: 0, index: 0).elements.isEmpty)
    }

    @Test func symmetricEqualizes() throws {
        let p = pt(10, 0)
        let path = Path(elements: [.move(to: pt(0, 0)),
                                   .cubic(control1: pt(3, 0), control2: pt(8, 1), to: p),
                                   .cubic(control1: pt(16, -2), control2: pt(20, 5), to: pt(20, 10))])
        let sym = try #require(try path.converting(contour: 0, index: 1, to: .symmetric).contours.first).anchors[1]
        let hin = try #require(sym.handleIn), hout = try #require(sym.handleOut)
        #expect(abs(hin.x - p.x + hout.x - p.x) < 1e-9 && abs(hin.y - p.y + hout.y - p.y) < 1e-9)
        #expect(sym.kind == .symmetric && (hout.x - p.x) * 6 + (hout.y - p.y) * -2 > 0)
        let smooth = try #require(try path.converting(contour: 0, index: 1, to: .smooth).contours.first).anchors[1]
        let sin = try #require(smooth.handleIn), sout = try #require(smooth.handleOut)
        #expect(smooth.kind == .smooth && abs(norm(sin.x - p.x, sin.y - p.y) - 5.0.squareRoot()) < 1e-9)
        #expect(abs(norm(sout.x - p.x, sout.y - p.y) - 40.0.squareRoot()) < 1e-9)
        let corner = try #require(try path.converting(contour: 0, index: 1, to: .corner).contours.first).anchors[1]
        #expect(corner.handleIn == nil && corner.handleOut == nil)
        let polyline = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10)], closed: false)
        #expect(try polyline.converting(contour: 0, index: 1, to: .symmetric).contours[0].anchors[1].kind == .symmetric)
    }

    @Test func badIndexThrows() throws {
        let square = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)], closed: true)
        for (c, i) in [(0, 4), (0, -1), (1, 0), (-1, 0)] {
            #expect(throws: GeometryError.invalidLocation) { try square.removingAnchor(contour: c, index: i) }
            #expect(throws: GeometryError.invalidLocation) { try square.converting(contour: c, index: i, to: .smooth) }
        }
        for (e, t) in [(0, 0.5), (5, 0.5), (-1, 0.5), (1, 1.5), (1, .nan)] {
            let at = PathLocation(element: e, t: t, point: pt(0, 0), distance: 0)
            #expect(throws: GeometryError.invalidLocation) { try square.inserting(at: at) }
        }
        let penless = Path(elements: [.line(to: pt(1, 1))])
        #expect(throws: GeometryError.invalidLocation) {
            try penless.inserting(at: PathLocation(element: 0, t: 0.5, point: pt(0, 0), distance: 0))
        }
    }
}
