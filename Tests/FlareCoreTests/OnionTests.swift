// OnionTests.swift: Timeline.onionFrames, the frames an onion skin shows
// around the playhead, clamped to the owner's duration.
import FlareCore
import Testing

@Suite struct OnionTests {
    @Test func framesAroundThePlayhead() {
        #expect(Timeline.onionFrames(at: 10, before: 2, after: 2, durationFrames: 48) == [8, 9, 11, 12])
    }

    @Test func framesPastTheStartAreDropped() {
        #expect(Timeline.onionFrames(at: 1, before: 2, after: 2, durationFrames: 48) == [0, 2, 3])
        #expect(Timeline.onionFrames(at: 0, before: 3, after: 0, durationFrames: 48) == [])
    }

    @Test func framesPastTheEndAreDropped() {
        #expect(Timeline.onionFrames(at: 47, before: 2, after: 2, durationFrames: 48) == [45, 46])
        #expect(Timeline.onionFrames(at: 46, before: 0, after: 3, durationFrames: 48) == [47])
    }

    @Test func zeroCountsGiveNothing() {
        #expect(Timeline.onionFrames(at: 10, before: 0, after: 0, durationFrames: 48) == [])
    }

    @Test func negativeCountsCountAsZero() {
        #expect(Timeline.onionFrames(at: 10, before: -3, after: 2, durationFrames: 48) == [11, 12])
        #expect(Timeline.onionFrames(at: 10, before: 2, after: -3, durationFrames: 48) == [8, 9])
    }

    @Test func oneFrameSceneGivesNothing() {
        #expect(Timeline.onionFrames(at: 0, before: 5, after: 5, durationFrames: 1) == [])
    }

    @Test func emptyOrNegativeDurationGivesNothing() {
        #expect(Timeline.onionFrames(at: 0, before: 2, after: 2, durationFrames: 0) == [])
        #expect(Timeline.onionFrames(at: 0, before: 2, after: 2, durationFrames: -5) == [])
        #expect(Timeline.onionFrames(at: 3, before: 2, after: 2, durationFrames: Int.min) == [])
    }

    @Test func playheadOutsideTheSceneStillClamps() {
        #expect(Timeline.onionFrames(at: 50, before: 4, after: 1, durationFrames: 48) == [46, 47])
        #expect(Timeline.onionFrames(at: -2, before: 1, after: 3, durationFrames: 48) == [0, 1])
        #expect(Timeline.onionFrames(at: 60, before: 2, after: 2, durationFrames: 48) == [])
    }

    @Test func extremeValuesNeverTrap() {
        let d = 48
        let cases: [(Int, Int, Int)] = [
            (10, Int.max, Int.max), (Int.min, Int.max, Int.max), (Int.max, Int.max, Int.max),
            (Int.min, 2, 2), (Int.max, 2, 2), (Int.min, 0, Int.max), (Int.max, Int.max, 0),
            (Int.min, Int.min, Int.min),
        ]
        for (frame, before, after) in cases {
            let frames = Timeline.onionFrames(at: frame, before: before, after: after, durationFrames: d)
            #expect(frames.allSatisfy { (0..<d).contains($0) })
            #expect(!frames.contains(frame))
        }
        #expect(Timeline.onionFrames(at: 10, before: Int.max, after: Int.max, durationFrames: 13)
            == [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12])
        // Counts are capped, so a playhead far past the end shows nothing.
        #expect(Timeline.onionFrames(at: Int.max, before: Int.max, after: 0, durationFrames: 3) == [])
        #expect(Timeline.onionFrames(at: Int.min, before: 0, after: Int.max, durationFrames: 3) == [])
        #expect(Timeline.onionFrames(at: -1, before: 0, after: Int.max, durationFrames: 3) == [0, 1, 2])
        #expect(Timeline.onionFrames(at: -2, before: Int.max, after: Int.max, durationFrames: 3) == [0, 1, 2])
        #expect(Timeline.onionFrames(at: 2, before: 0, after: Int.max, durationFrames: 5) == [3, 4])
        // A huge duration with huge counts stays bounded by the cap on each side.
        let cap = Timeline.maxOnionSkins
        let huge = Timeline.onionFrames(at: 5_000, before: Int.max, after: Int.max, durationFrames: 1_000_000_000_000)
        #expect(huge == Array((5_000 - cap)..<5_000) + Array(5_001...(5_000 + cap)))
        #expect(Timeline.onionFrames(at: 0, before: 0, after: Int.max, durationFrames: Int.max).count == cap)
        // `frame + after` overflows Int; it saturates, so the window ends at the last frame.
        #expect(Timeline.onionFrames(at: Int.max - 1, before: 5, after: 5, durationFrames: Int.max)
            == Array((Int.max - 6)...(Int.max - 2)))
        #expect(Timeline.onionFrames(at: cap + 50, before: cap + 5, after: 0, durationFrames: cap + 100).first == 50)
        #expect(Timeline.onionFrames(at: 0, before: 0, after: cap + 5, durationFrames: cap + 100).last == cap)
    }

    @Test func seededPropertyAscendingUniqueInRangeWithoutPlayhead() {
        var rng = SplitMix64(seed: 0x0_1A0E)
        for _ in 0..<2_000 {
            let d = Int.random(in: -3...60, using: &rng)
            let frame = Int.random(in: -10...70, using: &rng)
            let before = Int.random(in: -5...20, using: &rng)
            let after = Int.random(in: -5...20, using: &rng)
            let frames = Timeline.onionFrames(at: frame, before: before, after: after, durationFrames: d)
            #expect(zip(frames, frames.dropFirst()).allSatisfy { $0 < $1 })
            #expect(frames.allSatisfy { $0 >= 0 && $0 < d })
            #expect(!frames.contains(frame))
            let expected = (0..<max(d, 0)).filter {
                $0 != frame && $0 >= frame - max(before, 0) && $0 <= frame + max(after, 0)
            }
            #expect(frames == expected)
        }
    }
}
