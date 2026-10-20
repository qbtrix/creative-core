// PathTrimDashTests.swift: trim (wrapping offset, per contour) and dash (odd
// counts repeat, phase, contour restart) along the ruler; bad input throws.
import FlareCore
import Testing

private func pt(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
private let tol = 0.01

private func pieces(_ path: Path) throws -> [Double] {
    try path.flattened(tolerance: tol).map { try Path(polyline: $0, closed: false).length(tolerance: tol) }
}

private func distinct(_ lines: [[Point]]) -> [[Point]] {
    lines.map { line in line.enumerated().filter { $0.offset == 0 || line[$0.offset - 1] != $0.element }.map(\.element) }
}

private func close(_ a: [Double], _ b: [Double], _ eps: Double = 1e-9) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= eps }
}

@Suite struct PathTrimDashTests {
    static func rect() throws -> Path { try PathBuilders.rectangle(in: Rect(minX: 0, minY: 0, maxX: 100, maxY: 50)) }
    static let line120 = Path(polyline: [pt(0, 0), pt(120, 0)], closed: false)
    static let twoSquares = Path(elements:
        Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(0, 10)], closed: true).elements
        + Path(polyline: [pt(50, 0), pt(70, 0), pt(70, 20), pt(50, 20)], closed: true).elements)

    @Test func wholeTrimIsThePath() throws {
        let path = try Self.rect()
        let trimmed = try path.trimmed(start: 0, end: 1, offset: 0, mode: .together, tolerance: tol)
        #expect(try distinct(trimmed.flattened(tolerance: tol)) == distinct(path.flattened(tolerance: tol)))
    }

    @Test func middleHalfIsHalfTheLength() throws {
        let trimmed = try Self.rect().trimmed(start: 0.25, end: 0.75, offset: 0, mode: .together, tolerance: tol)
        #expect(close(try pieces(trimmed), [150]))
        #expect(try trimmed.flattened(tolerance: tol).first?.first == pt(75, 0))
        #expect(try Self.rect().trimmed(start: 0.4, end: 0.4, offset: 0, mode: .together, tolerance: tol).elements.isEmpty)
    }

    @Test func offsetWraps() throws {
        for offset in [0.5, 2.5, -0.5] {
            let trimmed = try Self.rect().trimmed(start: 0.25, end: 0.75, offset: offset, mode: .together, tolerance: tol)
            #expect(close(try pieces(trimmed), [75, 75]), "offset \(offset)")
        }
        #expect(close(try pieces(Self.rect().trimmed(start: 0.75, end: 0.25, offset: 0, mode: .together, tolerance: tol)), [75, 75]))
    }

    @Test func offsetIsAFractionAndEndsClamp() throws {
        // offset is a fraction of the length, not a distance: 1.25 is 0.25, and 25 is a whole number of turns.
        let quarter = try pieces(Self.line120.trimmed(start: 0, end: 0.5, offset: 0.25, mode: .together, tolerance: tol))
        #expect(close(quarter, [60]))
        #expect(close(try pieces(Self.line120.trimmed(start: 0, end: 0.5, offset: 1.25, mode: .together, tolerance: tol)), quarter))
        let turns = try Self.line120.trimmed(start: 0, end: 0.5, offset: 25, mode: .together, tolerance: tol)
        #expect(try turns.sample(atLength: 0, tolerance: tol)?.point == pt(0, 0) && close(try pieces(turns), [60]))
        // start and end outside 0...1 clamp to it.
        #expect(close(try pieces(Self.line120.trimmed(start: -0.5, end: 1.5, offset: 0, mode: .together, tolerance: tol)), [120]))
    }

    @Test func eachContourRestarts() throws {
        #expect(close(try pieces(Self.twoSquares.trimmed(start: 0, end: 0.5, offset: 0, mode: .eachContour, tolerance: tol)), [20, 40]))
        #expect(close(try pieces(Self.twoSquares.trimmed(start: 0, end: 0.5, offset: 0, mode: .together, tolerance: tol)), [40, 20]))
        // A dash pattern restarts at each contour: [30, 100] draws 30 of each.
        #expect(close(try pieces(Self.twoSquares.dashed([30, 100], phase: 0, tolerance: tol)), [30, 30]))
    }

    @Test func oddPatternRepeats() throws {
        let dashes = try Self.line120.dashed([10, 5, 5], phase: 0, tolerance: tol)
        #expect(close(try pieces(dashes), [10, 5, 5, 10, 5, 5, 10, 5, 5]))
        #expect(try dashes.flattened(tolerance: tol).map { $0.first?.x } == [0, 15, 30, 40, 55, 70, 80, 95, 110])
    }

    @Test func dashesOf10On300AndPhaseShiftsTheStart() throws {
        #expect(close(try pieces(Self.rect().dashed([10, 5], phase: 0, tolerance: tol)), Array(repeating: 10, count: 20)))
        let line = Path(polyline: [pt(0, 0), pt(30, 0)], closed: false)
        #expect(close(try pieces(line.dashed([10, 5], phase: 5, tolerance: tol)), [5, 10, 5]))
        #expect(close(try pieces(line.dashed([10, 5], phase: -5, tolerance: tol)), [10, 10]))
        #expect(close(try pieces(line.dashed([10, 5], phase: 7, tolerance: tol)), [3, 10, 7]))
    }

    @Test func refusals() throws {
        let path = try Self.rect()
        for pattern: [Double] in [[], [0, 0], [-1, 5], [.nan, 5], [.infinity, 1], Array(repeating: 1, count: 65),
                                 [1e308, 1e308]] {
            #expect(throws: GeometryError.invalidPattern) { try path.dashed(pattern, phase: 0, tolerance: tol) }
        }
        #expect(try !path.dashed(Array(repeating: 1, count: 64), phase: 0, tolerance: tol).elements.isEmpty)
        #expect(throws: GeometryError.nonFinite) { try path.dashed([1, 1], phase: .nan, tolerance: tol) }
        #expect(throws: GeometryError.invalidTolerance) { try path.dashed([1, 1], phase: 0, tolerance: 0) }
        for bad in [Double.nan, .infinity] {
            #expect(throws: GeometryError.nonFinite) { try path.trimmed(start: bad, end: 1, offset: 0, mode: .together, tolerance: tol) }
            #expect(throws: GeometryError.nonFinite) { try path.trimmed(start: 0, end: 1, offset: bad, mode: .eachContour, tolerance: tol) }
        }
        #expect(throws: GeometryError.invalidTolerance) { try path.trimmed(start: 0, end: 1, offset: 0, mode: .together, tolerance: -1) }
    }

    @Test func dashWalkIsCapped() throws {
        let long = Path(polyline: [pt(0, 0), pt(1000, 0)], closed: false)
        #expect(throws: GeometryError.tooComplex(1_000_000)) { try long.dashed([0, 0.001], phase: 0, tolerance: tol) }
        #expect(try long.dashed([0, 0.004], phase: 0, tolerance: tol).elements.isEmpty)
    }

    @Test func cutsTakeOnlyTheirOwnSpan() throws {
        let zig = Path(polyline: [pt(0, 0), pt(10, 0), pt(10, 10), pt(20, 10)], closed: false)
        #expect(try zig.dashed([10, 5], phase: 0, tolerance: tol).elements == [
            .move(to: pt(0, 0)), .line(to: pt(10, 0)), .move(to: pt(10, 5)), .line(to: pt(10, 10)), .line(to: pt(15, 10)),
        ])
        // 20,000 points and ~28,000 dashes: a cut that scans every point would take minutes.
        var rng = SplitMix64(seed: 432), x = 0.0
        let points = (0..<20_000).map { i -> Point in
            x += Double.random(in: 0.5...1.5, using: &rng)
            return pt(x, Double(i % 2))
        }
        let clock = ContinuousClock(), start = clock.now
        let dashes = try Path(polyline: points, closed: false).dashed([0.5, 0.5], phase: 0, tolerance: tol)
        #expect(clock.now - start < .seconds(3))
        #expect(dashes.elements.count > 40_000)
    }

    @Test func seededTrimKeepsLengthAndDashesStayOnTheRuler() throws {
        var rng = SplitMix64(seed: 430)
        for _ in 0..<300 {
            let path = PathGen.path(&rng), length = try path.length(tolerance: tol)
            let a = Double.random(in: 0...1, using: &rng), b = Double.random(in: 0...1, using: &rng)
            let (s, e) = (min(a, b), max(a, b))
            for mode in [TrimMode.together, .eachContour] {
                let trimmed = try path.trimmed(start: s, end: e, offset: PathGen.phase(&rng), mode: mode, tolerance: tol)
                #expect(abs(try trimmed.length(tolerance: tol) - (e - s) * length) <= 1e-6)
            }
            let pattern = PathGen.pattern(&rng)
            let dashes = try pieces(path.dashed(pattern, phase: PathGen.phase(&rng), tolerance: tol))
            #expect(dashes.allSatisfy { $0 >= 0 && $0 <= (pattern.max() ?? 0) + 1e-9 })
            #expect(dashes.reduce(0, +) <= length + 1e-6)
        }
    }

    @Test func hostilePathsThrowNotCrash() throws {
        var rng = SplitMix64(seed: 431)
        for _ in 0..<300 {
            let path = PathGen.hostile(&rng)
            #expect(throws: GeometryError.nonFinite) { try path.trimmed(start: 0.1, end: 0.9, offset: 0.3, mode: .together, tolerance: tol) }
            #expect(throws: GeometryError.nonFinite) { try path.dashed([3, 2], phase: 1, tolerance: tol) }
        }
    }
}
