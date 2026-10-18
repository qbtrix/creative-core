// ColorProfile.swift: an ICC matrix-and-curve colour profile as a plain value
// (RGB or gray, from the ICC.1 specification), and the three built-in
// profiles. Colourants are in the PCS, XYZ relative to D50, already adapted
// (the `chad` step) so a transform needs no second adaptation. Reading is in
// ICCRead.swift; writing lands in ICCWrite.swift (CP-4) and until then throws
// `ColorError.invalid("not built: CP-4")`.
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
    /// `para`, function type 0 to 4 with its parameters (g, a, b, c, d, e, f).
    case parametric(type: Int, params: [Double])
}

/// A matrix-and-curve ICC profile: RGB (three colourants, three curves) or
/// gray (the white point, one curve).
public struct ColorProfile: Hashable, Sendable {
    /// The profile description.
    public var name: String
    public var isGray: Bool
    /// 3 x 3, row-major, linear RGB to XYZ D50; gray: the white point column.
    public var toXYZD50: [Double]
    /// 3 (RGB) or 1 (gray).
    public var curves: [ProfileCurve]

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

    /// Writes a v4 profile: `mluc` description, D50 `wtpt`, `chad`, colourants and curves.
    public func iccData() throws(ColorError) -> Data {
        throw ColorError.invalid("not built: CP-4")
    }

    /// IEC 61966-2-1 sRGB as ICC `para` function type 3.
    static let sRGBCurve = ProfileCurve.parametric(
        type: 3, params: [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045])

    public static let sRGB = rgb("sRGB", Matrix3.xyzFromLinearSRGB, sRGBCurve)
    /// P3 primaries, D65 white, the sRGB curve.
    public static let displayP3 = rgb("Display P3", Matrix3.xyzFromLinearSRGB * Matrix3.linearSRGBFromP3, sRGBCurve)
    /// sRGB primaries, linear light: the working space.
    public static let linearSRGB = rgb("Linear sRGB", Matrix3.xyzFromLinearSRGB, .gamma(1))

    private static func rgb(_ name: String, _ xyzD65: Matrix3, _ curve: ProfileCurve) -> ColorProfile {
        let m = (Matrix3.bradfordD65ToD50 * xyzD65).m
        return ColorProfile(name: name, isGray: false, toXYZD50: [m.0, m.1, m.2, m.3, m.4, m.5, m.6, m.7, m.8],
                            curves: [curve, curve, curve])
    }
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
