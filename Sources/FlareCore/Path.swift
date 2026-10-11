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

extension Shape {
    /// The geometry to draw: `path` when it is set, otherwise the polyline
    /// through `points`.
    public var outline: Path {
        path ?? Path(polyline: points, closed: closed)
    }
}
