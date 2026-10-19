// PathEdit.swift: point editing on a `Path`: the anchors view, nearest point,
// inserting, removing and converting an anchor.
//
// Invariants:
// - `Path(contours: p.contours)` draws the same shape as `p`
// - inserting a point never moves the drawn shape
// - a bad contour, anchor or element index, or a t outside 0...1, throws
//   GeometryError.invalidLocation
//
// ponytail: stubs until PG-4; the throwing ones throw GeometryError.notBuilt
// with their own name, `contours` is empty and `init(contours:)` is empty.

extension Path {
    /// The path as contours of anchors. Quads are raised to cubics; a handle
    /// equal to its point is nil.
    public var contours: [PathContour] {
        []
    }

    /// The path that draws `contours`: a move per contour, a line where both
    /// facing handles are nil, a cubic otherwise, and a close when `closed`.
    public init(contours: [PathContour]) {
        self.init(elements: [])
    }

    /// The point on the path closest to `p`, curves searched to within
    /// `tolerance`; nil for an empty path.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance and
    /// `GeometryError.nonFinite` for a non-finite `p`.
    public func nearest(to p: Point, tolerance: Double) throws -> PathLocation? {
        throw GeometryError.notBuilt("nearest(to:tolerance:)")
    }

    /// The path with a new anchor at `location`, its element split there by
    /// de Casteljau so the drawn shape does not change.
    ///
    /// Throws `GeometryError.invalidLocation` when `location.element` is not a
    /// drawing element or `location.t` is outside 0...1.
    public func inserting(at location: PathLocation) throws -> Path {
        throw GeometryError.notBuilt("inserting(at:)")
    }

    /// The path without anchor `index` of contour `contour`. Its neighbours keep
    /// their outer handles and join as one segment; removing a contour's last
    /// anchor removes the contour.
    ///
    /// Throws `GeometryError.invalidLocation` for an index out of range.
    public func removingAnchor(contour: Int, index: Int) throws -> Path {
        throw GeometryError.notBuilt("removingAnchor(contour:index:)")
    }

    /// The path with anchor `index` of contour `contour` made `kind`: corner
    /// drops both handles, smooth lines them up, symmetric also equalizes them.
    ///
    /// Throws `GeometryError.invalidLocation` for an index out of range.
    public func converting(contour: Int, index: Int, to kind: AnchorKind) throws -> Path {
        throw GeometryError.notBuilt("converting(contour:index:to:)")
    }
}
