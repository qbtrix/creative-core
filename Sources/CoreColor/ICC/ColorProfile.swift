// ColorProfile.swift: an ICC matrix-and-curve colour profile as a plain value
// (RGB or gray, from the ICC.1 specification), and the three built-in
// profiles. Colourants are in the PCS, XYZ relative to D50, already adapted
// (the `chad` step) so a transform needs no second adaptation. Reading is in
// ICCRead.swift, writing in ICCWrite.swift.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One channel's tone curve, encoded value to linear light, as ICC.1 stores it.
public enum ProfileCurve: Hashable, Sendable {
    /// `curv` with one entry: y = x^gamma.
    case gamma(Double)
    /// `curv` with n entries spread evenly over 0...1.
    case table([Double])
    /// `para` (ICC.1 10.18): function `type` 0 to 4, and `params` holding exactly that type's count
    /// of values, the first ones of g, a, b, c, d, e, f in that order (X encoded, Y linear):
    ///
    /// | type | params | Y |
    /// |------|--------|---|
    /// | 0 | 1: g | X^g |
    /// | 1 | 3: g, a, b | (aX + b)^g when X >= -b/a, else 0 |
    /// | 2 | 4: g, a, b, c | (aX + b)^g + c when X >= -b/a, else c |
    /// | 3 | 5: g, a, b, c, d | (aX + b)^g when X >= d, else cX |
    /// | 4 | 7: g, a, b, c, d, e, f | (aX + b)^g + e when X >= d, else cX + f |
    ///
    /// Any other type or count makes `ProfileTransform.init` and `iccData()` throw `.invalid`.
    case parametric(type: Int, params: [Double])
}

/// A matrix-and-curve ICC profile: RGB (three colourants, three curves) or
/// gray (the white point, one curve).
public struct ColorProfile: Hashable, Sendable {
    /// The profile description.
    public var name: String
    /// True for a gray profile: one `kTRC` curve and a white point instead of three colourants.
    public var isGray: Bool
    /// 3 x 3, row-major, linear RGB to XYZ D50; gray: the white point column. RGB colourants are
    /// adapted to D50 by linear Bradford from the profile's media white; `iccData()` assumes that
    /// white is D65 and writes `chad` accordingly.
    public var toXYZD50: [Double]
    /// 3 (RGB) or 1 (gray).
    public var curves: [ProfileCurve]

    /// Values are not checked here; `toXYZD50` must hold 9 (RGB) or 3 (gray) finite values and
    /// `curves` 3 or 1. `ProfileTransform.init` and `iccData()` throw `.invalid` when they do not.
    public init(name: String, isGray: Bool, toXYZD50: [Double], curves: [ProfileCurve]) {
        self.name = name
        self.isGray = isGray
        self.toXYZD50 = toXYZD50
        self.curves = curves
    }

    /// Reads ICC bytes. Matrix and curve only; LUT-based, CMYK and Lab
    /// profiles throw `.invalid` naming what they are.
    public init(iccData: Data) throws(ColorError) {
        self = try ICCRead.profile(iccData)
    }

    /// Writes a v4 profile: `mluc` description, D50 `wtpt`, `chad`, colourants and curves (gray: its
    /// white in `wtpt` and `kTRC`). For RGB it assumes `toXYZD50` was adapted from a D65 white and
    /// writes `chad` as the Bradford D65-to-D50 matrix. A value that does not fit its ICC field
    /// throws `.invalid`.
    public func iccData() throws(ColorError) -> Data {
        try ICCWrite.profile(self)
    }

    // The built-ins: values are on the ICC s15Fixed16 grid, so a written profile reads back ==; each is
    // within 2^-16 of IEC 61966-2-1 / the P3 primaries.

    /// IEC 61966-2-1 sRGB as ICC `para` function type 3, its parameters on the s15Fixed16 grid.
    static let sRGBCurve = ProfileCurve.parametric(
        type: 3, params: [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045].map(s15))

    /// IEC 61966-2-1 sRGB: its primaries and curve, D65 adapted to D50, on the s15Fixed16 grid.
    public static let sRGB = rgb("sRGB", Matrix3.xyzFromLinearSRGB, sRGBCurve)
    /// P3 primaries, D65 white, the sRGB curve, on the s15Fixed16 grid.
    public static let displayP3 = rgb("Display P3", Matrix3.xyzFromLinearSRGB * Matrix3.linearSRGBFromP3, sRGBCurve)
    /// sRGB primaries, linear light: the working space, on the s15Fixed16 grid.
    public static let linearSRGB = rgb("Linear sRGB", Matrix3.xyzFromLinearSRGB, .gamma(1))

    private static func rgb(_ name: String, _ xyzD65: Matrix3, _ curve: ProfileCurve) -> ColorProfile {
        let m = (Matrix3.bradfordD65ToD50 * xyzD65).m
        return ColorProfile(name: name, isGray: false, toXYZD50: [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8].map(s15),
                            curves: [curve, curve, curve])
    }

    /// Rounds to the nearest ICC s15Fixed16 value (1/65536 steps), as a written profile stores it.
    private static func s15(_ v: Double) -> Double { (v * 65536).rounded() / 65536 }
}

extension Matrix3 {
    /// The ICC.1 PCS illuminant, D50.
    static let d50White = Color3(0.9642, 1.0, 0.8249)

    /// The linear Bradford cone response matrix (ICC.1 Annex E).
    static let bradford = Matrix3(m: (
        0.8951, 0.2664, -0.1614,
        -0.7502, 1.7135, 0.0367,
        0.0389, -0.0685, 1.0296))

    /// Chromatic adaptation from D65 to the D50 PCS, the `chad` tag's matrix.
    static let bradfordD65ToD50: Matrix3 = {
        let src = bradford * d65White, dst = bradford * d50White
        let scale = Matrix3(m: (dst.c0 / src.c0, 0, 0, 0, dst.c1 / src.c1, 0, 0, 0, dst.c2 / src.c2))
        return bradford.inverse * scale * bradford
    }()
}
