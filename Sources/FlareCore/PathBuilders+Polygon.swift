// PathBuilders+Polygon.swift: regular polygons and stars for the stage's
// shape tools, built on the ellipse inscribed in a rect (scene space, y down).
//
// Invariants:
// - a polygon has 3 to maxSides sides, a star 3 to maxSides points; any other
//   count throws GeometryError.invalidSides
// - a star's inner ratio is finite and in (0, 1]
// - the first vertex is the top centre of the rect; the rest run clockwise on
//   screen, angle 2πk / n from the top
// - a star's inner vertices sit at the inner ratio times the outer radii
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

extension PathBuilders {
    /// The most sides a polygon, or points a star, may have. It bounds the
    /// path an untrusted count can allocate.
    public static let maxSides = 1_000

    /// The regular polygon inscribed in the ellipse inscribed in `rect`: a
    /// move to the top centre, lines to the other `sides - 1` vertices
    /// clockwise on screen, and a close.
    ///
    /// Throws `GeometryError.invalidSides` when `sides` is below 3 or above
    /// `maxSides`, and `GeometryError.nonFinite` when an edge of `rect` is NaN
    /// or infinite.
    public static func polygon(in rect: Rect, sides: Int) throws -> Path {
        let box = try BuilderBox(rect)
        guard sides >= 3, sides <= maxSides else { throw GeometryError.invalidSides }
        let vertices = (0..<sides).map { k in
            vertex(box, step: k, of: sides, scale: 1)
        }
        return Path(polyline: vertices, closed: true)
    }

    /// The star inscribed in the ellipse inscribed in `rect`: `2 * points`
    /// vertices alternating outer (on the ellipse) and inner (at `innerRatio`
    /// times the ellipse's radii), the first outer at the top centre, joined
    /// clockwise on screen by lines and closed. A ratio of 1 gives a polygon
    /// with `2 * points` sides.
    ///
    /// Throws `GeometryError.nonFinite` when an edge of `rect` or `innerRatio`
    /// is NaN or infinite, and `GeometryError.invalidSides` when `points` is
    /// below 3 or above `maxSides`, or when a finite `innerRatio` is outside
    /// (0, 1]: such a ratio folds the inner vertices onto or through the
    /// centre, or past the outer ones, so the star's shape is invalid.
    public static func star(in rect: Rect, points: Int, innerRatio: Double) throws -> Path {
        let box = try BuilderBox(rect)
        guard innerRatio.isFinite else { throw GeometryError.nonFinite }
        guard points >= 3, points <= maxSides else { throw GeometryError.invalidSides }
        guard innerRatio > 0, innerRatio <= 1 else { throw GeometryError.invalidSides }
        let count = 2 * points
        let vertices = (0..<count).map { k in
            vertex(box, step: k, of: count, scale: k.isMultiple(of: 2) ? 1 : innerRatio)
        }
        return Path(polyline: vertices, closed: true)
    }

    /// Vertex `step` of `count` evenly spaced around the box's inscribed
    /// ellipse, scaled toward the centre by `scale`; step 0 is the top centre
    /// and steps run clockwise on screen (y down).
    private static func vertex(_ box: BuilderBox, step: Int, of count: Int, scale: Double) -> Point {
        let angle = 2 * Double.pi * Double(step) / Double(count)
        return Point(
            x: box.centerX + scale * box.halfWidth * sin(angle),
            y: box.centerY - scale * box.halfHeight * cos(angle)
        )
    }
}
