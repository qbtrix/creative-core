// ColorSpace.swift: Color3 and conversions between sRGB, linear sRGB, Display
// P3, CIE XYZ (D65) and OKLab. Every conversion goes through linear sRGB.
// Values outside 0...1 pass through unclamped (extended range); the transfer
// curve mirrors around zero so negative components survive a round trip.
// Sources: IEC 61966-2-1 (sRGB primaries and transfer curve), SMPTE EG 432-1
// (P3 primaries, with D65 and the sRGB curve as Display P3 uses them), and
// Björn Ottosson's published OKLab definition. RGB-to-XYZ matrices are derived
// from the primaries and the D65 white, so each inverse is exact to rounding.
#if canImport(FoundationEssentials)
import FoundationEssentials
// FoundationEssentials does not re-export the C math library (`pow`).
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
#else
import Foundation
#endif

/// The color spaces CoreColor converts between.
public enum ColorSpace: String, CaseIterable, Codable, Sendable, Hashable {
    /// Gamma-encoded sRGB (IEC 61966-2-1).
    case sRGB
    /// sRGB primaries, linear light.
    case linearSRGB
    /// Gamma-encoded Display P3: P3 primaries, D65 white, sRGB transfer curve.
    case displayP3
    /// CIE 1931 XYZ relative to D65, Y of white = 1.
    case xyzD65
    /// OKLab: L, a, b.
    case oklab
}

/// Three components of a color in some `ColorSpace` (r, g, b; X, Y, Z; or L, a, b).
public struct Color3: Codable, Sendable, Hashable {
    public var c0: Double
    public var c1: Double
    public var c2: Double

    public init(_ c0: Double, _ c1: Double, _ c2: Double) {
        self.c0 = c0
        self.c1 = c1
        self.c2 = c2
    }

    /// This color converted from `source` to `target`. Throws
    /// `ColorError.invalid` when a component is NaN or infinite, before or
    /// after conversion.
    public func converted(from source: ColorSpace, to target: ColorSpace) throws -> Color3 {
        try validated("input")
        guard source != target else { return self }
        let result = Self.fromLinearSRGB(Self.toLinearSRGB(self, from: source), to: target)
        try result.validated("result")
        return result
    }

    /// Each component clamped to 0...1.
    public func clampedToUnit() -> Color3 {
        map { min(max($0, 0), 1) }
    }

    private func validated(_ what: String) throws {
        guard c0.isFinite, c1.isFinite, c2.isFinite else {
            throw ColorError.invalid("color \(what) has a non-finite component: \(c0), \(c1), \(c2)")
        }
    }

    private func map(_ f: (Double) -> Double) -> Color3 {
        Color3(f(c0), f(c1), f(c2))
    }

    private static func toLinearSRGB(_ c: Color3, from space: ColorSpace) -> Color3 {
        switch space {
        case .sRGB: return c.map(TransferCurve.decode)
        case .linearSRGB: return c
        case .displayP3: return Matrix3.linearSRGBFromP3 * c.map(TransferCurve.decode)
        case .xyzD65: return Matrix3.linearSRGBFromXYZ * c
        case .oklab: return Matrix3.linearSRGBFromLMS * (Matrix3.lmsFromOKLab * c).map { $0 * $0 * $0 }
        }
    }

    private static func fromLinearSRGB(_ c: Color3, to space: ColorSpace) -> Color3 {
        switch space {
        case .sRGB: return c.map(TransferCurve.encode)
        case .linearSRGB: return c
        case .displayP3: return (Matrix3.p3FromLinearSRGB * c).map(TransferCurve.encode)
        case .xyzD65: return Matrix3.xyzFromLinearSRGB * c
        case .oklab: return Matrix3.oklabFromLMS * (Matrix3.lmsFromLinearSRGB * c).map(signedCubeRoot)
        }
    }

    private static func signedCubeRoot(_ x: Double) -> Double {
        x < 0 ? -pow(-x, 1.0 / 3.0) : pow(x, 1.0 / 3.0)
    }
}

/// The sRGB transfer curve (IEC 61966-2-1), shared by sRGB and Display P3.
/// Odd-extended so negative values map to the negated curve, and values over
/// 1 continue the curve. `decode` takes an encoded value to linear light,
/// `encode` the reverse.
public enum TransferCurve {
    public static func decode(_ v: Double) -> Double {
        let a = abs(v)
        let linear = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
        return v < 0 ? -linear : linear
    }

    public static func encode(_ v: Double) -> Double {
        let a = abs(v)
        let encoded = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1.0 / 2.4) - 0.055
        return v < 0 ? -encoded : encoded
    }
}

/// A row-major 3x3 matrix, enough for the linear steps between spaces.
struct Matrix3: Sendable {
    var m: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    static func * (a: Matrix3, c: Color3) -> Color3 {
        let m = a.m
        return Color3(
            m.0 * c.c0 + m.1 * c.c1 + m.2 * c.c2,
            m.3 * c.c0 + m.4 * c.c1 + m.5 * c.c2,
            m.6 * c.c0 + m.7 * c.c1 + m.8 * c.c2)
    }

    static func * (a: Matrix3, b: Matrix3) -> Matrix3 {
        let x = a.m, y = b.m
        return Matrix3(m: (
            x.0 * y.0 + x.1 * y.3 + x.2 * y.6, x.0 * y.1 + x.1 * y.4 + x.2 * y.7, x.0 * y.2 + x.1 * y.5 + x.2 * y.8,
            x.3 * y.0 + x.4 * y.3 + x.5 * y.6, x.3 * y.1 + x.4 * y.4 + x.5 * y.7, x.3 * y.2 + x.4 * y.5 + x.5 * y.8,
            x.6 * y.0 + x.7 * y.3 + x.8 * y.6, x.6 * y.1 + x.7 * y.4 + x.8 * y.7, x.6 * y.2 + x.7 * y.5 + x.8 * y.8))
    }

    /// The inverse by cofactors. Only called on the fixed, invertible matrices below.
    var inverse: Matrix3 {
        let (a, b, c, d, e, f, g, h, i) = m
        let A = e * i - f * h, B = f * g - d * i, C = d * h - e * g
        let det = a * A + b * B + c * C
        return Matrix3(m: (
            A / det, (c * h - b * i) / det, (b * f - c * e) / det,
            B / det, (a * i - c * g) / det, (c * d - a * f) / det,
            C / det, (b * g - a * h) / det, (a * e - b * d) / det))
    }

    /// The linear RGB-to-XYZ matrix for primaries (x, y) red, green, blue,
    /// scaled so RGB (1, 1, 1) maps to the D65 white.
    static func rgbToXYZ(_ r: (Double, Double), _ g: (Double, Double), _ b: (Double, Double)) -> Matrix3 {
        func xyz(_ p: (Double, Double)) -> (Double, Double, Double) { (p.0 / p.1, 1, (1 - p.0 - p.1) / p.1) }
        let (xr, yr, zr) = xyz(r), (xg, yg, zg) = xyz(g), (xb, yb, zb) = xyz(b)
        let s = Matrix3(m: (xr, xg, xb, yr, yg, yb, zr, zg, zb)).inverse * d65White
        return Matrix3(m: (
            xr * s.c0, xg * s.c1, xb * s.c2,
            yr * s.c0, yg * s.c1, yb * s.c2,
            zr * s.c0, zg * s.c1, zb * s.c2))
    }

    /// D65 white in XYZ, Y = 1 (the CIE tabulated illuminant).
    static let d65White = Color3(0.95047, 1.0, 1.08883)

    static let xyzFromLinearSRGB = rgbToXYZ((0.64, 0.33), (0.30, 0.60), (0.15, 0.06))
    static let linearSRGBFromXYZ = xyzFromLinearSRGB.inverse
    static let linearSRGBFromP3 = linearSRGBFromXYZ * rgbToXYZ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060))
    static let p3FromLinearSRGB = linearSRGBFromP3.inverse

    // OKLab, from Ottosson's definition: linear sRGB to LMS, then the
    // cube root, then LMS' to Lab. The inverses are computed, not copied.
    static let lmsFromLinearSRGB = Matrix3(m: (
        0.4122214708, 0.5363325363, 0.0514459929,
        0.2119034982, 0.6806995451, 0.1073969566,
        0.0883024619, 0.2817188376, 0.6299787005))
    static let linearSRGBFromLMS = lmsFromLinearSRGB.inverse
    static let oklabFromLMS = Matrix3(m: (
        0.2104542553, 0.7936177850, -0.0040720468,
        1.9779984951, -2.4285922050, 0.4505937099,
        0.0259040371, 0.7827717662, -0.8086757660))
    static let lmsFromOKLab = oklabFromLMS.inverse
}
