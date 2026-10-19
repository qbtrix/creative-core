// PathEdit.swift: point editing on a `Path`: the anchors view, nearest point,
// inserting, removing and converting an anchor.
//
// Invariants:
// - `Path(contours: p.contours)` draws the same shape as `p` (quads come back
//   as the same curve raised to cubics)
// - inserting a point never moves the drawn shape
// - a bad contour, anchor or element index, or a t outside 0...1, throws
//   GeometryError.invalidLocation
// - the pen before each element is the one `flattened` uses (`pens`)

extension Path {
    /// The path as contours of anchors. Quads are raised to cubics; a handle
    /// equal to its point is nil. A closed contour whose last anchor lands on
    /// its first by a curve folds the two into one anchor.
    public var contours: [PathContour] {
        var result: [PathContour] = []
        var current: PathContour?
        func start(_ p: Point) {
            if let c = current { result.append(c) }
            current = PathContour(anchors: [PathAnchor(point: p)], closed: false)
        }
        for (element, pen) in zip(elements, pens()) {
            switch element {
            case .move(let to): start(to)
            case .close: current?.close()
            default:
                guard let from = pen.pen, let to = element.endPoint else {
                    if let to = element.endPoint { start(to) }
                    continue
                }
                if current?.closed ?? true { start(from) }
                switch element {
                case .quad(let c, _):
                    current?.append(lerp(from, c, 2.0 / 3), lerp(to, c, 2.0 / 3), to)
                case .cubic(let c1, let c2, _): current?.append(c1, c2, to)
                default: current?.append(nil, nil, to)
                }
            }
        }
        if let c = current { result.append(c) }
        return result.map { contour in
            var c = contour
            for i in c.anchors.indices { c.anchors[i].kind = c.anchors[i].measuredKind }
            return c
        }
    }

    /// The path that draws `contours`: a move per contour, a line where both
    /// facing handles are nil, a cubic otherwise, and a close when `closed`.
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
            if contour.closed {
                if previous.handleOut != nil || first.handleIn != nil { elements.append(Self.segment(previous, first)) }
                elements.append(.close)
            }
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
            let found = Self.closest(c, to: p, tolerance: tolerance)
            if found.distance < best?.distance ?? .infinity { best = PathLocation(element: i, t: found.t, point: found.point, distance: found.distance) }
        }
        return best
    }

    /// The path with a new anchor at `location`, its element split there by
    /// de Casteljau so the drawn shape does not change.
    ///
    /// Throws `GeometryError.invalidLocation` when `location.element` is not a
    /// drawing element or `location.t` is outside 0...1.
    public func inserting(at location: PathLocation) throws -> Path {
        let i = location.element, t = location.t
        guard i >= 0, i < elements.count, t.isFinite, t >= 0, t <= 1,
              let from = pens()[i].pen else { throw GeometryError.invalidLocation }
        let parts: [PathElement]
        switch elements[i] {
        case .move: throw GeometryError.invalidLocation
        case .line(let to): parts = [.line(to: lerp(from, to, t)), .line(to: to)]
        case .close: parts = [.line(to: lerp(from, pens()[i].start ?? from, t)), .close]
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
    /// Smooth keeps each handle's length and turns the pair onto the line that
    /// bisects them, so the out handle stays on the out side; a missing handle
    /// starts a third of the way to its neighbour.
    ///
    /// Throws `GeometryError.invalidLocation` for an index out of range.
    public func converting(contour: Int, index: Int, to kind: AnchorKind) throws -> Path {
        var cs = contours
        try Self.checkAnchor(cs, contour, index)
        let anchors = cs[contour].anchors, closed = cs[contour].closed, a = anchors[index], p = a.point
        guard kind != .corner else {
            cs[contour].anchors[index].handleIn = nil
            cs[contour].anchors[index].handleOut = nil
            return Path(contours: cs)
        }
        func neighbour(_ j: Int) -> Point? {
            anchors.indices.contains(j) ? anchors[j].point : closed ? anchors[(j + anchors.count) % anchors.count].point : nil
        }
        func arm(_ handle: Point?, _ next: Int) -> (Double, Double)? {
            let q = handle ?? neighbour(next).map { lerp(p, $0, 1.0 / 3) }
            return q.flatMap { q in q == p ? nil : (q.x - p.x, q.y - p.y) }
        }
        guard let rawOut = arm(a.handleOut, index + 1) ?? arm(a.handleIn, index - 1).map({ (-$0.0, -$0.1) }),
              let rawIn = arm(a.handleIn, index - 1) ?? arm(a.handleOut, index + 1).map({ (-$0.0, -$0.1) })
        else { return Path(contours: cs) }
        let lengthIn = norm(rawIn.0, rawIn.1), lengthOut = norm(rawOut.0, rawOut.1)
        let (li, lo) = kind == .symmetric ? ((lengthIn + lengthOut) / 2, (lengthIn + lengthOut) / 2) : (lengthIn, lengthOut)
        var ux = rawOut.0 / lengthOut - rawIn.0 / lengthIn, uy = rawOut.1 / lengthOut - rawIn.1 / lengthIn
        if norm(ux, uy) < 1e-12 { (ux, uy) = (rawOut.0 / lengthOut, rawOut.1 / lengthOut) }
        let u = norm(ux, uy)
        cs[contour].anchors[index].handleOut = Point(x: p.x + ux / u * lo, y: p.y + uy / u * lo)
        cs[contour].anchors[index].handleIn = Point(x: p.x - ux / u * li, y: p.y - uy / u * li)
        return Path(contours: cs)
    }

    /// For each element, the pen it draws from (nil when there is none) and
    /// its subpath's start, walked the way `flattened` walks them.
    func pens() -> [(pen: Point?, start: Point?)] {
        var result: [(pen: Point?, start: Point?)] = []
        result.reserveCapacity(elements.count)
        var last: Point?, start: Point?
        for element in elements {
            switch element {
            case .move(let to):
                result.append((nil, start))
                (last, start) = (to, to)
            case .close:
                result.append((last, start))
                last = nil
            default:
                let from = last ?? start
                result.append((from, start))
                if from == nil { start = element.endPoint }
                last = element.endPoint
            }
        }
        return result
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
    /// same t: a line or close at thirds, a quad raised.
    private static func cubic(_ e: PathElement, from: Point, start: Point?) -> (Point, Point, Point, Point)? {
        switch e {
        case .move: return nil
        case .line(let to): return (from, lerp(from, to, 1.0 / 3), lerp(from, to, 2.0 / 3), to)
        case .close: return start.flatMap { cubic(.line(to: $0), from: from, start: nil) }
        case .quad(let c, let to): return (from, lerp(from, c, 2.0 / 3), lerp(to, c, 2.0 / 3), to)
        case .cubic(let c1, let c2, let to): return (from, c1, c2, to)
        }
    }

    /// The closest point of cubic `c` to `p`: the best of its flattening
    /// samples, then golden-section search between that sample's neighbours.
    private static func closest(_ c: (Point, Point, Point, Point), to p: Point, tolerance: Double) -> (t: Double, point: Point, distance: Double) {
        func at(_ t: Double) -> (Point, Double) {
            let q = cubicAt(c.0, c.1, c.2, c.3, t)
            return (q, norm(q.x - p.x, q.y - p.y))
        }
        let n = max(cubicSegmentCount(c.0, c.1, c.2, c.3, tolerance: tolerance), 8)
        let k = (0...n).min { at(Double($0) / Double(n)).1 < at(Double($1) / Double(n)).1 } ?? 0
        var lo = Double(max(k - 1, 0)) / Double(n), hi = Double(min(k + 1, n)) / Double(n)
        let g = (5.0.squareRoot() - 1) / 2
        for _ in 0..<80 {
            let a = hi - g * (hi - lo), b = lo + g * (hi - lo)
            if at(a).1 < at(b).1 { hi = b } else { lo = a }
        }
        let t = (lo + hi) / 2, (q, d) = at(t)
        return (t, q, d)
    }
}

extension PathContour {
    /// Appends a segment with handles `c1` and `c2` to `to`; a handle on its
    /// own point is dropped.
    fileprivate mutating func append(_ c1: Point?, _ c2: Point?, _ to: Point) {
        if let k = anchors.indices.last, let c1, c1 != anchors[k].point { anchors[k].handleOut = c1 }
        anchors.append(PathAnchor(point: to, handleIn: c2 == to ? nil : c2))
    }

    /// Closes the contour, folding a last anchor that a curve brought back
    /// onto the first into the first.
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
    /// The kind the handles show: opposite and collinear is smooth, and also
    /// of equal length is symmetric (both to 1e-9, relative).
    fileprivate var measuredKind: AnchorKind {
        guard let i = handleIn, let o = handleOut else { return .corner }
        let (ix, iy, ox, oy) = (i.x - point.x, i.y - point.y, o.x - point.x, o.y - point.y)
        let li = norm(ix, iy), lo = norm(ox, oy)
        guard ix * ox + iy * oy < 0, abs(ix * oy - iy * ox) <= 1e-9 * li * lo else { return .corner }
        return abs(li - lo) <= 1e-9 * max(li, lo) ? .symmetric : .smooth
    }
}

private func lerp(_ a: Point, _ b: Point, _ t: Double) -> Point {
    Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
