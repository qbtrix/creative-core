// Sampling+Tracks.swift: a layer's colour tracks at a frame, for rendering and
// export (shape tracks morph in Sampling+TracksMorph.swift). nil means the
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
}
