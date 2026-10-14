// PathBuilders.swift: closed paths for the stage's shape tools, built from a
// rect in scene space (y down). Polygon and star live in
// PathBuilders+Polygon.swift.
//
// Invariants:
// - a corner radius clamps to [0, half the rect's short side]
// - quarter arcs are cubics with handles kappa * radius, kappa = 0.5522847498
// - a non-finite rect or radius throws GeometryError.nonFinite; a zero-width
//   or zero-height rect gives a degenerate path with finite points
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum PathBuilders {
    /// Handle length of a cubic quarter circle of radius 1.
    static let kappa = 0.5522847498

    /// The rect as a closed path, clockwise on screen from the top edge.
    /// `cornerRadius` clamps to [0, min(width, height) / 2]; 0 gives a move,
    /// four lines and a close, otherwise four lines and four cubic corners.
    ///
    /// Throws `GeometryError.nonFinite` when an edge of `rect` or
    /// `cornerRadius` is NaN or infinite.
    public static func rectangle(in rect: Rect, cornerRadius: Double = 0) throws -> Path {
        let box = try BuilderBox(rect)
        guard cornerRadius.isFinite else { throw GeometryError.nonFinite }
        let r = Swift.min(Swift.max(cornerRadius, 0), Swift.min(box.halfWidth, box.halfHeight))
        let (x0, y0, x1, y1) = (box.minX, box.minY, box.maxX, box.maxY)
        guard r > 0 else {
            let corners = [Point(x: x0, y: y0), Point(x: x1, y: y0), Point(x: x1, y: y1), Point(x: x0, y: y1)]
            return Path(polyline: corners + [corners[0]], closed: true)
        }
        let k = kappa * r
        return Path(elements: [
            .move(to: Point(x: x0 + r, y: y0)),
            .line(to: Point(x: x1 - r, y: y0)),
            .cubic(control1: Point(x: x1 - r + k, y: y0), control2: Point(x: x1, y: y0 + r - k), to: Point(x: x1, y: y0 + r)),
            .line(to: Point(x: x1, y: y1 - r)),
            .cubic(control1: Point(x: x1, y: y1 - r + k), control2: Point(x: x1 - r + k, y: y1), to: Point(x: x1 - r, y: y1)),
            .line(to: Point(x: x0 + r, y: y1)),
            .cubic(control1: Point(x: x0 + r - k, y: y1), control2: Point(x: x0, y: y1 - r + k), to: Point(x: x0, y: y1 - r)),
            .line(to: Point(x: x0, y: y0 + r)),
            .cubic(control1: Point(x: x0, y: y0 + r - k), control2: Point(x: x0 + r - k, y: y0), to: Point(x: x0 + r, y: y0)),
            .close,
        ])
    }

    /// The ellipse inscribed in the rect: a move to the top midpoint, four
    /// cubics through the right, bottom, left and top midpoints, and a close.
    ///
    /// Throws `GeometryError.nonFinite` when an edge of `rect` is NaN or infinite.
    public static func ellipse(in rect: Rect) throws -> Path {
        let box = try BuilderBox(rect)
        let (x0, y0, x1, y1) = (box.minX, box.minY, box.maxX, box.maxY)
        let (cx, cy) = (box.centerX, box.centerY)
        let kx = kappa * box.halfWidth
        let ky = kappa * box.halfHeight
        return Path(elements: [
            .move(to: Point(x: cx, y: y0)),
            .cubic(control1: Point(x: cx + kx, y: y0), control2: Point(x: x1, y: cy - ky), to: Point(x: x1, y: cy)),
            .cubic(control1: Point(x: x1, y: cy + ky), control2: Point(x: cx + kx, y: y1), to: Point(x: cx, y: y1)),
            .cubic(control1: Point(x: cx - kx, y: y1), control2: Point(x: x0, y: cy + ky), to: Point(x: x0, y: cy)),
            .cubic(control1: Point(x: x0, y: cy - ky), control2: Point(x: cx - kx, y: y0), to: Point(x: cx, y: y0)),
            .close,
        ])
    }
}

/// A rect with ordered, finite edges for the path builders. Halves are taken
/// before subtracting, so edges near the Double limit don't overflow.
struct BuilderBox {
    let minX: Double
    let minY: Double
    let maxX: Double
    let maxY: Double

    /// Throws `GeometryError.nonFinite` when an edge is NaN or infinite.
    init(_ rect: Rect) throws {
        let edges = [rect.minX, rect.minY, rect.maxX, rect.maxY]
        guard edges.allSatisfy(\.isFinite) else { throw GeometryError.nonFinite }
        minX = Swift.min(rect.minX, rect.maxX)
        maxX = Swift.max(rect.minX, rect.maxX)
        minY = Swift.min(rect.minY, rect.maxY)
        maxY = Swift.max(rect.minY, rect.maxY)
    }

    var halfWidth: Double { maxX / 2 - minX / 2 }
    var halfHeight: Double { maxY / 2 - minY / 2 }
    var centerX: Double { minX / 2 + maxX / 2 }
    var centerY: Double { minY / 2 + maxY / 2 }
}
