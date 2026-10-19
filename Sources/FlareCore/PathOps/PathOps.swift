// PathOps.swift: the value types the path operations in this folder share:
// the anchors view of a `Path` (contours of anchors with handles), a location
// on a path, and the trim and boolean modes.
//
// Invariants:
// - every type here is a plain value (Sendable, Hashable); the operations are
//   extensions on FlareCore's `Path`, never a second path type
// - a handle equal to its anchor's point is stored as nil
// - `PathLocation.element` indexes `Path.elements`; `t` is in 0...1

/// How an anchor's two handles relate.
public enum AnchorKind: String, Codable, Sendable, Hashable {
    /// The handles move freely, or there are none: the path may turn sharply here.
    case corner
    /// The handles lie on one line through the point, so the path turns smoothly.
    case smooth
    /// Smooth, and both handles have the same length.
    case symmetric
}

/// One on-curve point of a contour with its incoming and outgoing handles.
/// A nil handle means the segment on that side leaves the point straight.
public struct PathAnchor: Codable, Sendable, Hashable {
    public var point: Point
    /// Control point of the segment arriving at `point`.
    public var handleIn: Point?
    /// Control point of the segment leaving `point`.
    public var handleOut: Point?
    public var kind: AnchorKind

    public init(point: Point, handleIn: Point? = nil, handleOut: Point? = nil, kind: AnchorKind = .corner) {
        self.point = point
        self.handleIn = handleIn
        self.handleOut = handleOut
        self.kind = kind
    }
}

/// One subpath as anchors; `closed` joins the last anchor back to the first.
public struct PathContour: Codable, Sendable, Hashable {
    public var anchors: [PathAnchor]
    public var closed: Bool

    public init(anchors: [PathAnchor], closed: Bool) {
        self.anchors = anchors
        self.closed = closed
    }
}

/// A point on a path: drawing element `element` of `Path.elements` at
/// parameter `t` (0...1), the `point` there and its `distance` from the query.
public struct PathLocation: Sendable, Hashable {
    public var element: Int
    public var t: Double
    public var point: Point
    public var distance: Double

    public init(element: Int, t: Double, point: Point, distance: Double) {
        self.element = element
        self.t = t
        self.point = point
        self.distance = distance
    }
}

/// How `Path.trimmed` maps start and end onto a path with several contours.
public enum TrimMode: String, Codable, Sendable, Hashable {
    /// One ruler along every contour in order.
    case together
    /// Each contour is trimmed by its own length.
    case eachContour
}

/// The set operation `Path.combine` applies to two filled areas: inside
/// either (union), the first but not the second (subtract), both
/// (intersect), or exactly one (exclude).
public enum BooleanOp: String, Codable, Sendable, Hashable {
    case union, subtract, intersect, exclude
}
