// ProfileTransform.swift: a colour transform from one ColorProfile to another
// through the D50 PCS: decode by the source curves, the source matrix, the
// inverse of the target matrix, encode by the target's inverse curves. The
// body lands in CP-5; until then `init` throws
// `ColorError.invalid("not built: CP-5")`, so no transform exists to apply.

/// Maps colours encoded in one profile to the same colours in another.
public struct ProfileTransform: Sendable {
    public init(from: ColorProfile, to: ColorProfile) throws(ColorError) {
        throw ColorError.invalid("not built: CP-5")
    }

    /// Encoded in, encoded out; no clamp, so out-of-gamut values survive.
    public func apply(_ rgb: Color3) -> Color3 {
        rgb
    }

    /// Linear in and out: the matrix part only.
    public func applyLinear(_ rgb: Color3) -> Color3 {
        rgb
    }
}
