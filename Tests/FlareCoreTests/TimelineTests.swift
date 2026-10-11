// TimelineTests.swift: frame/time conversion and keyframe interpolation.
import FlareCore
import Foundation
import Testing

@Suite struct TimelineTests {
    @Test func frameTimeConversion() throws {
        #expect(try Timeline.time(ofFrame: 0, fps: 24) == 0)
        #expect(try Timeline.time(ofFrame: 48, fps: 24) == 2)
        #expect(try Timeline.frame(atTime: 2, fps: 24) == 48)
        #expect(try Timeline.frame(atTime: 0.999, fps: 24) == 23)
        // Exact boundary at an awkward rate must not land a frame early.
        #expect(try Timeline.frame(atTime: 1.0 / 3.0 * 3.0, fps: 30) == 30)
        for f in 0..<500 {
            #expect(try Timeline.frame(atTime: Timeline.time(ofFrame: f, fps: 30), fps: 30) == f)
        }
    }

    @Test func invalidInputThrows() {
        #expect(throws: TimelineError.invalidFPS(0)) { try Timeline.time(ofFrame: 1, fps: 0) }
        #expect(throws: TimelineError.invalidFPS(-5)) { try Timeline.frame(atTime: 1, fps: -5) }
        #expect(throws: TimelineError.self) { try Timeline.frame(atTime: .nan, fps: 24) }
        #expect(throws: TimelineError.self) { try Timeline.frame(atTime: 1e300, fps: 24) }
    }

    @Test func playbackFrameLoopsOrClamps() throws {
        #expect(try Timeline.playbackFrame(elapsed: 2.5, fps: 24, durationFrames: 48, loop: true) == 12)
        #expect(try Timeline.playbackFrame(elapsed: 2.5, fps: 24, durationFrames: 48, loop: false) == 47)
        #expect(try Timeline.playbackFrame(elapsed: -1, fps: 24, durationFrames: 48, loop: true) == 0)
        #expect(try Timeline.playbackFrame(elapsed: -1, fps: 24, durationFrames: 48, loop: false) == 0)
        #expect(try Timeline.playbackFrame(elapsed: 1, fps: 24, durationFrames: 48, loop: false) == 24)
        #expect(try Timeline.playbackFrame(elapsed: 2, fps: 24, durationFrames: 48, loop: true) == 0)
        #expect(try Timeline.playbackFrame(elapsed: 5, fps: 24, durationFrames: 0, loop: true) == 0)
        #expect(try Timeline.playbackFrame(elapsed: 5, fps: 24, durationFrames: -3, loop: false) == 0)
        // Huge but finite times never overflow.
        let wrapped = try Timeline.playbackFrame(elapsed: 1e300, fps: 24, durationFrames: 48, loop: true)
        #expect((0..<48).contains(wrapped))
        #expect(try Timeline.playbackFrame(elapsed: 1e300, fps: 24, durationFrames: Int.max, loop: false) == Int.max - 1)
    }

    @Test func playbackFrameRejectsBadInput() {
        #expect(throws: TimelineError.invalidFPS(0)) {
            try Timeline.playbackFrame(elapsed: 1, fps: 0, durationFrames: 48, loop: true)
        }
        #expect(throws: TimelineError.self) {
            try Timeline.playbackFrame(elapsed: .nan, fps: 24, durationFrames: 48, loop: true)
        }
        #expect(throws: TimelineError.self) {
            try Timeline.playbackFrame(elapsed: .infinity, fps: 24, durationFrames: 48, loop: false)
        }
    }

    @Test func playbackFrameStaysInRange() throws {
        var rng = SplitMix64(seed: 12)
        for _ in 0..<1000 {
            let duration = Int(rng.next() % 500) + 1
            let elapsed = Double(rng.next() % 1_000_000) / 1000 - 100
            for loop in [true, false] {
                let f = try Timeline.playbackFrame(elapsed: elapsed, fps: 30, durationFrames: duration, loop: loop)
                #expect((0..<duration).contains(f))
            }
        }
    }

    @Test func interpolatesLinearly() {
        let track = [Keyframe(frame: 0, value: 0), Keyframe(frame: 10, value: 100)]
        #expect(Timeline.value(of: track, at: 5) == 50)
        #expect(Timeline.value(of: track, at: 2.5) == 25)
    }

    @Test func holdsBeforeFirstAndAfterLast() {
        let track = [Keyframe(frame: 10, value: 3), Keyframe(frame: 20, value: 7)]
        #expect(Timeline.value(of: track, at: 0) == 3)
        #expect(Timeline.value(of: track, at: 10) == 3)
        #expect(Timeline.value(of: track, at: 20) == 7)
        #expect(Timeline.value(of: track, at: 99) == 7)
    }

    @Test func appliesOutgoingEasing() {
        let track = [Keyframe(frame: 0, value: 0, easing: .easeIn), Keyframe(frame: 10, value: 10),
                     Keyframe(frame: 20, value: 0)]
        let eased = Timeline.value(of: track, at: 3)
        #expect(eased != nil && eased! < 3)  // ease-in starts slow
        #expect(Timeline.value(of: track, at: 15) == 5)  // second segment is linear
    }

    @Test func holdEasingJumpsAtNextKeyframe() throws {
        let track = [Keyframe(frame: 0, value: 0, easing: .hold), Keyframe(frame: 10, value: 10)]
        #expect(Timeline.value(of: track, at: 5) == 0)
        #expect(Timeline.value(of: track, at: 9.99) == 0)
        #expect(Timeline.value(of: track, at: 10) == 10)
        let data = try JSONEncoder().encode(track)
        #expect(try JSONDecoder().decode([Keyframe].self, from: data) == track)
    }

    @Test func degenerateInputReturnsNilOrHolds() {
        #expect(Timeline.value(of: [], at: 1) == nil)
        #expect(Timeline.value(of: [Keyframe(frame: 0, value: 1)], at: .nan) == nil)
        #expect(Timeline.value(of: [Keyframe(frame: 4, value: 1)], at: 100) == 1)
        let extreme = [Keyframe(frame: Int.min, value: 0), Keyframe(frame: Int.max, value: 1)]
        #expect(Timeline.value(of: extreme, at: 0) != nil)
    }

    /// The pre-G39 linear scan, kept as the oracle for the binary search.
    static func linearScanValue(of keyframes: [Keyframe], at frame: Double) -> Double? {
        guard frame.isFinite, let first = keyframes.first, let last = keyframes.last else { return nil }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        for (a, b) in zip(keyframes, keyframes.dropFirst()) where frame < Double(b.frame) {
            let span = Double(b.frame) - Double(a.frame)
            guard span > 0 else { return b.value }
            let t = a.easing.value(at: (frame - Double(a.frame)) / span)
            return a.value + (b.value - a.value) * t
        }
        return last.value
    }

    @Test func binarySearchMatchesLinearScan() {
        var rng = SplitMix64(seed: 39)
        let easings: [Easing] = [.linear, .hold, .easeIn, .easeInOut]
        for trial in 0..<200 {
            let count = trial == 0 ? 1 : (trial == 1 ? 1_000 : Int.random(in: 1...1_000, using: &rng))
            var frame = Int.random(in: -50...50, using: &rng)
            var track: [Keyframe] = []
            for _ in 0..<count {
                frame += Int.random(in: 0...5, using: &rng)  // 0 makes duplicate frames
                track.append(Keyframe(frame: frame, value: Double.random(in: -100...100, using: &rng),
                                      easing: easings[Int.random(in: 0..<easings.count, using: &rng)]))
            }
            let lo = Double(track[0].frame) - 3, hi = Double(frame) + 3
            for _ in 0..<50 {
                let exact = Double(track[Int.random(in: 0..<count, using: &rng)].frame)
                let sample = Bool.random(using: &rng) ? exact : Double.random(in: lo...hi, using: &rng)
                #expect(Timeline.value(of: track, at: sample) == Self.linearScanValue(of: track, at: sample))
            }
        }
    }
}
