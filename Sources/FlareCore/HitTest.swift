// HitTest.swift: point-in-shape tests under even-odd and nonzero fill rules.
//
// The outline is flattened to polygons, one per closed subpath, and the point
// is tested by summing signed edge crossings of a ray running in +x. Edges use
// a half-open rule on y so a ray through a vertex counts it once. Subpaths
// without a `close` fill nothing, so open shapes contain no point.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// How overlapping or self-intersecting regions are filled.
public enum FillRule: String, Codable, Sendable, Hashable {
    /// Inside when a ray from the point crosses the outline an odd number of times.
    case evenOdd
    /// Inside when the outline winds around the point a nonzero number of times.
    case nonZero
}

extension Shape {
    /// Whether `point` lies in the filled area of `outline` under `rule`.
    /// Open shapes and non-finite points give false.
    public func contains(_ point: Point, rule: FillRule) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        var winding = 0
        for polygon in outline.closedPolygons() {
            winding += windingNumber(of: point, around: polygon)
        }
        switch rule {
        case .evenOdd: return winding % 2 != 0
        case .nonZero: return winding != 0
        }
    }
}

/// Segments per curve when flattening.
// ponytail: fixed-step subdivision; switch to Path.flattened(tolerance:) once G24 lands.
private let curveSteps = 32

extension Path {
    /// One polygon per subpath that ends in `close`, with curves subdivided.
    func closedPolygons() -> [[Point]] {
        var polygons: [[Point]] = []
        var current: [Point] = []
        for element in elements {
            switch element {
            case .move(let to):
                current = [to]
            case .line(let to):
                current.append(to)
            case .quad(let control, let to):
                if let from = current.last {
                    for i in 1..<curveSteps {
                        let t = Double(i) / Double(curveSteps), u = 1 - t
                        current.append(Point(
                            x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                            y: u * u * from.y + 2 * u * t * control.y + t * t * to.y))
                    }
                }
                current.append(to)
            case .cubic(let control1, let control2, let to):
                if let from = current.last {
                    for i in 1..<curveSteps {
                        let t = Double(i) / Double(curveSteps), u = 1 - t
                        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                        current.append(Point(
                            x: w0 * from.x + w1 * control1.x + w2 * control2.x + w3 * to.x,
                            y: w0 * from.y + w1 * control1.y + w2 * control2.y + w3 * to.y))
                    }
                }
                current.append(to)
            case .close:
                if current.count >= 3 {
                    polygons.append(current)
                }
                // A new subpath after close starts at the closed subpath's start.
                current = current.first.map { [$0] } ?? []
            }
        }
        return polygons
    }
}

/// Signed count of polygon edges crossing the ray from `p` toward +x.
/// Upward edges count +1, downward edges -1.
private func windingNumber(of p: Point, around polygon: [Point]) -> Int {
    guard var a = polygon.last else { return 0 }
    var winding = 0
    for b in polygon {
        defer { a = b }
        guard a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite else { continue }
        if a.y <= p.y {
            if b.y > p.y, side(a, b, p) > 0 { winding += 1 }
        } else if b.y <= p.y, side(a, b, p) < 0 {
            winding -= 1
        }
    }
    return winding
}

/// Positive when `p` is left of the line from `a` to `b`.
private func side(_ a: Point, _ b: Point, _ p: Point) -> Double {
    (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
}
