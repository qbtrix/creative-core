// PathEdit.swift: point editing on a `Path`: the anchors view, nearest point,
// inserting, removing and converting an anchor.
//
// Invariants:
// - `Path(contours: p.contours)` draws the same shape as `p`
// - inserting a point never moves the drawn shape
// - a bad contour, anchor or element index, or a t outside 0...1, throws
//   GeometryError.invalidLocation

extension Path {
    /// The path as contours of anchors. Quads are raised to cubics; a handle
    /// equal to its point is nil; a curve closing onto the start folds into it.
    public var contours: [PathContour] {
        var result: [PathContour] = [], current: PathContour?
        func start(_ p: Point) {
            if let c = current { result.append(c) }
            current = PathContour(anchors: [PathAnchor(point: p)], closed: false)
        }
        for (element, pen) in zip(elements, pens()) {
            guard let to = element.endPoint else { current?.close(); continue }
            guard let from = pen.pen else { start(to); continue }
            if current?.closed ?? true { start(from) }
            if case .line = element {
                current?.append(nil, nil, to)
            } else if let c = Self.cubic(element, from: from, start: nil) {
                current?.append(c.1, c.2, to)
            }
        }
        if let c = current { result.append(c) }
        return result.map { c in PathContour(anchors: c.anchors.map { $0.measured }, closed: c.closed) }
    }

    /// The path that draws `contours`: a move per contour, a line where both
    /// facing handles are nil, a cubic otherwise, and a close when `closed`.
    /// Each anchor's `kind` is not read: the shape comes from points and
    /// handles alone, and `contours` re-derives kind from the handles.
    public init(contours: [PathContour]) {
        var elements: [PathElement] = []
        for contour in contours {
            guard let first = contour.anchors.first else { continue }
            elements.append(.move(to: first.point))
            var previous = first
            for anchor in contour.anchors.dropFirst() {
                elements.append(Self.segment(previous, anchor))
                previous = anchor
            }
            guard contour.closed else { continue }
            if previous.handleOut != nil || first.handleIn != nil { elements.append(Self.segment(previous, first)) }
            elements.append(.close)
        }
        self.init(elements: elements)
    }

    /// The point on the path closest to `p`, curves searched to within
    /// `tolerance`; nil for an empty path.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance and
    /// `GeometryError.nonFinite` for a non-finite `p`.
    public func nearest(to p: Point, tolerance: Double) throws -> PathLocation? {
        guard tolerance.isFinite, tolerance > 0 else { throw GeometryError.invalidTolerance }
        guard p.isFinite else { throw GeometryError.nonFinite }
        var best: PathLocation?
        for (i, (element, pen)) in zip(elements, pens()).enumerated() {
            guard let from = pen.pen, let c = Self.cubic(element, from: from, start: pen.start) else { continue }
            let (t, point, distance) = Self.closest(c, to: p, tolerance: tolerance)
            if distance < best?.distance ?? .infinity { best = PathLocation(element: i, t: t, point: point, distance: distance) }
        }
        return best
    }

    /// The path with a new anchor at `location`, its element split there by
    /// de Casteljau so the drawn shape does not change. Only `location.element`
    /// and `location.t` are read; its point and distance are ignored.
    ///
    /// Throws `GeometryError.invalidLocation` when `location.element` is not a
    /// drawing element or `location.t` is outside 0...1.
    public func inserting(at location: PathLocation) throws -> Path {
        let i = location.element, t = location.t
        guard i >= 0, i < elements.count, t.isFinite, t >= 0, t <= 1,
              case let (from?, start) = pens()[i] else { throw GeometryError.invalidLocation }
        let parts: [PathElement]
        switch elements[i] {
        case .move: throw GeometryError.invalidLocation
        case .line(let to): parts = [.line(to: lerp(from, to, t)), .line(to: to)]
        case .close: parts = [.line(to: lerp(from, start ?? from, t)), .close]
        case .quad(let c, let to):
            parts = [.quad(control: lerp(from, c, t), to: quadAt(from, c, to, t)), .quad(control: lerp(c, to, t), to: to)]
        case .cubic(let p1, let p2, let to):
            let p01 = lerp(from, p1, t), p12 = lerp(p1, p2, t), p23 = lerp(p2, to, t)
            let p012 = lerp(p01, p12, t), p123 = lerp(p12, p23, t)
            parts = [.cubic(control1: p01, control2: p012, to: lerp(p012, p123, t)),
                     .cubic(control1: p123, control2: p23, to: to)]
        }
        var result = elements
        result.replaceSubrange(i...i, with: parts)
        return Path(elements: result)
    }

    /// The path without anchor `index` of contour `contour`. Its neighbours keep
    /// their outer handles and join as one segment; removing a contour's last
    /// anchor removes the contour.
    ///
    /// Throws `GeometryError.invalidLocation` for an index out of range.
    public func removingAnchor(contour: Int, index: Int) throws -> Path {
        var cs = contours
        try Self.checkAnchor(cs, contour, index)
        cs[contour].anchors.remove(at: index)
        if cs[contour].anchors.isEmpty { cs.remove(at: contour) }
        return Path(contours: cs)
    }

    /// The path with anchor `index` of contour `contour` made `kind`: corner
    /// drops both handles, smooth lines them up, symmetric also equalizes them.
    /// Smooth turns both onto their bisector, keeping lengths and sides; a
    /// missing handle starts a third of the way to its neighbour. With no usable
    /// arm (no handle and no distinct neighbour, as for a lone anchor) smooth
    /// and symmetric leave the anchor as it is, so the path draws unchanged; so
    /// does an arm whose length under- or overflows a Double. Handles that
    /// point the same way (a cusp) line up along the old out-arm.
    ///
    /// Throws `GeometryError.invalidLocation` for an index out of range.
    public func converting(contour: Int, index: Int, to kind: AnchorKind) throws -> Path {
        var cs = contours
        try Self.checkAnchor(cs, contour, index)
        let anchors = cs[contour].anchors, closed = cs[contour].closed, n = anchors.count
        var a = anchors[index]
        let p = a.point
        func arm(_ handle: Point?, _ j: Int) -> (Double, Double)? {
            let neighbour: Point? = anchors.indices.contains(j) || closed ? anchors[(j + n) % n].point : nil
            let q = handle ?? neighbour.map { lerp(p, $0, 1.0 / 3) }
            return q.flatMap { $0 == p ? nil : ($0.x - p.x, $0.y - p.y) }
        }
        let flip: ((Double, Double)) -> (Double, Double) = { (-$0.0, -$0.1) }
        if kind == .corner {
            (a.handleIn, a.handleOut) = (nil, nil)
        } else if let rawOut = arm(a.handleOut, index + 1) ?? arm(a.handleIn, index - 1).map(flip),
                  let rawIn = arm(a.handleIn, index - 1) ?? arm(a.handleOut, index + 1).map(flip) {
            let lengthIn = norm(rawIn.0, rawIn.1), lengthOut = norm(rawOut.0, rawOut.1)
            let (li, lo) = kind == .symmetric ? ((lengthIn + lengthOut) / 2, (lengthIn + lengthOut) / 2) : (lengthIn, lengthOut)
            var ux = rawOut.0 / lengthOut - rawIn.0 / lengthIn, uy = rawOut.1 / lengthOut - rawIn.1 / lengthIn
            if norm(ux, uy) < 1e-12 { (ux, uy) = (rawOut.0 / lengthOut, rawOut.1 / lengthOut) }
            let u = norm(ux, uy)
            // An arm whose length under- or overflows leaves the anchor as it is.
            guard [lengthIn, lengthOut, u].allSatisfy({ $0.isFinite && $0 > 0 }) else { return Path(contours: cs) }
            a.handleOut = Point(x: p.x + ux / u * lo, y: p.y + uy / u * lo)
            a.handleIn = Point(x: p.x - ux / u * li, y: p.y - uy / u * li)
        }
        cs[contour].anchors[index] = a
        return Path(contours: cs)
    }

    /// For each element, the pen it draws from (nil for a move or when there
    /// is none) and its subpath's start, walked as `flattened` walks them.
    func pens() -> [(pen: Point?, start: Point?)] {
        var last: Point?, start: Point?
        return elements.map { element in
            let entry: (pen: Point?, start: Point?)
            switch element {
            case .move(let to): (entry, last, start) = ((nil, start), to, to)
            case .close: (entry, last) = ((last, start), nil)
            default:
                entry = (last ?? start, start)
                if entry.pen == nil { start = element.endPoint }
                last = element.endPoint
            }
            return entry
        }
    }

    private static func checkAnchor(_ cs: [PathContour], _ contour: Int, _ index: Int) throws {
        guard contour >= 0, contour < cs.count, index >= 0, index < cs[contour].anchors.count else {
            throw GeometryError.invalidLocation
        }
    }

    private static func segment(_ a: PathAnchor, _ b: PathAnchor) -> PathElement {
        guard a.handleOut != nil || b.handleIn != nil else { return .line(to: b.point) }
        return .cubic(control1: a.handleOut ?? a.point, control2: b.handleIn ?? b.point, to: b.point)
    }

    /// A drawing element from `from` as the cubic with the same points at the
    /// same t: a line (or close back to `start`) at thirds, a quad raised.
    static func cubic(_ e: PathElement, from: Point, start: Point?) -> (Point, Point, Point, Point)? {
        switch e {
        case .move: return nil
        case .line(let to): return (from, lerp(from, to, 1.0 / 3), lerp(from, to, 2.0 / 3), to)
        case .close: return start.flatMap { cubic(.line(to: $0), from: from, start: nil) }
        case .quad(let c, let to): return (from, lerp(from, c, 2.0 / 3), lerp(to, c, 2.0 / 3), to)
        case .cubic(let c1, let c2, let to): return (from, c1, c2, to)
        }
    }

    /// The closest point of cubic `c` to `p`: the nearest of the equal t steps
    /// `flattened` takes, then golden-section search between its neighbours
    /// until the bracket is under 1e-9 in t.
    private static func closest(_ c: (Point, Point, Point, Point), to p: Point, tolerance: Double) -> (Double, Point, Double) {
        func at(_ t: Double) -> (t: Double, point: Point, distance: Double) {
            let q = cubicAt(c.0, c.1, c.2, c.3, t)
            return (t, q, norm(q.x - p.x, q.y - p.y))
        }
        let n = cubicSegments(c.0, c.1, c.2, c.3, tolerance: tolerance)
        var k = 0, nearest = Double.infinity
        for i in 0...n {
            let d = at(Double(i) / Double(n)).distance
            if d < nearest { (k, nearest) = (i, d) }
        }
        var lo = Double(max(k - 1, 0)) / Double(n), hi = Double(min(k + 1, n)) / Double(n)
        let g = (5.0.squareRoot() - 1) / 2
        for _ in 0..<80 where hi - lo > 1e-9 {
            let a = hi - g * (hi - lo), b = lo + g * (hi - lo)
            if at(a).distance < at(b).distance { hi = b } else { lo = a }
        }
        return at((lo + hi) / 2)
    }
}

extension PathContour {
    /// Appends a segment with handles `c1`, `c2` to `to`; a handle on its own point is dropped.
    fileprivate mutating func append(_ c1: Point?, _ c2: Point?, _ to: Point) {
        if let k = anchors.indices.last, let c1, c1 != anchors[k].point { anchors[k].handleOut = c1 }
        anchors.append(PathAnchor(point: to, handleIn: c2 == to ? nil : c2))
    }

    /// Closes the contour, folding a last anchor that a curve brought back onto the first into it.
    fileprivate mutating func close() {
        guard !closed else { return }
        closed = true
        if anchors.count > 1, let first = anchors.first, let last = anchors.last, last.point == first.point,
           let handle = last.handleIn {
            anchors[0].handleIn = handle
            anchors.removeLast()
        }
    }
}

extension PathAnchor {
    /// The anchor with the kind its handles show: opposite and collinear is
    /// smooth, and also of equal length is symmetric (both to 1e-9, relative).
    fileprivate var measured: PathAnchor {
        guard let i = handleIn, let o = handleOut else { return PathAnchor(point: point, handleIn: handleIn, handleOut: handleOut) }
        let (ix, iy, ox, oy) = (i.x - point.x, i.y - point.y, o.x - point.x, o.y - point.y)
        let li = norm(ix, iy), lo = norm(ox, oy)
        let smooth = ix * ox + iy * oy < 0 && abs(ix * oy - iy * ox) <= 1e-9 * li * lo
        let kind: AnchorKind = !smooth ? .corner : abs(li - lo) <= 1e-9 * max(li, lo) ? .symmetric : .smooth
        return PathAnchor(point: point, handleIn: i, handleOut: o, kind: kind)
    }
}

/// The point `t` of the way from `a` to `b`; PathMeasure cuts with it too.
func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
    Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
