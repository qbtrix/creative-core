// ProfileTransform.swift: a colour transform from one ColorProfile to another
// through the D50 PCS (ICC.1): decode by the source curves, the source
// colourants to XYZ, linear Bradford adaptation from the source white to the
// target white when they differ (each white is where RGB (1, 1, 1) or gray 1
// lands), the inverse of the target colourants, then the target's inverse
// curves. Tables invert by binary search and linear interpolation, and
// continue their last segment past 1. Every curve is odd-extended about zero,
// as CoreColor's TransferCurve is, so out-of-gamut values pass through
// unclamped. Gray profiles read the first component and write r == g == b.
// A profile that cannot be inverted (singular colourants, a falling table, a
// zero gamma) throws ColorError.
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

/// Maps colours encoded in one profile to the same colours in another.
public struct ProfileTransform: Sendable {
    private let decode: [Tone]
    private let encode: [Tone]
    private let matrix: Matrix3

    public init(from source: ColorProfile, to target: ColorProfile) throws(ColorError) {
        let (toPCS, sourceWhite) = try Self.toPCS(source)
        let (fromPCS, targetWhite) = try Self.fromPCS(target)
        let m = fromPCS * (try Self.adaptation(from: sourceWhite, to: targetWhite)) * toPCS
        let e = m.m
        guard [e.0, e.1, e.2, e.3, e.4, e.5, e.6, e.7, e.8].allSatisfy(\.isFinite) else {
            throw ColorError.invalid("profile transform \(source.name) to \(target.name) overflows")
        }
        matrix = m
        decode = try Self.tones(source)
        encode = try Self.tones(target)
    }

    /// Encoded in, encoded out; no clamp, so out-of-gamut values survive.
    public func apply(_ rgb: Color3) -> Color3 {
        let linear = applyLinear(Color3(decode[0].linear(rgb.c0), decode[1].linear(rgb.c1), decode[2].linear(rgb.c2)))
        return Color3(encode[0].encoded(linear.c0), encode[1].encoded(linear.c1), encode[2].encoded(linear.c2))
    }

    /// Linear in and out: the matrix part only.
    public func applyLinear(_ rgb: Color3) -> Color3 {
        matrix * rgb
    }

    /// Linear RGB (or gray in the first component) to XYZ D50, and the white it maps 1 to.
    private static func toPCS(_ profile: ColorProfile) throws(ColorError) -> (Matrix3, Color3) {
        let v = try values(profile)
        if profile.isGray { return (Matrix3(m: (v[0], 0, 0, v[1], 0, 0, v[2], 0, 0)), Color3(v[0], v[1], v[2])) }
        let m = Matrix3(m: (v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]))
        return (m, m * Color3(1, 1, 1))
    }

    /// XYZ D50 to linear RGB (gray: Y over the white's Y, three times), and the profile's white.
    private static func fromPCS(_ profile: ColorProfile) throws(ColorError) -> (Matrix3, Color3) {
        let v = try values(profile)
        if profile.isGray { return (Matrix3(m: (0, 1 / v[1], 0, 0, 1 / v[1], 0, 0, 1 / v[1], 0)), Color3(v[0], v[1], v[2])) }
        let (m, white) = try toPCS(profile)
        let det = m.determinant
        guard det.isFinite, abs(det) > 1e-12 else {
            throw ColorError.invalid("profile \(profile.name) has singular colourants (determinant \(det))")
        }
        return (m.inverse, white)
    }

    /// The profile's `toXYZD50`, checked: 9 finite values (RGB), or 3 with Y > 0 (gray).
    private static func values(_ profile: ColorProfile) throws(ColorError) -> [Double] {
        let v = profile.toXYZD50, want = profile.isGray ? 3 : 9
        guard v.count == want, v.allSatisfy(\.isFinite) else {
            throw ColorError.invalid("profile \(profile.name) needs \(want) finite XYZ values, has \(v)")
        }
        guard !profile.isGray || v[1] > 0 else {
            throw ColorError.invalid("gray profile \(profile.name) has a white with Y \(v[1])")
        }
        return v
    }

    /// Linear Bradford adaptation (ICC.1 Annex E) taking `source` white to `target` white.
    private static func adaptation(from source: Color3, to target: Color3) throws(ColorError) -> Matrix3 {
        let identity = Matrix3(m: (1, 0, 0, 0, 1, 0, 0, 0, 1))
        guard source != target else { return identity }
        let s = Matrix3.bradford * source, d = Matrix3.bradford * target
        guard [s.c0, s.c1, s.c2].allSatisfy({ abs($0) > 1e-12 }) else {
            throw ColorError.invalid("white \(source.c0), \(source.c1), \(source.c2) has a zero cone response")
        }
        let scale = Matrix3(m: (d.c0 / s.c0, 0, 0, 0, d.c1 / s.c1, 0, 0, 0, d.c2 / s.c2))
        return Matrix3.bradford.inverse * scale * Matrix3.bradford
    }

    /// Three channel tones: one per RGB curve, or the gray curve three times.
    private static func tones(_ profile: ColorProfile) throws(ColorError) -> [Tone] {
        let want = profile.isGray ? 1 : 3
        guard profile.curves.count == want else {
            throw ColorError.invalid("profile \(profile.name) needs \(want) curves, has \(profile.curves.count)")
        }
        var tones: [Tone] = []
        for curve in profile.curves { tones.append(try Tone(curve)) }
        return profile.isGray ? [tones[0], tones[0], tones[0]] : tones
    }
}

/// One validated, invertible tone curve, odd-extended about zero.
private enum Tone: Sendable {
    /// ICC.1 `para` in its type-4 form: (a x + b)^g + e for x >= d, else c x + f.
    case segments(g: Double, a: Double, b: Double, c: Double, d: Double, e: Double, f: Double)
    /// At least two entries, finite, non-decreasing, rising overall.
    case table([Double])

    init(_ curve: ProfileCurve) throws(ColorError) {
        switch curve {
        case .gamma(let g):
            self = .segments(g: g, a: 1, b: 0, c: 0, d: 0, e: 0, f: 0)
        case .table(let t):
            guard t.count >= 2, t.allSatisfy(\.isFinite), zip(t, t.dropFirst()).allSatisfy({ $0 <= $1 }),
                  let first = t.first, let last = t.last, last > first else {
                throw ColorError.invalid("a curve table must hold 2 or more finite, rising entries")
            }
            self = .table(t)
        case .parametric(let type, let p):
            let counts = [1, 3, 4, 5, 7]
            guard (0..<counts.count).contains(type), p.count == counts[type], p.allSatisfy(\.isFinite) else {
                throw ColorError.invalid("parametric curve type \(type) with \(p.count) parameters is not valid")
            }
            let g = p[0], a = p.count > 1 ? p[1] : 1, b = p.count > 2 ? p[2] : 0
            guard a > 0 else { throw ColorError.invalid("parametric curve slope a \(a) is not positive") }
            switch type {
            case 0: self = .segments(g: g, a: 1, b: 0, c: 0, d: 0, e: 0, f: 0)
            case 1: self = .segments(g: g, a: a, b: b, c: 0, d: -b / a, e: 0, f: 0)
            case 2: self = .segments(g: g, a: a, b: b, c: 0, d: -b / a, e: p[3], f: p[3])
            case 3: self = .segments(g: g, a: a, b: b, c: p[3], d: p[4], e: 0, f: 0)
            default: self = .segments(g: g, a: a, b: b, c: p[3], d: p[4], e: p[5], f: p[6])
            }
        }
        if case .segments(let g, _, _, let c, _, _, _) = self, !(g > 0) || c < 0 {
            throw ColorError.invalid("curve gamma \(g) or linear slope \(c) cannot be inverted")
        }
    }

    /// Encoded value to linear light.
    func linear(_ x: Double) -> Double {
        let v = abs(x), y: Double
        switch self {
        case let .segments(g, a, b, c, d, e, f):
            y = v >= d ? pow(max(a * v + b, 0), g) + e : c * v + f
        case .table(let t):
            let n = t.count - 1
            if v < 1 {
                let p = v * Double(n), i = min(Int(p), n - 1)
                y = t[i] + (p - Double(i)) * (t[i + 1] - t[i])
            } else {
                y = t[n] + (v - 1) * Double(n) * (t[n] - t[n - 1])
            }
        }
        return x < 0 ? -y : y
    }

    /// Linear light to encoded value, the inverse of `linear`.
    func encoded(_ y: Double) -> Double {
        let v = abs(y), x: Double
        switch self {
        case let .segments(g, a, b, c, d, e, f):
            let knee = pow(max(a * d + b, 0), g) + e
            if v >= knee { x = (pow(max(v - e, 0), 1 / g) - b) / a } else { x = c > 0 ? (v - f) / c : d }
        case .table(let t):
            x = Self.invert(t, v)
        }
        return y < 0 ? -x : x
    }

    /// Where a non-decreasing table reaches `y`: binary search, then linear
    /// interpolation; past the last entry its last segment continues.
    private static func invert(_ t: [Double], _ y: Double) -> Double {
        let n = t.count - 1, last = t[n], rise = (t[n] - t[n - 1]) * Double(n)
        if y >= last { return rise > 0 ? 1 + (y - last) / rise : 1 }
        if y <= t[0] { return 0 }
        var lo = 0, hi = n
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if t[mid] <= y { lo = mid } else { hi = mid }
        }
        return (Double(lo) + (y - t[lo]) / (t[hi] - t[lo])) / Double(n)
    }
}

extension Matrix3 {
    fileprivate var determinant: Double {
        let (a, b, c, d, e, f, g, h, i) = m
        return a * (e * i - f * h) + b * (f * g - d * i) + c * (d * h - e * g)
    }
}
