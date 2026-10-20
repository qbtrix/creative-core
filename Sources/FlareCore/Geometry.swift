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
    /// A coordinate, size or ratio that is NaN or infinite. Fix it by
    /// passing finite values.
    case nonFinite
    /// A polygon side count or star point count below 3 or above
    /// `PathBuilders.maxSides`. Fix it by passing a count in 3...maxSides.
    case invalidSides
    /// A finite star inner ratio outside (0, 1]. Fix it by passing a ratio
    /// greater than 0 and at most 1.
    case invalidRatio
    /// Not thrown: every path operation is built. Kept for source
    /// compatibility with the path-geometry stubs (PG-a), which threw it with
    /// the operation's name as the payload.
    case notBuilt(String)
    /// A contour, anchor or element index that is out of range, or a curve
    /// parameter outside 0...1. Fix it by passing a location on the path.
    case invalidLocation
    /// A dash pattern that is empty, sums to zero or past Double's range, has
    /// a negative or non-finite entry, or has more than 64 entries.
    case invalidPattern
    /// A path operation past one of its work limits. The payload is always
    /// the limit that was passed, never a count: `Path.maxBooleanVertices`
    /// (flattened vertices, from `combine` and `outlined`),
    /// `Path.maxBooleanWork` (edge pair tests, crossing cuts and ray-cast
    /// steps, from `combine`), `Path.maxMeasurePoints` (flattened points, from
    /// `length`, `sample`, `trimmed` and `dashed`) or `Path.maxDashSteps`
    /// (dash and gap entries, from `dashed`). Fix it by simplifying or
    /// splitting the input, a coarser tolerance, or a longer dash pattern.
    case tooComplex(Int)
    /// A finite stroke width or miter limit that is zero or negative, from
    /// `Path.outlined`. Fix it by passing values greater than 0.
    case invalidStroke
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
    /// The anchor point in the layer's own space: what rotation and scale turn about, and the point that lands
    /// on (x, y). 0, 0 by default, so a transform without one is the plain translate, rotate, scale.
    public var anchorX: Double
    public var anchorY: Double

    public init(x: Double = 0, y: Double = 0, scaleX: Double = 1, scaleY: Double = 1, rotation: Double = 0,
                anchorX: Double = 0, anchorY: Double = 0) {
        self.x = x
        self.y = y
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.rotation = rotation
        self.anchorX = anchorX
        self.anchorY = anchorY
    }

    public static let identity = Transform()

    /// translate * rotate * scale * translate(-anchor): the anchor moves to the origin, then scale, rotate and
    /// move. A 0, 0 anchor skips the last multiply, so unanchored matrices are bit for bit what they were.
    public var matrix: Matrix {
        let placed = Matrix.translation(x: x, y: y) * Matrix.rotation(degrees: rotation) * Matrix.scale(x: scaleX, y: scaleY)
        return anchorX == 0 && anchorY == 0 ? placed : placed * Matrix.translation(x: -anchorX, y: -anchorY)
    }

    private enum CodingKeys: String, CodingKey { case x, y, scaleX, scaleY, rotation, anchorX, anchorY }

    /// Files written before anchors existed decode with a 0, 0 anchor.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
                  scaleX: try c.decode(Double.self, forKey: .scaleX), scaleY: try c.decode(Double.self, forKey: .scaleY),
                  rotation: try c.decode(Double.self, forKey: .rotation),
                  anchorX: try c.decodeIfPresent(Double.self, forKey: .anchorX) ?? 0,
                  anchorY: try c.decodeIfPresent(Double.self, forKey: .anchorY) ?? 0)
    }

    /// The anchor is written only when it isn't 0, 0, so an unanchored transform writes the bytes it always did.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(scaleX, forKey: .scaleX)
        try c.encode(scaleY, forKey: .scaleY)
        try c.encode(rotation, forKey: .rotation)
        if anchorX != 0 || anchorY != 0 {
            try c.encode(anchorX, forKey: .anchorX)
            try c.encode(anchorY, forKey: .anchorY)
        }
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
