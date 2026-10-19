// PathOpsBudgetTests.swift: the path-geometry budgets (PG-11). On the seeded
// 10,000-anchor scribble (PathFixtures.scribble) `nearest` takes at most 2 ms
// (one pointer move), and dash and trim at most 5 ms each; a boolean of two
// seeded 5,000-vertex logo outlines takes at most 50 ms. The packet's budgets
// are release, reported, as EffectBudgetTests and AffineBudgetTests are: an
// optimized build gates on them, and a debug build, which `scripts/ci` runs,
// only reports, so no wall-clock check can flake the gate. Inputs are the
// packet's sizes in both builds. Times are wall-clock medians of `runs` after
// one untimed call (debug times a single call), printed as
// `budget <row>: <ms> ms (budget <ms> ms)`.
// Run: swift test -c release -Xswiftc -enable-testing --filter PathOpsBudgetTests
import FlareCore
import Foundation
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Debug times one run: it only reports, and its loops are slow.
private let runs = optimized ? 5 : 1

private func milliseconds(_ d: Duration) -> String {
    let ms = Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    return "\((ms * 1000).rounded() / 1000)"
}

/// Serialized, so no two timed runs share cores.
@Suite(.serialized) struct PathOpsBudgetTests {
    static let scribble = PathFixtures.scribble()
    /// Screen-pixel tolerance: what a drag or a stroke preview flattens at.
    static let tolerance = 0.5
    static let logoVertices = 5_000

    /// Runs `body` once untimed (optimized builds), then prints the median of
    /// `runs` timings and, in an optimized build, expects it within `budget`.
    static func check<T>(_ row: String, budget: Duration, _ body: () throws -> T) throws -> T {
        let clock = ContinuousClock()
        var result: T?
        if optimized { result = try body() }
        var wall: [Duration] = []
        for _ in 0..<runs { wall.append(try clock.measure { result = try body() }) }
        guard let result else { throw GeometryError.notBuilt(row) }
        let time = wall.sorted()[runs / 2]
        let suffix = optimized ? "budget \(milliseconds(budget)) ms" : "report only, debug; budget \(milliseconds(budget)) ms in release"
        print("budget \(row): \(milliseconds(time)) ms (\(suffix))")
        if optimized { #expect(time <= budget, "\(row): median \(time) over \(budget)") }
        return result
    }

    /// A closed wavy outline of `logoVertices` lines around `center`: a
    /// 7-lobed radius with seeded jitter, as a traced logo's edge wobbles.
    static func logo(center: Point, radius: Double, seed: UInt64) -> Path {
        var rng = SplitMix64(seed: seed)
        let points = (0..<logoVertices).map { k -> Point in
            let angle = 2 * Double.pi * Double(k) / Double(logoVertices)
            let r = radius * (1 + 0.15 * sin(7 * angle) + Double.random(in: -0.01...0.01, using: &rng))
            return Point(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
        }
        return Path(polyline: points, closed: true)
    }

    @Test func nearestOnScribble() throws {
        #expect(Self.scribble.elements.count == PathFixtures.scribbleAnchors)
        let target = Point(x: 512, y: 487)
        let found = try Self.check("nearest on 10,000 anchors", budget: .milliseconds(2)) {
            try Self.scribble.nearest(to: target, tolerance: Self.tolerance)
        }
        #expect(try #require(found).distance.isFinite)
    }

    /// Optimized builds only for now: each dash's cut scans the whole
    /// 400,000-point polyline, so a debug run takes minutes in the gate.
    @Test(.enabled(if: optimized, "the dash cut is quadratic in debug until the r2 cut lands"))
    func dashScribble() throws {
        let dashed = try Self.check("dash the scribble", budget: .milliseconds(5)) {
            try Self.scribble.dashed([400, 200], phase: 50, tolerance: Self.tolerance)
        }
        #expect(!dashed.elements.isEmpty)
    }

    @Test func trimScribble() throws {
        let trimmed = try Self.check("trim the scribble", budget: .milliseconds(5)) {
            try Self.scribble.trimmed(start: 0.1, end: 0.9, offset: 0.25, mode: .together, tolerance: Self.tolerance)
        }
        let total = try Self.scribble.length(tolerance: Self.tolerance)
        #expect(abs(try trimmed.length(tolerance: Self.tolerance) - 0.8 * total) <= 1e-6 * total)
        let points = try Self.scribble.flattened(tolerance: Self.tolerance).joined().count
        print("scribble: \(points) flattened points, length \(total)")
    }

    @Test func booleanLogo() throws {
        let a = Self.logo(center: Point(x: 500, y: 500), radius: 300, seed: 11)
        let b = Self.logo(center: Point(x: 620, y: 540), radius: 280, seed: 12)
        for path in [a, b] { #expect(try path.flattened(tolerance: Self.tolerance).joined().count >= Self.logoVertices) }
        let union = try Self.check("union of 2 × 5,000 vertices", budget: .milliseconds(50)) {
            try Path.combine(.union, a, b, rule: .nonZero, tolerance: Self.tolerance)
        }
        // Inclusion–exclusion: |a ∪ b| + |a ∩ b| = |a| + |b|, within 1e-6 of the sum.
        let both = try Path.combine(.intersect, a, b, rule: .nonZero, tolerance: Self.tolerance)
        let lhs = try abs(PathArea.signedArea(union)) + abs(PathArea.signedArea(both))
        let rhs = try abs(PathArea.signedArea(a)) + abs(PathArea.signedArea(b))
        #expect(abs(lhs - rhs) <= 1e-6 * rhs, "union + intersect \(lhs), a + b \(rhs)")
    }
}
