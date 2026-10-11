// PathFlattening.swift: turn a Path into straight polylines.
//
// Each subpath becomes one polyline: `move` starts a new one and `close`
// repeats the subpath's first point. Lines are copied as they are. Quads are
// raised to cubics exactly, and cubics are split in half (de Casteljau) until
// both control points lie within `tolerance` of the chord. The curve stays
// inside its control hull, so every curve point is then within `tolerance` of
// the chord, and every chord point is within `tolerance` of the curve.
//
// Splitting stops at `maxDepth` halvings (at most 2^maxDepth segments per
// curve), so huge or non-finite coordinates cannot loop forever; there the
// tolerance is best effort.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Path {
    /// Polylines approximating the path, one per subpath, each within
    /// `tolerance` of the true curve. Throws `GeometryError.invalidTolerance`
    /// when `tolerance` is not a finite number above zero.
    public func flattened(tolerance: Double) throws -> [[Point]] {
        guard tolerance.isFinite, tolerance > 0 else { throw GeometryError.invalidTolerance }
        var result: [[Point]] = []
        var current: [Point] = []
        var subpathStart: Point?

        func finish() {
            if !current.isEmpty { result.append(current) }
            current = []
        }
        // Drawing after a close continues from the subpath start, as a new polyline.
        func begin(at fallback: Point) -> Point {
            if let last = current.last { return last }
            let start = subpathStart ?? fallback
            current = [start]
            subpathStart = start
            return start
        }

        for element in elements {
            switch element {
            case .move(let to):
                finish()
                current = [to]
                subpathStart = to
            case .line(let to):
                _ = begin(at: to)
                current.append(to)
            case .quad(let control, let to):
                let from = begin(at: to)
                let c1 = Point(x: from.x + 2 * (control.x - from.x) / 3, y: from.y + 2 * (control.y - from.y) / 3)
                let c2 = Point(x: to.x + 2 * (control.x - to.x) / 3, y: to.y + 2 * (control.y - to.y) / 3)
                flattenCubic(from, c1, c2, to, tolerance: tolerance, depth: 0, into: &current)
            case .cubic(let control1, let control2, let to):
                let from = begin(at: to)
                flattenCubic(from, control1, control2, to, tolerance: tolerance, depth: 0, into: &current)
            case .close:
                if let start = subpathStart, !current.isEmpty {
                    current.append(start)
                }
                finish()
            }
        }
        finish()
        return result
    }
}

private let maxDepth = 16

/// Appends the polyline for the cubic p0...p3, excluding p0, to `points`.
private func flattenCubic(
    _ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point,
    tolerance: Double, depth: Int, into points: inout [Point]
) {
    let flat = distance(p1, toSegment: p0, p3) <= tolerance && distance(p2, toSegment: p0, p3) <= tolerance
    if flat || depth >= maxDepth {
        points.append(p3)
        return
    }
    let p01 = midpoint(p0, p1), p12 = midpoint(p1, p2), p23 = midpoint(p2, p3)
    let p012 = midpoint(p01, p12), p123 = midpoint(p12, p23)
    let mid = midpoint(p012, p123)
    flattenCubic(p0, p01, p012, mid, tolerance: tolerance, depth: depth + 1, into: &points)
    flattenCubic(mid, p123, p23, p3, tolerance: tolerance, depth: depth + 1, into: &points)
}

private func midpoint(_ a: Point, _ b: Point) -> Point {
    Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

/// Distance from `p` to the closed segment a-b; NaN for non-finite input.
private func distance(_ p: Point, toSegment a: Point, _ b: Point) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    var t = 0.0
    if lengthSquared > 0 {
        t = Swift.min(1, Swift.max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    }
    let ex = p.x - (a.x + t * dx), ey = p.y - (a.y + t * dy)
    return (ex * ex + ey * ey).squareRoot()
}
