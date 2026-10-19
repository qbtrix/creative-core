// PathEditTests.swift: the anchors view round-trips every fixture, nearest
// finds the analytic foot on a cubic, inserting keeps the drawn shape and adds
// one anchor, removing and converting anchors, and bad indices throw.
import Foundation
@testable import FlareCore
import Testing

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
private let square = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)], closed: true)

/// Exact signed area of a path of lines and cubics: half the integral of
/// x dy - y dx, by 3-point Gauss-Legendre, exact for these degree-5 terms.
private func exactArea(_ path: Path) -> Double {
    let nodes = [(0.5 - 0.15.squareRoot(), 5.0 / 18), (0.5, 8.0 / 18), (0.5 + 0.15.squareRoot(), 5.0 / 18)]
    var total = 0.0, pen = pt(0, 0), start = pen
    for e in path.elements {
        if case .move(let to) = e { (pen, start) = (to, to) }
        guard let (p0, p1, p2, p3) = Path.cubic(e, from: pen, start: start) else { continue }
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
            let a = try path.flattened(tolerance: 0.05), b = try Path(contours: path.contours).flattened(tolerance: 0.05)
            #expect(a.map(\.count) == b.map(\.count), "\(name)")
            for (pa, pb) in zip(a.joined(), b.joined()) {
                #expect(abs(pa.x - pb.x) <= 1e-9 && abs(pa.y - pb.y) <= 1e-9, "\(name)")
            }
        }
        #expect(anchorCount(PathFixtures.scribble()) == PathFixtures.scribbleAnchors)
        let ring = try PathFixtures.ring().contours
        #expect(ring.count == 2 && ring.allSatisfy { $0.closed && $0.anchors.count == 4 })
        #expect(ring[0].anchors.allSatisfy { $0.kind == .symmetric })
        #expect(try PathFixtures.star().contours[0].anchors.allSatisfy { $0.kind == .corner && $0.handleIn == nil })
        let quad = Path(elements: [.move(to: pt(0, 0)), .quad(control: pt(10, 0), to: pt(10, 10))]).contours[0].anchors
        #expect(quad.count == 2 && quad[0].handleOut.map { abs($0.x - 20.0 / 3) < 1e-12 && $0.y == 0 } == true)
        #expect(quad[1].handleIn.map { $0.x == 10 && abs($0.y - 10.0 / 3) < 1e-12 } == true)
    }

    @Test func nearestFindsTheAnalyticFoot() throws {
        // x = 2t - 1, y = x^2; the foot from (2, 0) solves x^3 + x/2 - 1 = 0 (Cardano).
        let parabola = Path(elements: [.move(to: pt(-1, 1)),
                                       .cubic(control1: pt(-1.0 / 3, -1.0 / 3), control2: pt(1.0 / 3, -1.0 / 3), to: pt(1, 1))])
        let r = (0.25 + 1.0 / 216).squareRoot(), x = cbrt(0.5 + r) + cbrt(0.5 - r)
        let hit = try #require(try parabola.nearest(to: pt(2, 0), tolerance: 0.01))
        #expect(hit.element == 1 && abs(hit.t - (x + 1) / 2) < 1e-6)
        #expect(abs(hit.point.x - x) < 1e-6 && abs(hit.point.y - x * x) < 1e-6)
        #expect(abs(hit.distance - ((x - 2) * (x - 2) + x * x * x * x).squareRoot()) < 1e-9)
        let side = try #require(try square.nearest(to: pt(-3, 4), tolerance: 0.01))
        #expect(side.element == 4 && abs(side.point.x) < 1e-9 && abs(side.point.y - 4) < 1e-6)
        #expect(try Path().nearest(to: pt(0, 0), tolerance: 0.1) == nil)
        #expect(throws: GeometryError.invalidTolerance) { try square.nearest(to: pt(0, 0), tolerance: 0) }
        #expect(throws: GeometryError.nonFinite) { try square.nearest(to: pt(.nan, 0), tolerance: 0.1) }
    }

    @Test func insertKeepsShape() throws {
        // A cubic, a quad and a closing segment (element 4 of glyph and quadLoop) at a few t.
        for path in [PathFixtures.figureEight, PathFixtures.glyph, PathFixtures.quadLoop] {
            for (element, t) in [(1, 0.3), (2, 0.75), (4, 0.5)] where element < path.elements.count {
                let (pen, start) = path.pens()[element], at = try #require(pen)
                let split = try path.inserting(at: PathLocation(element: element, t: t, point: at, distance: 0))
                #expect(abs(exactArea(split) - exactArea(path)) < 1e-9 && anchorCount(split) == anchorCount(path) + 1)
                let whole = try #require(Path.cubic(path.elements[element], from: at, start: start))
                let left = try #require(Path.cubic(split.elements[element], from: at, start: start))
                let right = try #require(Path.cubic(split.elements[element + 1], from: left.3, start: start))
                for u in stride(from: 0.0, through: 1, by: 0.125) {
                    let l = cubicAt(left.0, left.1, left.2, left.3, u), r = cubicAt(right.0, right.1, right.2, right.3, u)
                    let wl = cubicAt(whole.0, whole.1, whole.2, whole.3, t * u)
                    let wr = cubicAt(whole.0, whole.1, whole.2, whole.3, t + (1 - t) * u)
                    #expect(abs(l.x - wl.x) < 1e-9 && abs(l.y - wl.y) < 1e-9 && abs(r.x - wr.x) < 1e-9 && abs(r.y - wr.y) < 1e-9)
                }
            }
        }
    }

    @Test func removingAnchorJoinsNeighbours() throws {
        let three = [pt(0, 0), pt(10, 10), pt(0, 10)].map { PathAnchor(point: $0) }
        #expect(try square.removingAnchor(contour: 0, index: 1).contours == [PathContour(anchors: three, closed: true)])
        #expect(try Path(elements: [.move(to: pt(1, 1))]).removingAnchor(contour: 0, index: 0).elements.isEmpty)
        // Three cubics: removing anchor 1 joins anchors 0 and 2 with their outer handles.
        let cubics = Path(elements: [.move(to: pt(0, 0)), .cubic(control1: pt(1, 4), control2: pt(3, 5), to: pt(5, 5)),
                                     .cubic(control1: pt(7, 5), control2: pt(9, 2), to: pt(10, 0)),
                                     .cubic(control1: pt(11, -2), control2: pt(14, -1), to: pt(15, 0))])
        #expect(try cubics.removingAnchor(contour: 0, index: 1).elements == [
            .move(to: pt(0, 0)), .cubic(control1: pt(1, 4), control2: pt(9, 2), to: pt(10, 0)),
            .cubic(control1: pt(11, -2), control2: pt(14, -1), to: pt(15, 0)),
        ])
    }

    @Test func symmetricEqualizes() throws {
        let p = pt(10, 0)
        let path = Path(elements: [.move(to: pt(0, 0)), .cubic(control1: pt(3, 0), control2: pt(8, 1), to: p),
                                   .cubic(control1: pt(16, -2), control2: pt(20, 5), to: pt(20, 10))])
        func converted(_ kind: AnchorKind) throws -> (PathAnchor, Point?, Point?) {
            let a = try path.converting(contour: 0, index: 1, to: kind).contours[0].anchors[1]
            return (a, a.handleIn.map { pt($0.x - p.x, $0.y - p.y) }, a.handleOut.map { pt($0.x - p.x, $0.y - p.y) })
        }
        let (sym, si, so) = try converted(.symmetric), hin = try #require(si), hout = try #require(so)
        #expect(sym.kind == .symmetric && abs(hin.x + hout.x) < 1e-9 && abs(hin.y + hout.y) < 1e-9)
        #expect(hout.x * 6 + hout.y * -2 > 0)
        let (smooth, mi, mo) = try converted(.smooth), sin = try #require(mi), sout = try #require(mo)
        #expect(smooth.kind == .smooth && abs(norm(sin.x, sin.y) - 5.0.squareRoot()) < 1e-9)
        #expect(abs(norm(sout.x, sout.y) - 40.0.squareRoot()) < 1e-9)
        let (_, ci, co) = try converted(.corner)
        #expect(ci == nil && co == nil)
        let polyline = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10)], closed: false)
        #expect(try polyline.converting(contour: 0, index: 1, to: .symmetric).contours[0].anchors[1].kind == .symmetric)
    }

    @Test func badIndexThrows() throws {
        for (c, i) in [(0, 4), (0, -1), (1, 0), (-1, 0)] {
            #expect(throws: GeometryError.invalidLocation) { try square.removingAnchor(contour: c, index: i) }
            #expect(throws: GeometryError.invalidLocation) { try square.converting(contour: c, index: i, to: .smooth) }
        }
        let penless = Path(elements: [.line(to: pt(1, 1))])
        for (path, e, t) in [(square, 0, 0.5), (square, 5, 0.5), (square, -1, 0.5), (square, 1, 1.5), (square, 1, .nan), (penless, 0, 0.5)] {
            #expect(throws: GeometryError.invalidLocation) { try path.inserting(at: PathLocation(element: e, t: t, point: pt(0, 0), distance: 0)) }
        }
    }
}
