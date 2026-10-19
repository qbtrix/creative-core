// PathMeasure.swift: a ruler along a `Path`: its length, the point and unit
// tangent at a length, trim and dash.
//
// Invariants:
// - every measure flattens the path once at `tolerance` and walks the polyline
// - trimmed and dashed output is polyline pieces of the flattened path
// - a dash pattern with a negative, non-finite or zero-sum entry list, or
//   more than 64 entries, throws GeometryError.invalidPattern
//
// ponytail: stubs until PG-6; each throws GeometryError.notBuilt with its name.

extension Path {
    /// The length of the path flattened to `tolerance`.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance.
    public func length(tolerance: Double) throws -> Double {
        throw GeometryError.notBuilt("length(tolerance:)")
    }

    /// The point `s` along the path and the unit tangent there; nil when `s`
    /// is outside 0...length or the path is empty.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance.
    public func sample(atLength s: Double, tolerance: Double) throws -> (point: Point, tangent: Point)? {
        throw GeometryError.notBuilt("sample(atLength:tolerance:)")
    }

    /// The part of the path from `start` to `end` (fractions 0...1 of the
    /// length) shifted by `offset` (wraps), over the whole path or each contour
    /// as `mode` says. A start past the end after wrapping gives two pieces.
    ///
    /// Throws `GeometryError.invalidTolerance` for a bad tolerance and
    /// `GeometryError.nonFinite` for a non-finite start, end or offset.
    public func trimmed(start: Double, end: Double, offset: Double, mode: TrimMode,
                        tolerance: Double) throws -> Path {
        throw GeometryError.notBuilt("trimmed(start:end:offset:mode:tolerance:)")
    }

    /// The dashes of `pattern` (dash, gap, dash, ... lengths; an odd count
    /// repeats once) along each contour, starting `phase` into the pattern.
    ///
    /// Throws `GeometryError.invalidPattern` for a bad pattern and
    /// `GeometryError.invalidTolerance` for a bad tolerance.
    public func dashed(_ pattern: [Double], phase: Double, tolerance: Double) throws -> Path {
        throw GeometryError.notBuilt("dashed(_:phase:tolerance:)")
    }
}
