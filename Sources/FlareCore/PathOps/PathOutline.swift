// PathOutline.swift: a stroke turned into the closed path that fills the
// same area.
//
// Invariants:
// - the result is closed and its filled area is the stroked area
// - a miter longer than `miterLimit` times half the width falls back to a bevel
// - a width or miter limit that is zero, negative or not finite throws
//   GeometryError.nonFinite
// - the loops never hold more than `Path.maxBooleanVertices` points: the
//   stroker throws tooComplex(maxBooleanVertices) as it passes the cap, before
//   building the rest (a round join can add 4096 points per vertex)
//
// Each subpath flattens and is offset by w/2 to both sides: an open one
// becomes one loop (left side, end cap, right side back, start cap), a closed
// one two rings (left, and right reversed). At each vertex the outer side of
// the turn gets the join (miter tip, nothing for a bevel, or an arc); the
// inner side cuts across at the offsets' crossing when it lies within half of
// both segments, and pivots through the vertex otherwise. Every loop then
// winds the same way, as many times as strokes cover a point, so
// `Path.combine` under nonzero merges them into the stroked area.
// ponytail: polyline output, no curve re-fit; a subpath that flattens to one
// point draws nothing (no dot caps). Ceiling: re-fit cubics if a caller needs
// editable outlines.
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

extension Path {
    /// The outline of this path stroked at `width` with `join`, `cap` (open
    /// contours only) and `miterLimit`, curves and round parts flattened to
    /// `tolerance`, as one fillable path (nonzero).
    ///
    /// Throws `GeometryError.nonFinite` when `width` or `miterLimit` is not
    /// finite or not greater than 0 (pass a positive width and miter limit),
    /// or for a non-finite point; `GeometryError.invalidTolerance` for a bad
    /// tolerance; and `GeometryError.tooComplex(Path.maxBooleanVertices)` as
    /// soon as the outline's points pass `Path.maxBooleanVertices`, the most
    /// `combine` accepts (round joins and caps at a fine tolerance add many).
    public func outlined(width: Double, join: Stroke.Join, cap: Stroke.Cap, miterLimit: Double,
                         tolerance: Double) throws -> Path {
        guard width.isFinite, width > 0, miterLimit.isFinite, miterLimit > 0 else { throw GeometryError.nonFinite }
        guard tolerance.isFinite, tolerance > 0 else { throw GeometryError.invalidTolerance }
        let stroker = Stroker(h: width / 2, join: join, cap: cap, miterLimit: miterLimit, tolerance: tolerance)
        var loops: [PathElement] = [], budget = Path.maxBooleanVertices
        for (subpath, closed) in strokedSubpaths() {
            for polyline in try subpath.flattened(tolerance: tolerance) {
                for loop in try stroker.loops(polyline, closed: closed, budget: &budget) {
                    loops += Path(polyline: loop, closed: true).elements
                }
            }
        }
        return try Path.combine(.union, Path(elements: loops), Path(), rule: .nonZero, tolerance: tolerance)
    }

    /// Each subpath as its own path, with whether it ends in `close`. A
    /// drawing element right after a close starts a new subpath at its start.
    func strokedSubpaths() -> [(Path, Bool)] {
        var result: [(Path, Bool)] = [], current: [PathElement] = [], start: Point?
        for element in elements {
            switch element {
            case .move(let to):
                if !current.isEmpty { result.append((Path(elements: current), false)) }
                (current, start) = ([element], to)
            case .close:
                guard !current.isEmpty else { continue }
                result.append((Path(elements: current), true))
                current = []
            default:
                if current.isEmpty, let start { current = [.move(to: start)] }
                current.append(element)
            }
        }
        if !current.isEmpty { result.append((Path(elements: current), false)) }
        return result
    }
}

/// Offsets one flattened subpath into the loops whose nonzero fill is its stroke.
private struct Stroker {
    let h: Double, join: Stroke.Join, cap: Stroke.Cap, miterLimit: Double, tolerance: Double

    /// Each loop's points count against `budget`, the points the outline may
    /// still add; passing it throws tooComplex(maxBooleanVertices) at once.
    func loops(_ polyline: [Point], closed: Bool, budget: inout Int) throws -> [[Point]] {
        var points: [Point] = []
        for p in polyline where points.last != p {
            guard p.x.isFinite, p.y.isFinite else { throw GeometryError.nonFinite }
            points.append(p)
        }
        if closed, points.count > 1, points.first == points.last { points.removeLast() }
        guard points.count > 1 else { return [] }
        let ends = closed ? points + [points[0]] : points
        // Length, unit direction and left normal × h of each segment.
        let lengths = zip(ends, ends.dropFirst()).map { norm($1.x - $0.x, $1.y - $0.y) }
        let dirs = zip(ends, ends.dropFirst()).enumerated().map { i, pair in
            Point(x: (pair.1.x - pair.0.x) / lengths[i], y: (pair.1.y - pair.0.y) / lengths[i])
        }
        let normals = dirs.map { Point(x: -$0.y * h, y: $0.x * h) }
        func spend(_ points: [Point]) throws -> [Point] {
            budget -= points.count
            guard budget >= 0 else { throw GeometryError.tooComplex(Path.maxBooleanVertices) }
            return points
        }
        func side(_ s: Double) throws -> [Point] {
            var chain = try spend(closed ? [] : [offset(ends[0], normals[0], s)])
            for i in (closed ? 0 : 1)..<dirs.count {
                let previous = i == 0 ? dirs.count - 1 : i - 1
                chain += try spend(vertex(ends[i], s, dirs[previous], dirs[i], normals[previous], normals[i],
                                          min(lengths[previous], lengths[i])))
            }
            if !closed, let last = normals.last, let end = ends.last { chain += try spend([offset(end, last, s)]) }
            return chain
        }
        let (left, right) = (try side(1), Array(try side(-1).reversed()))
        guard !closed, let d0 = dirs.first, let d1 = dirs.last, let n0 = normals.first, let n1 = normals.last,
              let end = ends.last else { return [left, right] }
        let endCap = try spend(capPoints(end, outward: d1, from: n1))
        let startCap = try spend(capPoints(ends[0], outward: Point(x: -d0.x, y: -d0.y), from: Point(x: -n0.x, y: -n0.y)))
        return [left + endCap + right + startCap]
    }

    /// The side `s` (1 left, -1 right) offset points at vertex `v` between a
    /// segment along `d0` and one along `d1`; `shorter` is the shorter one's length.
    func vertex(_ v: Point, _ s: Double, _ d0: Point, _ d1: Point, _ n0: Point, _ n1: Point,
                _ shorter: Double) -> [Point] {
        let (turn, dot) = (d0.x * d1.y - d0.y * d1.x, d0.x * d1.x + d0.y * d1.y)
        guard abs(turn) > 1e-12 || dot < 0 else { return [offset(v, n1, s)] }
        let outer: Double = turn > 0 ? -1 : 1
        let (o0, o1) = (offset(v, n0, s), offset(v, n1, s))
        // Where the two offset lines cross: h / cos(θ/2) from v along the bisector.
        let crossing = dot > -1 ? Point(x: v.x + s * (n0.x + n1.x) / (1 + dot), y: v.y + s * (n0.y + n1.y) / (1 + dot)) : v
        guard s == outer else {
            return dot > -1 && h * abs(turn) / (1 + dot) <= shorter / 2 ? [crossing] : [o0, v, o1]
        }
        switch join {
        case .bevel:
            return [o0, o1]
        case .miter:
            let miter = dot > -1 ? h * (2 / (1 + dot)).squareRoot() : .infinity
            return miter <= miterLimit * h ? [o0, crossing, o1] : [o0, o1]
        case .round:
            let (a, b) = (Point(x: s * n0.x, y: s * n0.y), Point(x: s * n1.x, y: s * n1.y))
            return [o0] + arc(v, from: a, sweep: atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y)) + [o1]
        }
    }

    /// The points a cap adds between `p + n` and `p - n` at an end leaving along `outward`.
    func capPoints(_ p: Point, outward: Point, from n: Point) -> [Point] {
        switch cap {
        case .butt:
            return []
        case .square:
            let extent = h
            let e = Point(x: outward.x * extent, y: outward.y * extent)
            return [Point(x: p.x + n.x + e.x, y: p.y + n.y + e.y), Point(x: p.x - n.x + e.x, y: p.y - n.y + e.y)]
        case .round:
            return arc(p, from: n, sweep: -Double.pi)
        }
    }

    /// The points strictly inside the arc around `v` that turns offset `from`
    /// by `sweep` radians, spaced so no chord strays past `tolerance`.
    func arc(_ v: Point, from: Point, sweep: Double) -> [Point] {
        let step = tolerance < h ? 2 * acos(1 - tolerance / h) : Double.pi / 2
        let n = Path.segmentCount(abs(sweep) / step)
        return (1..<max(n, 1)).map { k in
            let a = sweep * Double(k) / Double(n)
            return Point(x: v.x + from.x * cos(a) - from.y * sin(a), y: v.y + from.x * sin(a) + from.y * cos(a))
        }
    }

    func offset(_ v: Point, _ n: Point, _ s: Double) -> Point { Point(x: v.x + s * n.x, y: v.y + s * n.y) }
}
