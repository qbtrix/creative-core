// Easing.swift: easing curves that map tween progress (0...1) to eased
// progress. `linear`, CSS-style `cubicBezier(x1, y1, x2, y2)`, and `hold`
// (stays at 0 until progress reaches 1, i.e. a step at the next keyframe).
//
// Invariants:
// - value(at:) is total: any Double in (NaN, infinities, out of range) gives a
//   finite result, and the endpoints are exact (0 -> 0, 1 -> 1)
// - x1/x2 are clamped to 0...1 so the curve is a function of x; y1/y2 may
//   leave 0...1 (overshoot), but a non-finite control point falls back to linear
// - the solver is Newton's method with a bisection fallback, so it always
//   terminates in a bounded number of steps
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum Easing: Codable, Sendable, Hashable {
    case linear
    case cubicBezier(x1: Double, y1: Double, x2: Double, y2: Double)
    /// Keeps the keyframe's value until the next keyframe, then jumps.
    case hold

    public static let ease = Easing.cubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    public static let easeIn = Easing.cubicBezier(x1: 0.42, y1: 0, x2: 1, y2: 1)
    public static let easeOut = Easing.cubicBezier(x1: 0, y1: 0, x2: 0.58, y2: 1)
    public static let easeInOut = Easing.cubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)

    /// Eased progress for `progress`, clamped to 0...1 on the way in.
    public func value(at progress: Double) -> Double {
        guard progress > 0 else { return 0 }  // also catches NaN
        guard progress < 1 else { return 1 }
        switch self {
        case .linear:
            return progress
        case .hold:
            return 0
        case let .cubicBezier(x1, y1, x2, y2):
            guard let curve = CubicBezier(x1: x1, y1: y1, x2: x2, y2: y2) else { return progress }
            return curve.y(curve.parameter(forX: progress))
        }
    }
}

/// Unit cubic Bezier from (0,0) to (1,1) with control points (x1,y1), (x2,y2),
/// in polynomial form: x(s) = ((ax*s + bx)*s + cx)*s, same for y.
struct CubicBezier {
    let ax, bx, cx, ay, by, cy: Double

    init?(x1: Double, y1: Double, x2: Double, y2: Double) {
        guard x1.isFinite, y1.isFinite, x2.isFinite, y2.isFinite else { return nil }
        let x1 = min(max(x1, 0), 1)
        let x2 = min(max(x2, 0), 1)
        cx = 3 * x1
        bx = 3 * (x2 - x1) - cx
        ax = 1 - cx - bx
        cy = 3 * y1
        by = 3 * (y2 - y1) - cy
        ay = 1 - cy - by
    }

    func x(_ s: Double) -> Double { ((ax * s + bx) * s + cx) * s }
    func y(_ s: Double) -> Double { ((ay * s + by) * s + cy) * s }
    func dx(_ s: Double) -> Double { (3 * ax * s + 2 * bx) * s + cx }

    /// The curve parameter s in 0...1 with x(s) == x (to ~1e-12).
    func parameter(forX x: Double) -> Double {
        // Newton: fast when the slope is healthy.
        var s = x
        for _ in 0..<8 {
            let err = self.x(s) - x
            if abs(err) < 1e-12 { return s }
            let d = dx(s)
            if abs(d) < 1e-9 { break }
            let next = s - err / d
            if !(next >= 0 && next <= 1) { break }
            s = next
        }
        // Bisection: always converges because x(s) is monotonic for x1, x2 in 0...1.
        var lo = 0.0
        var hi = 1.0
        s = x
        for _ in 0..<64 {
            let v = self.x(s)
            if abs(v - x) < 1e-12 { break }
            if v < x { lo = s } else { hi = s }
            s = (lo + hi) / 2
        }
        return s
    }
}
