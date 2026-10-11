// Timeline.swift: frame/time conversion and keyframe interpolation.
//
// Frames are integers; time is seconds as Double. Interpolation takes a Double
// frame so sub-frame sampling (motion blur, export at a higher rate) works.
// Keyframes passed in must be sorted by frame (FlareFormat.validate and the
// keyframe commands guarantee this). Nothing here crashes on bad input:
// invalid fps or time throws, and interpolation of unusable input returns nil.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public enum TimelineError: Error, Equatable, Sendable {
    case invalidFPS(Int)
    case invalidTime(Double)
}

public enum Timeline {
    /// Seconds at the start of `frame`.
    public static func time(ofFrame frame: Int, fps: Int) throws -> Double {
        guard fps > 0 else { throw TimelineError.invalidFPS(fps) }
        return Double(frame) / Double(fps)
    }

    /// The frame showing at `seconds` (floor). A tiny epsilon keeps exact frame
    /// boundaries such as 1.0 / 3 * 3 from landing one frame early.
    public static func frame(atTime seconds: Double, fps: Int) throws -> Int {
        guard fps > 0 else { throw TimelineError.invalidFPS(fps) }
        let f = (seconds * Double(fps) + 1e-9).rounded(.down)
        guard f.isFinite, abs(f) < 1e15 else { throw TimelineError.invalidTime(seconds) }
        return Int(f)
    }

    /// Value of a sorted keyframe track at `frame`. Holds the first value
    /// before the first keyframe and the last value after the last one.
    /// Returns nil for an empty track or a non-finite frame.
    public static func value(of keyframes: [Keyframe], at frame: Double) -> Double? {
        guard frame.isFinite, let first = keyframes.first, let last = keyframes.last else { return nil }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        // ponytail: linear scan; binary search when tracks get long (docs/gaps.md).
        for (a, b) in zip(keyframes, keyframes.dropFirst()) where frame < Double(b.frame) {
            let span = Double(b.frame) - Double(a.frame)  // no Int overflow
            guard span > 0 else { return b.value }
            let t = a.easing.value(at: (frame - Double(a.frame)) / span)
            return a.value + (b.value - a.value) * t
        }
        return last.value
    }
}
