// PathOutline.swift: a stroke turned into the closed path that fills the
// same area.
//
// Invariants:
// - the result is closed and its filled area is the stroked area
// - a miter longer than `miterLimit` times half the width falls back to a bevel
// - a width that is zero, negative or not finite throws GeometryError.nonFinite
//
// ponytail: stub until PG-8; it throws GeometryError.notBuilt with its name.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Path {
    /// The outline of this path stroked at `width` with `join`, `cap` (open
    /// contours only) and `miterLimit`, curves and round parts flattened to
    /// `tolerance`, as one fillable path (nonzero).
    ///
    /// Throws `GeometryError.nonFinite` for a bad width or miter limit and
    /// `GeometryError.invalidTolerance` for a bad tolerance.
    public func outlined(width: Double, join: Stroke.Join, cap: Stroke.Cap, miterLimit: Double,
                         tolerance: Double) throws -> Path {
        throw GeometryError.notBuilt("outlined(width:join:cap:miterLimit:tolerance:)")
    }
}
