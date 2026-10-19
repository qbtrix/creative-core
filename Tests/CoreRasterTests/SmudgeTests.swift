// SmudgeTests.swift: retouch-heal RH-6's acceptance, written first by RH-1
// (docs/blueprints/core/features/retouch-heal.md). Disabled until RH-6 lands.
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

    @Test(.disabled("waits on RH-6")) func firstDabPicksUp() throws {
        let (before, after) = try Self.stroke(strength: 1, count: 1)
        #expect(after == before)
    }

    @Test(.disabled("waits on RH-6")) func colourDrags() throws {
        let (before, after) = try Self.stroke(strength: 0.6, count: 10)
        #expect(try Self.redness(before, x: 24, y: 10) == 0 && Self.redness(after, x: 24, y: 10) > 0.05)
    }

    @Test(.disabled("waits on RH-6")) func colourFades() throws {
        // Dab centres sit at columns 18, 20, ..., 36; past the edge the red falls strictly.
        let (_, after) = try Self.stroke(strength: 0.6, count: 10)
        let samples = try [22, 26, 30, 34].map { try Self.redness(after, x: $0, y: 10) }
        for (near, far) in zip(samples, samples.dropFirst()) {
            #expect(far < near, "redness along the stroke \(samples)")
        }
        #expect(samples.last.map { $0 > 0 } == true)
    }

    @Test(.disabled("waits on RH-6")) func strengthZeroIsIdentity() throws {
        let (before, after) = try Self.stroke(strength: 0, count: 10)
        #expect(after == before)
    }

    @Test(.disabled("waits on RH-6")) func outsideBoundsUntouched() throws {
        let (before, after) = try Self.stroke(strength: 1, count: 10)
        try expectSameOutside(after, before, cx: 27, cy: 10, r: 13)
        #expect(after != before)
    }

    @Test(.disabled("waits on RH-6")) func fuzzedDabsThrowOrSmudge() throws {
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
