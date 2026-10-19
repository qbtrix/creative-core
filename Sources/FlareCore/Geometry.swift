// Geometry.swift: 2D affine `Matrix` and the `Transform` (position, scale,
// rotation) that layers and instances use to place content, plus the
// axis-aligned `Rect` used for bounds.
//
// Invariants:
// - a Matrix maps (x, y) to (a*x + c*y + tx, b*x + d*y + ty)
// - `m * n` applies n first, then m: (m * n).apply(p) == m.apply(n.apply(p))
// - inverted() never returns non-finite values: a singular or degenerate
//   matrix throws GeometryError.singularMatrix
// - Transform.matrix is translate * rotate * scale, rotation in degrees,
//   clockwise on screen (scene space is y down; rotate 90 maps (1, 0) to (0, 1))
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// Errors from geometry: matrix inversion, flattening, the path builders and
/// the path operations in `PathOps/`.
public enum GeometryError: Error, Equatable, Sendable {
    /// A matrix with zero or non-finite determinant, e.g. a zero scale, that has no inverse.
    case singularMatrix
    /// A flattening tolerance that is zero, negative or not finite.
    case invalidTolerance
    /// A coordinate, size or ratio that is NaN or infinite.
    case nonFinite
    /// A polygon side count or star point count below 3 or above
    /// `PathBuilders.maxSides`. Fix it by passing a count in 3...maxSides.
    case invalidSides
    /// A finite star inner ratio outside (0, 1]. Fix it by passing a ratio
    /// greater than 0 and at most 1.
    case invalidRatio
    /// A path operation whose body has not landed yet; the payload names it,
    /// e.g. "length(tolerance:)".
    case notBuilt(String)
    /// A contour, anchor or element index that is out of range, or a curve
    /// parameter outside 0...1. Fix it by passing a location on the path.
    case invalidLocation
    /// A dash pattern that is empty, sums to zero, has a negative or
    /// non-finite entry, or has more than 64 entries.
    case invalidPattern
    /// A path operation past one of its work limits. From `Path.combine` the
    /// payload is either the flattened vertex count, when it passes
    /// `Path.maxBooleanVertices`, or `Path.maxBooleanWork`, when edge pair
    /// tests, crossing cuts and ray-cast steps together pass that cap. From
    /// `Path.dashed` it is `Path.maxDashSteps` (1,000,000), the most dash and
    /// gap entries one call walks. Fix it by simplifying or splitting the input,
    /// or with a longer dash pattern.
    case tooComplex(Int)
}

public struct Matrix: Codable, Sendable, Hashable {
    public var a: Double
    public var b: Double
    public var c: Double
    public var d: Double
    public var tx: Double
    public var ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
        self.tx = tx
        self.ty = ty
    }

    public static let identity = Matrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(x: Double, y: Double) -> Matrix {
        Matrix(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y)
    }

    public static func scale(x: Double, y: Double) -> Matrix {
        Matrix(a: x, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }

    /// Rotation by `degrees`. Multiples of 90 are exact (no 6e-17 residue).
    public static func rotation(degrees: Double) -> Matrix {
        let (s, c) = sinCos(degrees: degrees)
        return Matrix(a: c, b: s, c: -s, d: c, tx: 0, ty: 0)
    }

    public var determinant: Double { a * d - b * c }

    public func apply(_ p: Point) -> Point {
        Point(x: a * p.x + c * p.y + tx, y: b * p.x + d * p.y + ty)
    }

    /// `lhs * rhs` applies `rhs` first, then `lhs`.
    public static func * (lhs: Matrix, rhs: Matrix) -> Matrix {
        Matrix(
            a: lhs.a * rhs.a + lhs.c * rhs.b,
            b: lhs.b * rhs.a + lhs.d * rhs.b,
            c: lhs.a * rhs.c + lhs.c * rhs.d,
            d: lhs.b * rhs.c + lhs.d * rhs.d,
            tx: lhs.a * rhs.tx + lhs.c * rhs.ty + lhs.tx,
            ty: lhs.b * rhs.tx + lhs.d * rhs.ty + lhs.ty
        )
    }

    public func inverted() throws -> Matrix {
        let det = determinant
        guard det != 0, det.isFinite else { throw GeometryError.singularMatrix }
        let inv = Matrix(
            a: d / det,
            b: -b / det,
            c: -c / det,
            d: a / det,
            tx: (c * ty - d * tx) / det,
            ty: (b * tx - a * ty) / det
        )
        let values = [inv.a, inv.b, inv.c, inv.d, inv.tx, inv.ty]
        guard values.allSatisfy(\.isFinite) else { throw GeometryError.singularMatrix }
        return inv
    }
}

public struct Transform: Codable, Sendable, Hashable {
    public var x: Double
    public var y: Double
    public var scaleX: Double
    public var scaleY: Double
    /// Degrees, clockwise on screen: scene space is y down, as the exporters draw it.
    public var rotation: Double

    public init(x: Double = 0, y: Double = 0, scaleX: Double = 1, scaleY: Double = 1, rotation: Double = 0) {
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
    }

    public static let identity = Transform()

    /// translate * rotate * scale: scale first, then rotate, then move.
    public var matrix: Matrix {
        Matrix.translation(x: x, y: y) * Matrix.rotation(degrees: rotation) * Matrix.scale(x: scaleX, y: scaleY)
    }
}

/// Axis-aligned rectangle given by its edges. `minX <= maxX` and
/// `minY <= maxY` hold for rects built with `Rect(enclosing:)`.
public struct Rect: Codable, Sendable, Hashable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// The smallest rect holding every finite point; nil when there is none.
    /// Points with a NaN or infinite coordinate are skipped.
    public init?(enclosing points: [Point]) {
        var rect: Rect?
        for p in points where p.x.isFinite && p.y.isFinite {
            if var r = rect {
                r.minX = Swift.min(r.minX, p.x)
                r.minY = Swift.min(r.minY, p.y)
                r.maxX = Swift.max(r.maxX, p.x)
                r.maxY = Swift.max(r.maxY, p.y)
                rect = r
            } else {
                rect = Rect(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
            }
        }
        guard let rect else { return nil }
        self = rect
    }

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }

    /// The same rect with `minX <= maxX` and `minY <= maxY`, whichever way
    /// it was dragged; nil when an edge is NaN or infinite.
    var normalized: Rect? {
        guard [minX, minY, maxX, maxY].allSatisfy(\.isFinite) else { return nil }
        return Rect(minX: Swift.min(minX, maxX), minY: Swift.min(minY, maxY),
                    maxX: Swift.max(minX, maxX), maxY: Swift.max(minY, maxY))
    }
}

/// Sine and cosine of an angle in degrees, exact at multiples of 90.
private func sinCos(degrees: Double) -> (Double, Double) {
    guard degrees.isFinite else { return (.nan, .nan) }
    let r = degrees.truncatingRemainder(dividingBy: 360)
    if r.truncatingRemainder(dividingBy: 90) == 0 {
        switch (Int(r) + 360) % 360 {
        case 90: return (1, 0)
        case 180: return (0, -1)
        case 270: return (-1, 0)
        default: return (0, 1)
        }
    }
    let radians = r * Double.pi / 180
    return (sin(radians), cos(radians))
}
