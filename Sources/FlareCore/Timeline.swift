// Timeline.swift: frame/time conversion and keyframe interpolation.
//
// Frames are integers; time is seconds as Double. A scene's rate is an exact
// fraction (`SceneRate`, 29.97 is 30000/1001) so frame times at the NTSC rates
// don't drift; the `fps: Int` forms are the whole-rate case. Interpolation takes a Double
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
    /// `MachinePlayer` was asked for a state machine id the document lacks.
    case stateMachineNotFound(String)
    /// `MachinePlayer` was given a machine that breaks a rule: its first error issue.
    case invalidMachine(MachineIssue)
}

/// A frame rate as an exact fraction, frames per second = `numerator / denominator`, kept reduced: 29.97 is
/// 30000/1001 and 24 is 24/1. Valid when both parts are positive, the denominator is at most `maxDenominator` and
/// the rate at most `maxFPS`; `FlareFormat` and the commands refuse the rest, and nothing here traps on any Int.
/// Encodes as `{"num", "den"}`.
public struct SceneRate: Codable, Sendable, Hashable, CustomStringConvertible {
    public private(set) var numerator: Int
    public private(set) var denominator: Int

    /// The largest denominator a valid rate has (NTSC's is 1001).
    public static let maxDenominator = 1_000_000
    /// The fastest valid rate, in frames per second.
    public static let maxFPS = 1000

    /// `numerator / denominator`, reduced by their greatest common divisor (a zero or negative part is kept as
    /// given, so validation can name it).
    public init(numerator: Int, denominator: Int) {
        var (a, b) = (numerator.magnitude, denominator.magnitude)
        while b != 0 { (a, b) = (b, a % b) }
        let g = numerator > 0 && denominator > 0 && a > 1 ? Int(a) : 1
        (self.numerator, self.denominator) = (numerator / g, denominator / g)
    }

    /// `fps` frames per second.
    public init(whole fps: Int) { (numerator, denominator) = (fps, 1) }

    /// Decodes `{"num", "den"}` through the reducing init.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(numerator: try c.decode(Int.self, forKey: .numerator), denominator: try c.decode(Int.self, forKey: .denominator))
    }

    /// Both parts positive, the denominator at most `maxDenominator`, the rate at most `maxFPS`.
    public var isValid: Bool {
        numerator > 0 && denominator > 0 && denominator <= Self.maxDenominator && numerator <= Self.maxFPS * denominator
    }
    /// A whole number of frames per second.
    public var isWhole: Bool { denominator == 1 }
    /// Frames per second as a Double.
    public var value: Double { Double(numerator) / Double(denominator) }
    /// The whole rate nearest `value` (30 for 29.97): what an `fps: Int` reader sees.
    public var nominal: Int { isValid ? (numerator + denominator / 2) / denominator : 0 }
    public var description: String { isWhole ? "\(numerator)" : "\(numerator)/\(denominator)" }

    /// Seconds at the start of `frame`.
    public func seconds(ofFrame frame: Int) -> Double { Double(frame) * Double(denominator) / Double(numerator) }

    /// The rate a decimal `fps` stands for: an NTSC rate (n × 1000/1001 for n of 24, 30, 48, 60 or 120) when it
    /// is within 0.005 of one, as files write 29.97 rounded, else the nearest whole rate.
    public init(decimal fps: Double) {
        guard fps.isFinite, fps > 0, fps <= Double(Self.maxFPS) else {
            self.init(whole: 0)
            return
        }
        for n in [24, 30, 48, 60, 120] where abs(fps - Double(n) * 1000 / 1001) < 0.005 {
            self.init(numerator: n * 1000, denominator: 1001)
            return
        }
        self.init(whole: Int(fps.rounded()))
    }

    private enum CodingKeys: String, CodingKey { case numerator = "num", denominator = "den" }
}

public enum Timeline {
    /// Seconds at the start of `frame`.
    public static func time(ofFrame frame: Int, fps: Int) throws -> Double {
        try time(ofFrame: frame, rate: SceneRate(whole: fps))
    }

    /// Seconds at the start of `frame` at `rate`.
    public static func time(ofFrame frame: Int, rate: SceneRate) throws -> Double {
        guard rate.isValid else { throw TimelineError.invalidFPS(rate.numerator) }
        return rate.seconds(ofFrame: frame)
    }

    /// The frame showing at `seconds` (floor). A tiny epsilon keeps exact frame
    /// boundaries such as 1.0 / 3 * 3 from landing one frame early.
    public static func frame(atTime seconds: Double, fps: Int) throws -> Int {
        try frame(atTime: seconds, rate: SceneRate(whole: fps))
    }

    /// The frame showing at `seconds` at `rate` (floor, with the same epsilon).
    public static func frame(atTime seconds: Double, rate: SceneRate) throws -> Int {
        guard rate.isValid else { throw TimelineError.invalidFPS(rate.numerator) }
        let f = (seconds * rate.value + 1e-9).rounded(.down)
        guard f.isFinite, abs(f) < 1e15 else { throw TimelineError.invalidTime(seconds) }
        return Int(f)
    }

    /// The frame to show `elapsed` seconds into playback of a `durationFrames`
    /// long timeline. Looping wraps; play-once clamps to the last frame.
    /// Negative elapsed and a duration of 0 or less give frame 0.
    public static func playbackFrame(elapsed: Double, fps: Int, durationFrames: Int, loop: Bool) throws -> Int {
        try playbackFrame(elapsed: elapsed, rate: SceneRate(whole: fps), durationFrames: durationFrames, loop: loop)
    }

    /// `playbackFrame(elapsed:fps:durationFrames:loop:)` at an exact `rate`.
    public static func playbackFrame(elapsed: Double, rate: SceneRate, durationFrames: Int, loop: Bool) throws -> Int {
        guard rate.isValid else { throw TimelineError.invalidFPS(rate.numerator) }
        guard elapsed.isFinite else { throw TimelineError.invalidTime(elapsed) }
        guard durationFrames > 0, elapsed > 0 else { return 0 }
        // Same epsilon as frame(atTime:). Stays in Double so huge times cannot overflow Int.
        let f = (elapsed * rate.value + 1e-9).rounded(.down)
        let last = durationFrames - 1
        if !loop, f >= Double(last) { return last }  // compare before Int(): Double(Int.max) traps
        let mapped = loop ? f.truncatingRemainder(dividingBy: Double(durationFrames)) : f
        // mapped < 2^63 here; min guards Double rounding of durations near Int.max.
        return min(Int(mapped), last)
    }

    /// Value of a sorted keyframe track at `frame`. Holds the first value
    /// before the first keyframe and the last value after the last one.
    /// Returns nil for an empty track or a non-finite frame.
    public static func value(of keyframes: [Keyframe], at frame: Double) -> Double? {
        guard frame.isFinite, let first = keyframes.first, let last = keyframes.last else { return nil }
        if frame <= Double(first.frame) { return first.value }
        if frame >= Double(last.frame) { return last.value }
        // Binary search for the first keyframe after `frame`. first.frame < frame
        // < last.frame here, so hi lands in 1..<count and hi - 1 is valid.
        var lo = 1
        var hi = keyframes.count - 1
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if frame < Double(keyframes[mid].frame) { hi = mid } else { lo = mid + 1 }
        }
        guard hi > 0, hi < keyframes.count else { return last.value }
        let a = keyframes[hi - 1]
        let b = keyframes[hi]
        let span = Double(b.frame) - Double(a.frame)  // no Int overflow
        guard span > 0 else { return b.value }
        let t = a.easing.value(at: (frame - Double(a.frame)) / span)
        return a.value + (b.value - a.value) * t
    }
}
