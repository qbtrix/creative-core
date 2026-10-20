// Sampling.swift: a layer's property values at a frame, for rendering and export.
//
// Every track is sampled with Timeline.value; standard transform properties
// without a track get their defaults. Opacity is clamped to 0...1.
// `placement` packs the standard properties, the anchor point included, into a Transform and opacity.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Layer {
    /// Default values of the standard properties when a layer has no track for them.
    public static let standardDefaults: [String: Double] = [
        "x": 0, "y": 0, "scaleX": 1, "scaleY": 1, "rotation": 0, "opacity": 1, "anchorX": 0, "anchorY": 0,
    ]

    /// Every track's value at `frame`, plus defaults for standard properties
    /// that have no track. A non-finite frame yields only the defaults.
    public func sample(at frame: Double) -> [String: Double] {
        var values = Layer.standardDefaults
        for (property, keyframes) in tracks {
            if let value = Timeline.value(of: keyframes, at: frame) {
                values[property] = value
            }
        }
        if let opacity = values["opacity"] {
            // NaN opacity falls back to fully opaque rather than leaking out.
            values["opacity"] = opacity.isNaN ? 1 : min(max(opacity, 0), 1)
        }
        return values
    }
}

extension Layer {
    /// The layer's sampled position, scale and rotation, and its opacity, at `frame`.
    public func placement(at frame: Double) -> (transform: Transform, opacity: Double) {
        let s = sample(at: frame)
        let transform = Transform(
            x: s["x"] ?? 0, y: s["y"] ?? 0,
            scaleX: s["scaleX"] ?? 1, scaleY: s["scaleY"] ?? 1,
            rotation: s["rotation"] ?? 0, anchorX: s["anchorX"] ?? 0, anchorY: s["anchorY"] ?? 0
        )
        return (transform, s["opacity"] ?? 1)
    }
}
