// Sampling+Tracks.swift: a layer's colour tracks and stroke trim tracks at a frame, for
// rendering and export (shape tracks morph in Sampling+TracksMorph.swift). nil means the
// track is empty, so the caller uses the shape's or text's static colour.
// Colour blends each encoded sRGB component (not linear light, as Lottie
// players do, so stage and export agree) through `Timeline.value`: the same
// key lookup, left-key easing, hold and held ends as every Double track.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Layer {
    /// `target`'s colour at `frame`, interpolated between its keys in encoded
    /// sRGB with each key's easing, or nil when the track is empty or missing
    /// (use the static colour) or `frame` is not finite.
    public func sampledColor(_ target: TrackTarget, at frame: Double) -> Color? {
        guard let keys = colorTracks[target.key] else { return nil }
        let component = { (c: KeyPath<Color, Double>) -> Double? in
            Timeline.value(of: keys.map { Keyframe(frame: $0.frame, value: $0.value[keyPath: c], easing: $0.easing) }, at: frame)
        }
        guard let r = component(\.r), let g = component(\.g), let b = component(\.b), let a = component(\.a) else { return nil }
        return Color(r: r, g: g, b: b, a: a)
    }

    /// Shape `index`'s stroke trim at `frame`: `base` (a whole-outline trim
    /// when nil) with each of its `trimStart.<i>`, `trimEnd.<i>` and
    /// `trimOffset.<i>` tracks sampled in; start and end clamp to 0...1.
    /// `base` itself when none of the three is keyed.
    public func sampledTrim(of index: Int, base: StrokeTrim?, at frame: Double) -> StrokeTrim? {
        func value(_ key: String) -> Double? { tracks[key].flatMap { Timeline.value(of: $0, at: frame) } }
        let start = value(Layer.trackKey(trimStartOf: index)), end = value(Layer.trackKey(trimEndOf: index))
        let offset = value(Layer.trackKey(trimOffsetOf: index))
        guard start != nil || end != nil || offset != nil else { return base }
        var trim = base ?? StrokeTrim()
        if let start { trim.start = min(max(start, 0), 1) }
        if let end { trim.end = min(max(end, 0), 1) }
        if let offset { trim.offset = offset }
        return trim
    }
}
