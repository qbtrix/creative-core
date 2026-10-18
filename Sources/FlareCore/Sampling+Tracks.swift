// Sampling+Tracks.swift: a layer's colour and shape tracks at a frame, for
// rendering and export. nil means the track is empty, so the caller uses the
// shape's or text's static value. Stubs today (animate-properties AP-1): both
// answer nil, which is the static value, until AP-5 builds colour sampling
// and AP-6 morph sampling. Their signatures are the packet's contract.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Layer {
    /// `target`'s colour at `frame`, interpolated between its keys in encoded
    /// sRGB with each key's easing, or nil when the track is empty (use the
    /// static colour). Stub: always nil until AP-5.
    public func sampledColor(_ target: TrackTarget, at frame: Double) -> Color? {
        nil
    }
}
