// SmudgeTests.swift: retouch-heal RH-6's acceptance, written first by RH-1
// (docs/blueprints/core/features/retouch-heal.md); RH-6 turned it on.
import CoreRaster
import Testing

@Suite struct SmudgeTests {
    static let dabRadius = 4

    /// The red edge (red below column 20, white from it) after a stroke of
    /// `count` dabs stepping 2 px right from column 14 along rows 6...13.
    static func stroke(strength: Float, count: Int) throws -> (before: PixelBuffer, after: PixelBuffer) {
        let before = try RetouchFixtures.redEdge(width: 60, height: 20, edgeX: 20)
        var after = before
        var state = SmudgeState(strength: strength)
        let dab = try RetouchFixtures.roundDab(radius: dabRadius)
        for i in 0..<count { try state.dab(dab, x: 14 + 2 * i, y: 6, on: &after) }
        return (before, after)
    }

    /// How red a pixel is: 0 for white, 1 for pure red.
    static func redness(_ buffer: PixelBuffer, x: Int, y: Int) throws -> Float {
        let p = try buffer.pixel(x: x, y: y)
        return p.r - (p.g + p.b) / 2
    }

    @Test func firstDabPicksUp() throws {
        let (before, after) = try Self.stroke(strength: 1, count: 1)
        #expect(after == before)
    }

    @Test func colourDrags() throws {
        let (before, after) = try Self.stroke(strength: 0.6, count: 10)
        #expect(try Self.redness(before, x: 24, y: 10) == 0 && Self.redness(after, x: 24, y: 10) > 0.05)
    }

    @Test func colourFades() throws {
        // Dab centres sit at columns 18, 20, ..., 36; past the edge the red falls strictly.
        let (_, after) = try Self.stroke(strength: 0.6, count: 10)
        let samples = try [22, 26, 30, 34].map { try Self.redness(after, x: $0, y: 10) }
        for (near, far) in zip(samples, samples.dropFirst()) {
            #expect(far < near, "redness along the stroke \(samples)")
        }
        #expect(samples.last.map { $0 > 0 } == true)
    }

    @Test func strengthZeroIsIdentity() throws {
        let (before, after) = try Self.stroke(strength: 0, count: 10)
        #expect(after == before)
    }

    @Test func outsideBoundsUntouched() throws {
        let (before, after) = try Self.stroke(strength: 1, count: 10)
        try expectSameOutside(after, before, cx: 27, cy: 10, r: 13)
        #expect(after != before)
    }

    @Test func sizeChangeOnlyPicksUp() throws {
        // A dab of a new size lays nothing: it starts a new pick-up, like the first dab.
        let before = try RetouchFixtures.redEdge(width: 30, height: 20, edgeX: 10)
        var after = before
        var state = SmudgeState(strength: 1)
        try state.dab(Mask(width: 5, height: 5, fill: 1), x: 6, y: 6, on: &after)
        try state.dab(Mask(width: 7, height: 7, fill: 1), x: 8, y: 6, on: &after)
        #expect(after == before)
        try state.dab(Mask(width: 7, height: 7, fill: 1), x: 10, y: 6, on: &after)
        #expect(after != before)
    }

    @Test func statesCompareByCarriedPatch() throws {
        let buffer = try RetouchFixtures.redEdge(width: 30, height: 20, edgeX: 10)
        let dab = try RetouchFixtures.roundDab(radius: 3)
        var a = SmudgeState(strength: 0.5), b = SmudgeState(strength: 0.5)
        var bufferA = buffer, bufferB = buffer
        #expect(a == b)
        for x in [4, 6, 8] {
            try a.dab(dab, x: x, y: 5, on: &bufferA)
            try b.dab(dab, x: x, y: 5, on: &bufferB)
        }
        #expect(a == b && bufferA == bufferB)
        let copy = a
        try a.dab(dab, x: 10, y: 5, on: &bufferA)
        #expect(a != b && copy == b)
        #expect(Set([a, b, copy]).count == 2)
    }

    @Test func featherWeightsByCoverage() throws {
        // Dab 1 at column 14 picks up; dab 2 at column 16 lays it, so dab pixel
        // (i, j) gets the colour from 2 px left, weighted by the dab's coverage.
        let before = try RetouchFixtures.redEdge(width: 60, height: 20, edgeX: 20)
        var after = before
        var state = SmudgeState(strength: 1)
        let dab = try RetouchFixtures.roundDab(radius: 4, hardness: 0.5)
        try state.dab(dab, x: 14, y: 6, on: &after)
        try state.dab(dab, x: 16, y: 6, on: &after)
        let full = try Self.redness(after, x: 20, y: 10) - Self.redness(before, x: 20, y: 10)
        #expect(try dab.coverage(x: 4, y: 4) == 1 && full > 0.99)
        var feathered = 0
        for j in 0..<dab.height {
            for i in 0..<dab.width {
                let c = try dab.coverage(x: i, y: j)
                let p = try before.pixel(x: 16 + i, y: 6 + j), q = try before.pixel(x: 14 + i, y: 6 + j)
                let got = try after.pixel(x: 16 + i, y: 6 + j)
                let want = [p.r * (1 - c) + q.r * c, p.g * (1 - c) + q.g * c, p.b * (1 - c) + q.b * c]
                for (g, w) in zip([got.r, got.g, got.b], want) {
                    #expect(abs(g - w) < 1e-5, "pixel (\(i), \(j)) at coverage \(c)")
                }
                guard c > 0, c < 1, p != q else { continue }
                feathered += 1
                let change = try Self.redness(after, x: 16 + i, y: 6 + j) - Self.redness(before, x: 16 + i, y: 6 + j)
                #expect(change > 0 && change < full, "pixel (\(i), \(j)) at coverage \(c)")
            }
        }
        #expect(feathered > 0)
    }

    @Test func fuzzedDabsThrowOrSmudge() throws {
        var rng = SplitMix64(seed: 0x5D06)
        let positions = [Int.min, -9, -2, 0, 3, 17, 25, Int.max]
        let dab = try RetouchFixtures.roundDab(radius: 3, hardness: 0.5)
        for _ in 0..<40 {
            var buffer = try RetouchFixtures.redEdge(width: 24, height: 16, edgeX: 12)
            let strength = [Float.nan, .infinity, -0.1, 1.5, .random(in: 0...1, using: &rng)].randomElement(using: &rng) ?? 0
            var state = SmudgeState(strength: strength)
            for _ in 0..<8 {
                let x = positions.randomElement(using: &rng) ?? 0, y = positions.randomElement(using: &rng) ?? 0
                do {
                    try state.dab(dab, x: x, y: y, on: &buffer)
                    #expect((0...1).contains(strength) && buffer.width == 24 && buffer.height == 16)
                } catch is RasterError {
                } catch {
                    Issue.record("unexpected error \(error)")
                }
            }
        }
    }
}
