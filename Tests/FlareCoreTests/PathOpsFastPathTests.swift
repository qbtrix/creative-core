// PathOpsFastPathTests.swift: the PG-z speedups give the old answers bit for
// bit. On seeded paths of every element kind, drawn twice so ties occur,
// pruned `nearest` and the one-pass ruler's trim and dash match the plain
// algorithms they replaced, kept here as references.
import FlareCore
import Testing

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }

private func seededPath(_ seed: UInt64) -> Path {
    var rng = SplitMix64(seed: seed)
    func r() -> Point { pt(Double.random(in: 0...100, using: &rng), Double.random(in: 0...100, using: &rng)) }
    let elements: [PathElement] = [.move(to: r())] + (0..<40).map { _ in
        switch Int.random(in: 0..<12, using: &rng) {
        case 0: .move(to: r())
        case 1: .close
        case 2...4: .line(to: r())
        case 5...7: .quad(control: r(), to: r())
        default: .cubic(control1: r(), control2: r(), to: r())
        }
    }
    return Path(elements: elements + elements)
}

private func end(_ e: PathElement) -> Point? {
    switch e {
    case .move(let to), .line(let to), .quad(_, let to), .cubic(_, _, let to): to
    case .close: nil
    }
}

/// The old `nearest`: every drawing element searched alone, the first strictly nearest kept.
private func plainNearest(_ path: Path, _ p: Point, _ tol: Double) throws -> PathLocation? {
    var last: Point?, start: Point?, best: PathLocation?
    for (i, e) in path.elements.enumerated() {
        var one: [PathElement] = []
        switch e {
        case .move(let to): (last, start) = (to, to)
        case .close:
            if let from = last, let s = start { one = [.move(to: from), .line(to: s)] }
            last = nil
        default:
            if let from = last ?? start { one = [.move(to: from), e] } else { start = end(e) }
            last = end(e)
        }
        guard !one.isEmpty, let f = try Path(elements: one).nearest(to: p, tolerance: tol) else { continue }
        if f.distance < best?.distance ?? .infinity { best = PathLocation(element: i, t: f.t, point: f.point, distance: f.distance) }
    }
    return best
}

/// The old ruler line: prefix sums over a copied polyline, and a filtering cut.
private struct OldLine {
    var points: [Point], sums: [Double] = [0]
    var length: Double { sums.last ?? 0 }
    init(_ points: [Point]) {
        self.points = points
        for (a, b) in zip(points, points.dropFirst()) { sums.append(length + ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()) }
    }
    func at(_ s: Double) -> Point {
        var lo = 0, hi = sums.count - 1
        while hi - lo > 1 { let mid = (lo + hi) / 2; if sums[mid] <= s { lo = mid } else { hi = mid } }
        while lo > 0, sums[lo + 1] <= sums[lo] { lo -= 1 }
        let a = points[lo], b = points[lo + 1], t = (s - sums[lo]) / (sums[lo + 1] - sums[lo])
        return pt(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
    }
    func cut(_ a: Double, _ b: Double) -> [PathElement] {
        Path(polyline: [at(a)] + zip(points, sums).filter { $0.1 > a && $0.1 < b }.map(\.0) + [at(b)], closed: false).elements
    }
}

/// The old dash walk (even pattern) and whole-path trim (start <= end, no offset).
private func plainDashed(_ path: Path, _ entries: [Double], _ phase: Double, _ tol: Double) throws -> Path {
    let period = entries.reduce(0, +)
    var out: [PathElement] = []
    for line in try path.flattened(tolerance: tol).map(OldLine.init) {
        var i = 0, left = phase - (phase / period).rounded(.down) * period
        for _ in entries where left > 0 && left >= entries[i] { left -= entries[i]; i = (i + 1) % entries.count }
        var d = 0.0, remaining = max(entries[i] - left, 0)
        while d < line.length {
            let next = min(d + remaining, line.length)
            if i % 2 == 0, next > d { out += line.cut(d, next) }
            (d, i) = (next, (i + 1) % entries.count)
            remaining = entries[i]
        }
    }
    return Path(elements: out)
}

private func plainTrimmed(_ path: Path, _ s: Double, _ e: Double, _ tol: Double) throws -> Path {
    let lines = try path.flattened(tolerance: tol).map(OldLine.init)
    let total = lines.reduce(0) { $0 + $1.length }
    var offset = 0.0, out: [PathElement] = []
    for line in lines {
        let lo = max(s * total - offset, 0), hi = min(min((s + (e - s)) * total, total) - offset, line.length)
        if hi > lo { out += line.cut(lo, hi) }
        offset += line.length
    }
    return Path(elements: out)
}

@Suite struct PathOpsFastPathTests {
    @Test func nearestMatchesThePlainSearch() throws {
        for seed in UInt64(1)...6 {
            let path = seededPath(0x5EED + seed)
            var rng = SplitMix64(seed: seed)
            let targets = path.elements.compactMap(end) + (0..<150).map { _ in
                pt(Double.random(in: -20...120, using: &rng), Double.random(in: -20...120, using: &rng))
            }
            for p in targets { #expect(try path.nearest(to: p, tolerance: 0.05) == plainNearest(path, p, 0.05), "seed \(seed) at \(p)") }
        }
    }

    @Test func trimAndDashMatchTheCopyingRuler() throws {
        for seed in UInt64(1)...6 {
            let path = seededPath(0xDA5 + seed)
            #expect(try path.dashed([7, 3, 2, 3], phase: 4, tolerance: 0.1) == plainDashed(path, [7, 3, 2, 3], 4, 0.1))
            #expect(try path.trimmed(start: 0.2, end: 0.7, offset: 0, mode: .together, tolerance: 0.1) == plainTrimmed(path, 0.2, 0.7, 0.1))
        }
    }
}
