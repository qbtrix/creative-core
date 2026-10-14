// Path.swift: vector paths with straight and curved segments.
//
// A Path is a list of drawing elements in order. Each element's end point is
// the start point of the next. `move` starts a new subpath; `close` joins the
// current subpath back to its start.
//
// Encoding uses the synthesized enum Codable, e.g. {"cubic":{"control1":..,
// "control2":..,"to":..}} and {"close":{}}, matching how Easing is stored.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum PathElement: Codable, Sendable, Hashable {
    case move(to: Point)
    case line(to: Point)
    /// Quadratic Bezier from the current point through `control` to `to`.
    case quad(control: Point, to: Point)
    /// Cubic Bezier from the current point with two control points to `to`.
    case cubic(control1: Point, control2: Point, to: Point)
    case close
}

public struct Path: Codable, Sendable, Hashable {
    public var elements: [PathElement]

    public init(elements: [PathElement] = []) {
        self.elements = elements
    }

    /// The straight-line path through `points`: a move to the first point,
    /// lines to the rest, and a close if `closed`. Empty points give an empty path.
    public init(polyline points: [Point], closed: Bool) {
        guard let start = points.first else {
            self.elements = []
            return
        }
        var elements: [PathElement] = [.move(to: start)]
        for p in points.dropFirst() {
            elements.append(.line(to: p))
        }
        if closed {
            elements.append(.close)
        }
        self.elements = elements
    }
}

extension Path {
    /// Most line segments one curve element is split into, so a huge curve or
    /// a tiny tolerance cannot exhaust memory.
    public static let maxFlattenSegments = 4096

    /// The path as polylines, one per subpath. `move` starts a new polyline,
    /// `close` repeats the subpath's first point. Each quad or cubic is split
    /// into equal parameter steps, enough by Wang's formula that every point of
    /// the curve is within `tolerance` of the polyline (up to
    /// `maxFlattenSegments` per element). A drawing element with no current
    /// point starts a polyline at its end point.
    ///
    /// Throws `GeometryError.invalidTolerance` when tolerance <= 0 or non-finite.
    public func flattened(tolerance: Double) throws -> [[Point]] {
        guard tolerance.isFinite, tolerance > 0 else { throw GeometryError.invalidTolerance }
        var result: [[Point]] = []
        var current: [Point] = []
        var subpathStart: Point?

        func finish() {
            if !current.isEmpty { result.append(current) }
            current = []
        }

        for element in elements {
            switch element {
            case .move(let to):
                finish()
                current = [to]
                subpathStart = to
                continue
            case .close:
                if let start = subpathStart, !current.isEmpty {
                    current.append(start)
                }
                finish()
                continue
            default:
                break
            }
            // A drawing element: needs a start point.
            guard let from = current.last ?? subpathStart else {
                if let end = element.endPoint {
                    current = [end]
                    subpathStart = end
                }
                continue
            }
            if current.isEmpty {
                current = [from]
            }
            switch element {
            case .line(let to):
                current.append(to)
            case .quad(let c, let to):
                // Wang's bound for degree 2: n^2 >= (2*1/8) * |p0 - 2c + p2| / tol.
                let m = norm(from.x - 2 * c.x + to.x, from.y - 2 * c.y + to.y)
                let n = Self.segmentCount((0.25 * m / tolerance).squareRoot())
                for i in 1...n {
                    current.append(quadAt(from, c, to, Double(i) / Double(n)))
                }
            case .cubic(let c1, let c2, let to):
                // Wang's bound for degree 3: n^2 >= (3*2/8) * max second difference / tol.
                let m = max(
                    norm(from.x - 2 * c1.x + c2.x, from.y - 2 * c1.y + c2.y),
                    norm(c1.x - 2 * c2.x + to.x, c1.y - 2 * c2.y + to.y)
                )
                let n = Self.segmentCount((0.75 * m / tolerance).squareRoot())
                for i in 1...n {
                    current.append(cubicAt(from, c1, c2, to, Double(i) / Double(n)))
                }
            case .move, .close:
                break
            }
        }
        finish()
        return result
    }

    /// `ceil(raw)` clamped to 1...maxFlattenSegments; NaN gives 1.
    static func segmentCount(_ raw: Double) -> Int {
        guard raw.isFinite else { return raw == .infinity ? maxFlattenSegments : 1 }
        let clamped = Swift.min(Swift.max(raw.rounded(.up), 1), Double(maxFlattenSegments))
        return Int(clamped)
    }
}

extension Path {
    /// The path with every point of every element mapped by `m`. An affine
    /// map takes a curve to the same kind of curve, so cubics stay cubics.
    public func transformed(by m: Matrix) -> Path {
        Path(elements: elements.map { element in
            switch element {
            case .move(let to): .move(to: m.apply(to))
            case .line(let to): .line(to: m.apply(to))
            case .quad(let c, let to): .quad(control: m.apply(c), to: m.apply(to))
            case .cubic(let c1, let c2, let to): .cubic(control1: m.apply(c1), control2: m.apply(c2), to: m.apply(to))
            case .close: .close
            }
        })
    }
}

extension PathElement {
    /// Where the element leaves the pen; nil for `close`.
    var endPoint: Point? {
        switch self {
        case .move(let to), .line(let to), .quad(_, let to), .cubic(_, _, let to): to
        case .close: nil
        }
    }
}

/// Length of the vector (x, y).
func norm(_ x: Double, _ y: Double) -> Double {
    (x * x + y * y).squareRoot()
}

private func quadAt(_ p0: Point, _ p1: Point, _ p2: Point, _ t: Double) -> Point {
    let u = 1 - t
    return Point(
        x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
        y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y
    )
}

private func cubicAt(_ p0: Point, _ p1: Point, _ p2: Point, _ p3: Point, _ t: Double) -> Point {
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

extension Shape {
    /// The geometry to draw: `path` when it is set, otherwise the polyline
    /// through `points`.
    public var outline: Path {
        path ?? Path(polyline: points, closed: closed)
    }
}
