// Sampling+Tracks.swift: a layer's colour, stroke width, trim and shape tracks at a frame. `sampledShape` is the
// one place a shape's animated values resolve: the render list calls it for every shape it walks, so the stage, hit
// testing, PNG frames and the SVG export all draw the same values (shape tracks morph in Sampling+TracksMorph.swift).
// nil from a single-track sampler means the track is empty, so the caller uses the static value.
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

    /// Shape `index` of `shapes` as it draws at `frame`: its fill colour, stroke colour, stroke width, stroke trim
    /// and path sampled from this layer's tracks. A keyed fill colour replaces any fill, gradients included, with
    /// that solid. A sampled width below 0 draws as 0, the least a stroke may have. Stroke tracks change an existing
    /// stroke only. An empty shape for an index past `shapes`.
    public func sampledShape(_ index: Int, at frame: Double) -> Shape {
        guard shapes.indices.contains(index) else { return Shape(points: []) }
        let shape = shapes[index]
        var out = shape
        if let color = sampledColor(.fill(shape: index), at: frame) { out.fill = .solid(color) }
        if var stroke = shape.stroke {
            if let color = sampledColor(.stroke(shape: index), at: frame) { stroke.color = color }
            if let keys = tracks[Layer.trackKey(strokeWidthOf: index)], let width = Timeline.value(of: keys, at: frame) {
                stroke.width = max(width, 0)
            }
            stroke.trim = sampledTrim(of: index, base: stroke.trim, at: frame)
            out.stroke = stroke
        }
        if let path = sampledPath(shape: index, at: frame) { out.path = path }
        return out
    }
}
