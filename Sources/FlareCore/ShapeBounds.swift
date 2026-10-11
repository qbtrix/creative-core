// ShapeBounds.swift: tight axis-aligned bounds of a shape's outline.
//
// Lines contribute their end points. Quadratic and cubic segments contribute
// their end points plus the curve points where dx/dt or dy/dt is zero for t in
// (0, 1), so the box hugs the curve rather than its control points. Points
// with non-finite coordinates are skipped instead of poisoning the box.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Shape {
    /// The tight box around `outline`, or nil when it has no finite points.
    public var bounds: Rect? {
        outline.bounds
    }
}

extension Path {
    /// The tight box around every element, or nil when there is no finite point.
    public var bounds: Rect? {
        var points: [Point] = []
        var current: Point?
        var subpathStart: Point?
        for element in elements {
            switch element {
            case .move(let to):
                points.append(to)
                current = to
                subpathStart = to
            case .line(let to):
                points.append(to)
                current = to
            case .quad(let control, let to):
                if let from = current {
                    for t in quadExtrema(from.x, control.x, to.x) + quadExtrema(from.y, control.y, to.y) {
                        points.append(quadPoint(from, control, to, t))
                    }
                }
                points.append(to)
                current = to
            case .cubic(let control1, let control2, let to):
                if let from = current {
                    let ts = cubicExtrema(from.x, control1.x, control2.x, to.x)
                        + cubicExtrema(from.y, control1.y, control2.y, to.y)
                    for t in ts {
                        points.append(cubicPoint(from, control1, control2, to, t))
                    }
                }
                points.append(to)
                current = to
            case .close:
                current = subpathStart
            }
        }
        return Rect(enclosing: points)
    }
}

/// Parameters in (0, 1) where the quadratic's derivative is zero on one axis.
private func quadExtrema(_ p0: Double, _ p1: Double, _ p2: Double) -> [Double] {
    let denom = p0 - 2 * p1 + p2
    guard denom != 0 else { return [] }
    return inUnitInterval([(p0 - p1) / denom])
}

/// Parameters in (0, 1) where the cubic's derivative is zero on one axis.
/// The derivative divided by 3 is a*t^2 + b*t + c.
private func cubicExtrema(_ p0: Double, _ p1: Double, _ p2: Double, _ p3: Double) -> [Double] {
    let a = -p0 + 3 * p1 - 3 * p2 + p3
    let b = 2 * (p0 - 2 * p1 + p2)
    let c = p1 - p0
    if a == 0 {
        guard b != 0 else { return [] }
        return inUnitInterval([-c / b])
    }
    let disc = b * b - 4 * a * c
    guard disc >= 0 else { return [] }
    // Stable form: avoids cancellation when b*b dominates 4*a*c.
    let q = -0.5 * (b + (b < 0 ? -1 : 1) * disc.squareRoot())
    var roots = [q / a]
    if q != 0 {
        roots.append(c / q)
    }
    return inUnitInterval(roots)
}

private func inUnitInterval(_ ts: [Double]) -> [Double] {
    ts.filter { $0.isFinite && $0 > 0 && $0 < 1 }
}

private func quadPoint(_ p0: Point, _ p1: Point, _ p2: Point, _ t: Double) -> Point {
    let u = 1 - t
    return Point(
        x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
        y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
    )
}

private func cubicPoint(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point, _ t: Double) -> Point {
    let u = 1 - t
    let w0 = u * u * u
    let w1 = 3 * u * u * t
    let w2 = 3 * u * t * t
    let w3 = t * t * t
    return Point(
        x: w0 * p0.x + w1 * p1.x + w2 * p2.x + w3 * p3.x,
        y: w0 * p0.y + w1 * p1.y + w2 * p2.y + w3 * p3.y
    )
}
