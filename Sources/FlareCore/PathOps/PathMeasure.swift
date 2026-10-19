// PathMeasure.swift: a ruler along a `Path`: its length, the point and unit
// tangent at a length, trim and dash.
//
// Invariants:
// - every measure flattens the path once at `tolerance` and walks the polyline
// - trimmed and dashed output is polyline pieces of the flattened path
// - a dash pattern with a negative, non-finite or zero-sum entry list, or
//   more than 64 entries, throws GeometryError.invalidPattern
// - a non-finite point or length throws nonFinite; a dash walk past `maxDashSteps` throws tooComplex
//
// ponytail: trim and dash cut the flattened polyline, so curves come back as
// lines; ceiling: exact cubic trim if a caller needs editable curves.

extension Path {
    /// Most dash and gap entries one `dashed` call walks.
    static let maxDashSteps = 1_000_000

    /// The length of the path flattened to `tolerance`.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance, `.nonFinite` for a non-finite point.
    public func length(tolerance: Double) throws -> Double {
        try Ruler(self, tolerance: tolerance).total
    }

    /// The point `s` along the path and the unit tangent there; nil when `s`
    /// is outside 0...length or the path is empty. A corner takes the tangent leaving it.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance, `.nonFinite` for a non-finite point.
    public func sample(atLength s: Double, tolerance: Double) throws -> (point: Point, tangent: Point)? {
        let ruler = try Ruler(self, tolerance: tolerance)
        guard ruler.total > 0, s >= 0, s <= ruler.total else { return nil }
        // The last line with length that starts at or before s.
        guard let k = ruler.lines.indices.last(where: { ruler.offsets[$0] <= s && ruler.lines[$0].length > 0 }) else {
            return nil
        }
        let line = ruler.lines[k], at = s - ruler.offsets[k], i = line.segment(at: at)
        let a = line.points[i], b = line.points[i + 1], d = line.sums[i + 1] - line.sums[i]
        return (line.at(at), Point(x: (b.x - a.x) / d, y: (b.y - a.y) / d))
    }

    /// The part of the path from `start` to `end` (fractions 0...1 of the
    /// length) shifted by `offset` (wraps), over the whole path or each contour
    /// as `mode` says. A start past the end after wrapping gives two pieces.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance and
    /// `GeometryError.nonFinite` for a non-finite start, end or offset.
    public func trimmed(start: Double, end: Double, offset: Double, mode: TrimMode,
                        tolerance: Double) throws -> Path {
        guard start.isFinite, end.isFinite, offset.isFinite else { throw GeometryError.nonFinite }
        let ruler = try Ruler(self, tolerance: tolerance)
        let s = Swift.min(Swift.max(start, 0), 1), e = Swift.min(Swift.max(end, 0), 1)
        let span = e >= s ? e - s : 1 - s + e
        let from = wrap(s + offset)
        let rulers = mode == .eachContour ? ruler.lines.map { Ruler(lines: [$0]) } : [ruler]
        var pieces: [[Point]] = []
        for r in rulers {
            let a = from * r.total, b = (from + span) * r.total
            pieces += r.slice(a, Swift.min(b, r.total))
            if b > r.total { pieces += r.slice(0, b - r.total) }
        }
        return Path(pieces: pieces)
    }

    /// The dashes of `pattern` (dash, gap, dash, ... lengths; an odd count
    /// repeats once) along each contour, starting `phase` into the pattern.
    ///
    /// Throws `GeometryError.invalidPattern` for a bad pattern,
    /// `GeometryError.invalidTolerance` for a bad tolerance, `.nonFinite` for a
    /// non-finite phase or point, and `GeometryError.tooComplex(1_000_000)` when
    /// the walk passes `maxDashSteps` (1,000,000) dash and gap entries over all contours.
    public func dashed(_ pattern: [Double], phase: Double, tolerance: Double) throws -> Path {
        guard (1...64).contains(pattern.count), pattern.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw GeometryError.invalidPattern
        }
        let entries = pattern.count % 2 == 1 ? pattern + pattern : pattern
        let period = entries.reduce(0, +)
        guard period > 0, period.isFinite else { throw GeometryError.invalidPattern }
        guard phase.isFinite else { throw GeometryError.nonFinite }
        var pieces: [[Point]] = [], steps = 0
        for line in try Ruler(self, tolerance: tolerance).lines {
            // Find where `phase` falls in the pattern, then walk the contour.
            var i = 0, left = phase - (phase / period).rounded(.down) * period
            for _ in entries where left > 0 && left >= entries[i] {
                left -= entries[i]
                i = (i + 1) % entries.count
            }
            var d = 0.0, remaining = Swift.max(entries[i] - left, 0)
            while d < line.length {
                steps += 1
                guard steps <= Self.maxDashSteps else { throw GeometryError.tooComplex(Self.maxDashSteps) }
                let next = Swift.min(d + remaining, line.length)
                if i % 2 == 0, next > d { pieces.append(line.cut(d, next)) }
                d = next
                i = (i + 1) % entries.count
                remaining = entries[i]
            }
        }
        return Path(pieces: pieces)
    }

    /// Open polylines, one subpath each.
    init(pieces: [[Point]]) {
        self.init(elements: pieces.flatMap { Path(polyline: $0, closed: false).elements })
    }
}

/// `x` wrapped into 0..<1.
private func wrap(_ x: Double) -> Double {
    let w = x - x.rounded(.down)
    return w < 1 ? w : 0
}

/// One flattened polyline; `sums[i]` is the length from `points[0]` to `points[i]`.
private struct RulerLine {
    var points: [Point], sums: [Double]
    var length: Double { sums.last ?? 0 }

    /// The segment `i` with `sums[i] <= s < sums[i + 1]`; at the end, the last
    /// segment with length. Needs `length > 0`.
    func segment(at s: Double) -> Int {
        var lo = 0, hi = sums.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if sums[mid] <= s { lo = mid } else { hi = mid }
        }
        while lo > 0, sums[lo + 1] <= sums[lo] { lo -= 1 }
        return lo
    }

    func at(_ s: Double) -> Point {
        let i = segment(at: s)
        return lerp(points[i], points[i + 1], (s - sums[i]) / (sums[i + 1] - sums[i]))
    }

    /// The polyline from length `a` to `b` (0 <= a < b <= length): a binary
    /// search finds the first point past `a`, so a cut walks only its own span.
    func cut(_ a: Double, _ b: Double) -> [Point] {
        var lo = 0, hi = sums.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sums[mid] <= a { lo = mid + 1 } else { hi = mid }
        }
        var result = [at(a)]
        while lo < sums.count, sums[lo] < b {
            result.append(points[lo])
            lo += 1
        }
        return result + [at(b)]
    }
}

/// The flattened path as lines laid end to end; line `k` starts at `offsets[k]`.
private struct Ruler {
    var lines: [RulerLine], offsets: [Double] = [], total = 0.0

    init(lines: [RulerLine]) {
        self.lines = lines
        for line in lines {
            offsets.append(total)
            total += line.length
        }
    }

    init(_ path: Path, tolerance: Double) throws {
        let lines = try path.flattened(tolerance: tolerance).map { points in
            let sums = zip(points, points.dropFirst()).reduce(into: [0.0]) { $0.append(($0.last ?? 0) + norm($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
            guard (sums.last ?? 0).isFinite, points.allSatisfy(\.isFinite) else { throw GeometryError.nonFinite }
            return RulerLine(points: points, sums: sums)
        }
        self.init(lines: lines)
        guard total.isFinite else { throw GeometryError.nonFinite }
    }

    /// The pieces from `a` to `b` (0 <= a <= b <= total), one per line crossed.
    func slice(_ a: Double, _ b: Double) -> [[Point]] {
        lines.indices.compactMap { k in
            let lo = Swift.max(a - offsets[k], 0), hi = Swift.min(b - offsets[k], lines[k].length)
            return hi > lo ? lines[k].cut(lo, hi) : nil
        }
    }
}
