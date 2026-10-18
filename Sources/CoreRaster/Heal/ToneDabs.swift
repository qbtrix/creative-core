// ToneDabs.swift: dodge, burn and sponge, the per-dab tone ops (retouch-heal
// RH-5). A dab is a mask placed with its top-left corner at (x, y); only
// pixels under it change, and alpha never does. TonalRange is real; the three
// dab ops are stubs RH-0 declares and RH-5 fills in without changing them.

/// The band of luma a dodge or burn dab acts on.
public enum TonalRange: Hashable, Sendable {
    case shadows, midtones, highlights
}

extension PixelBuffer {
    /// Lightens the pixels under `dab` (its top-left at `x`, `y`) in `range`,
    /// weighted by the dab's coverage. `exposure` is in 0...1; 0 changes
    /// nothing. Throws `RasterError.invalid` for an exposure outside 0...1 or
    /// NaN.
    public mutating func dodge(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        throw RasterError.invalid("dodge is not built yet (retouch-heal RH-5)")
    }

    /// Darkens the pixels under `dab` (its top-left at `x`, `y`) in `range`,
    /// weighted by the dab's coverage. `exposure` is in 0...1; 0 changes
    /// nothing. Throws `RasterError.invalid` for an exposure outside 0...1 or
    /// NaN.
    public mutating func burn(_ dab: Mask, x: Int, y: Int, range: TonalRange, exposure: Float) throws {
        throw RasterError.invalid("burn is not built yet (retouch-heal RH-5)")
    }

    /// Raises (`amount` above 0) or lowers (`amount` below 0) the saturation
    /// of the pixels under `dab` (its top-left at `x`, `y`), weighted by the
    /// dab's coverage. `amount` is in -1...1; 0 changes nothing. Throws
    /// `RasterError.invalid` for an amount outside -1...1 or NaN.
    public mutating func sponge(_ dab: Mask, x: Int, y: Int, amount: Float) throws {
        throw RasterError.invalid("sponge is not built yet (retouch-heal RH-5)")
    }
}
