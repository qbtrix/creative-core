// PathBoolean.swift: union, subtract, intersect and exclude of two filled
// paths, as closed polygons.
//
// Both inputs are flattened; only closed subpaths fill, as in HitTest. Every
// edge is split where it crosses or runs along another, endpoints snapped to
// a 1e-9 grid so touching vertices and collinear overlaps merge into one
// segment that counts how many edges of each input run along it. Each
// segment then learns each input's winding just beside its middle by a ray
// cast through horizontal bands (a vertical ray for a horizontal segment), is
// kept when the op is inside on exactly one side, and is directed so the
// result's inside lies on a fixed side. Kept segments chain into contours.
//
// Invariants:
// - the result's filled area is the set operation on the inputs' filled areas
//   under `rule`
// - more than `maxBooleanVertices` flattened vertices throws
//   GeometryError.tooComplex(count) instead of running unbounded; a NaN or
//   infinite coordinate throws GeometryError.nonFinite
// - output contours are closed, outer counter-clockwise on screen (negative
//   shoelace area with y down), holes clockwise
// - every loop is bounded by the segment count; the bands hold at most 8
//   entries per segment
//
// ponytail: band-indexed pair splitting instead of the full Martinez–Rueda–
// Feito sweep, and polygon output (curves are not re-fitted). Ceiling: a
// sweep-line event queue if the 2 × 5,000-vertex budget fails.

extension Path {
    /// Most flattened vertices, both inputs together, `combine` accepts.
    public static let maxBooleanVertices = 200_000

    /// `a op b` as one path, each input filled under `rule` and flattened to
    /// `tolerance`.
    ///
    /// Throws `GeometryError.tooComplex` past `maxBooleanVertices`,
    /// `GeometryError.nonFinite` for a NaN or infinite coordinate and
    /// `GeometryError.invalidTolerance` for a bad tolerance.
    public static func combine(_ op: BooleanOp, _ a: Path, _ b: Path, rule: FillRule,
                               tolerance: Double) throws -> Path {
        var count = 0
        for path in [a, b] {
            try path.forEachFlattenedPoint(tolerance: tolerance) { _, _ in count += 1; return false }
        }
        guard count <= maxBooleanVertices else { throw GeometryError.tooComplex(count) }
        var edges: [BooleanEdge] = []
        for (owner, path) in [a, b].enumerated() {
            for polygon in try path.filledPolygons(tolerance: tolerance) {
                for (p, q) in zip(polygon, polygon.dropFirst()) {
                    let edge = BooleanEdge(p: snapped(p), q: snapped(q), owner: owner)
                    guard edge.p.x.isFinite, edge.p.y.isFinite, edge.q.x.isFinite, edge.q.y.isFinite else {
                        throw GeometryError.nonFinite
                    }
                    if edge.p != edge.q { edges.append(edge) }
                }
            }
        }
        return chain(kept(op, rule, segments(edges)))
    }

    /// The closed subpaths, flattened: the polygons HitTest fills.
    func filledPolygons(tolerance: Double) throws -> [[Point]] {
        var result: [[Point]] = [], current: [PathElement] = [], start: Point?
        for element in elements {
            if case .move(let to) = element {
                current = []
                start = to
            } else if current.isEmpty, let start {
                current = [.move(to: start)]
            }
            current.append(element)
            if case .close = element {
                result += try Path(elements: current).flattened(tolerance: tolerance)
                current = []
            }
        }
        return result
    }
}

/// One flattened input edge; `owner` is 0 for the first input, 1 for the second.
private struct BooleanEdge { var p: Point, q: Point, owner: Int }

/// A split segment with ends ordered by (y, x), and per input how many of
/// its edges run lo to hi minus hi to lo.
private struct BooleanSegment: Hashable { var lo: Point, hi: Point }

private func snap(_ v: Double) -> Double { (v * 1e9).rounded() / 1e9 }

private func snapped(_ p: Point) -> Point { Point(x: snap(p.x), y: snap(p.y)) }

private func cross(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double { ax * by - ay * bx }

/// Segments bucketed into horizontal bands by y, for pair search and ray casts.
private struct Bands {
    var minY = 0.0, height = 1.0, count = 1
    var buckets: [[Int]] = []

    init(_ segments: [(Point, Point)]) {
        let lows = segments.map { min($0.0.y, $0.1.y) }, highs = segments.map { max($0.0.y, $0.1.y) }
        minY = lows.min() ?? 0
        let span = (highs.max() ?? 0) - minY
        count = span > 0 ? max(1, Int(Double(segments.count).squareRoot())) : 1
        while count > 1 {
            height = span / Double(count)
            let entries = zip(lows, highs).reduce(0) { $0 + band($1.1) - band($1.0) + 1 }
            if entries <= 8 * segments.count { break }
            count /= 2
        }
        height = span > 0 ? span / Double(count) : 1
        buckets = Array(repeating: [], count: count)
        for (i, (low, high)) in zip(lows, highs).enumerated() {
            for k in band(low)...band(high) { buckets[k].append(i) }
        }
    }

    func band(_ y: Double) -> Int {
        let k = (y - minY) / height
        guard k > 0 else { return 0 }
        return k >= Double(count - 1) ? count - 1 : Int(k)
    }
}

/// Every edge split at its crossings and overlaps, deduplicated, with the
/// net count of each input's edges along it.
private func segments(_ edges: [BooleanEdge]) -> [(BooleanSegment, SIMD2<Int>)] {
    var cuts = Array(repeating: [(t: Double, point: Point)](), count: edges.count)
    let bands = Bands(edges.map { ($0.p, $0.q) })
    for (index, bucket) in bands.buckets.enumerated() {
        let sorted = bucket.sorted { min(edges[$0].p.x, edges[$0].q.x) < min(edges[$1].p.x, edges[$1].q.x) }
        for (k, i) in sorted.enumerated() {
            let (p, p2) = (edges[i].p, edges[i].q)
            for j in sorted[(k + 1)...] {
                let (q, q2) = (edges[j].p, edges[j].q)
                guard min(q.x, q2.x) <= max(p.x, p2.x) else { break }
                // Each pair once: in the first band both edges reach.
                guard bands.band(max(min(p.y, p2.y), min(q.y, q2.y))) == index else { continue }
                addCuts(i, j, edges, &cuts)
            }
        }
    }
    var index: [BooleanSegment: Int] = [:], result: [(BooleanSegment, SIMD2<Int>)] = []
    for (i, edge) in edges.enumerated() {
        var from = edge.p
        for to in cuts[i].sorted(by: { $0.t < $1.t }).map(\.point) + [edge.q] where to != from {
            let up = (from.y, from.x) < (to.y, to.x)
            let key = BooleanSegment(lo: up ? from : to, hi: up ? to : from)
            var net = SIMD2<Int>.zero
            net[edge.owner] = up ? 1 : -1
            if let k = index[key] { result[k].1 &+= net } else { index[key] = result.count; result.append((key, net)) }
            from = to
        }
    }
    return result
}

/// Records where edges `i` and `j` cross, or where each has the other's ends
/// inside it when they overlap on one line.
private func addCuts(_ i: Int, _ j: Int, _ edges: [BooleanEdge], _ cuts: inout [[(t: Double, point: Point)]]) {
    let (p, p2, q, q2) = (edges[i].p, edges[i].q, edges[j].p, edges[j].q)
    let (rx, ry, sx, sy, wx, wy) = (p2.x - p.x, p2.y - p.y, q2.x - q.x, q2.y - q.y, q.x - p.x, q.y - p.y)
    let d = cross(rx, ry, sx, sy)
    if abs(d) <= 1e-12 * norm(rx, ry) * norm(sx, sy) {
        guard abs(cross(wx, wy, rx, ry)) <= 1e-9 * norm(rx, ry) else { return }
        for (end, k) in [(q, i), (q2, i), (p, j), (p2, j)] {
            let (a, b) = (edges[k].p, edges[k].q)
            let t = ((end.x - a.x) * (b.x - a.x) + (end.y - a.y) * (b.y - a.y)) / ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))
            if t > 0, t < 1 { cuts[k].append((t, end)) }
        }
        return
    }
    let t = cross(wx, wy, sx, sy) / d, u = cross(wx, wy, rx, ry) / d
    guard t >= -1e-12, t <= 1 + 1e-12, u >= -1e-12, u <= 1 + 1e-12 else { return }
    let raw = Point(x: p.x + t * rx, y: p.y + t * ry)
    let point = [p, p2, q, q2].first { norm($0.x - raw.x, $0.y - raw.y) <= 1e-9 } ?? snapped(raw)
    cuts[i].append((t, point))
    cuts[j].append((u, point))
}

/// The segments on the boundary of `op`, each directed with the result's
/// inside on its left as drawn (y down), so outers run counter-clockwise.
private func kept(_ op: BooleanOp, _ rule: FillRule, _ segments: [(BooleanSegment, SIMD2<Int>)]) -> [(Point, Point)] {
    // Frame 1 swaps x and y, so a horizontal segment gets a vertical ray.
    let frames = [segments.map { ($0.0.lo, $0.0.hi) },
                  segments.map { (Point(x: $0.0.lo.y, y: $0.0.lo.x), Point(x: $0.0.hi.y, y: $0.0.hi.x)) }]
    let bands = frames.map(Bands.init)
    var result: [(Point, Point)] = []
    for (i, (segment, net)) in segments.enumerated() {
        let f = segment.lo.y == segment.hi.y ? 1 : 0
        let (a, b) = frames[f][i]
        let m = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        var right = SIMD2<Int>.zero
        for j in bands[f].buckets[bands[f].band(m.y)] where j != i {
            let (c, d) = frames[f][j]
            guard (c.y <= m.y) != (d.y <= m.y), c.x + (m.y - c.y) * (d.x - c.x) / (d.y - c.y) > m.x else { continue }
            right = d.y > c.y ? right &+ segments[j].1 : right &- segments[j].1
        }
        // Crossing the segment itself from +x to -x adds its own edges.
        let left = right &+ net
        let inRight = op.keeps(rule.fills(right[0]), rule.fills(right[1]))
        guard inRight != op.keeps(rule.fills(left[0]), rule.fills(left[1])) else { continue }
        // In frame 0 inside on +x means lo to hi; frame 1 is a mirror, so it flips.
        result.append(inRight == (f == 0) ? (segment.lo, segment.hi) : (segment.hi, segment.lo))
    }
    return result
}

/// Directed edges joined end to start into closed contours.
private func chain(_ edges: [(Point, Point)]) -> Path {
    var outgoing: [Point: [Int]] = [:]
    for (i, edge) in edges.enumerated() { outgoing[edge.0, default: []].append(i) }
    var used = [Bool](repeating: false, count: edges.count), elements: [PathElement] = []
    for first in edges.indices where !used[first] {
        let start = edges[first].0
        var points = [start], current = first
        while true {
            used[current] = true
            let end = edges[current].1
            guard end != start, let next = outgoing[end]?.first(where: { !used[$0] }) else { break }
            points.append(end)
            current = next
        }
        elements += Path(polyline: points, closed: true).elements
    }
    return Path(elements: elements)
}

private extension BooleanOp {
    func keeps(_ a: Bool, _ b: Bool) -> Bool {
        switch self {
        case .union: a || b
        case .subtract: a && !b
        case .intersect: a && b
        case .exclude: a != b
        }
    }
}

private extension FillRule {
    func fills(_ winding: Int) -> Bool { self == .evenOdd ? winding % 2 != 0 : winding != 0 }
}
