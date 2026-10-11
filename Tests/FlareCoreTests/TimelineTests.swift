// TimelineTests.swift: frame/time conversion and keyframe interpolation.
import FlareCore
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

    @Test func degenerateInputReturnsNilOrHolds() {
        #expect(Timeline.value(of: [], at: 1) == nil)
        #expect(Timeline.value(of: [Keyframe(frame: 0, value: 1)], at: .nan) == nil)
        #expect(Timeline.value(of: [Keyframe(frame: 4, value: 1)], at: 100) == 1)
        let extreme = [Keyframe(frame: Int.min, value: 0), Keyframe(frame: Int.max, value: 1)]
        #expect(Timeline.value(of: extreme, at: 0) != nil)
    }
}
