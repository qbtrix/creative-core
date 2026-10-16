// DisplayTransfer.swift: 8-bit display encoding and decoding of linear sRGB in
// sRGB or Display P3, by table. Decoding reads one of 256 values that
// `TransferCurve.decode` gives for byte / 255; encoding counts how many of 255
// thresholds a value reaches, where threshold k is the smallest Double whose
// encoded, clamped and rounded byte is at least k. Both spaces share the
// curve, so they share the tables; Display P3 adds the same `Matrix3` step, in
// the same order, as `Color3.converted`. The results are bit for bit those of
// `converted` plus the clamp-and-round byte rule, with no `pow` and no `throw`
// per value.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// 8-bit display encoding of linear sRGB in sRGB or Display P3, by table.
/// Bit for bit the same as `Color3.converted` followed by DisplayBytes'
/// clamp and round, without a `pow` or a `throw` per value.
public struct DisplayTransfer: Sendable, Hashable {
    /// `.sRGB` or `.displayP3`.
    public let space: ColorSpace

    /// Throws `ColorError.invalid` for a space other than `.sRGB` or `.displayP3`.
    public init(_ space: ColorSpace) throws {
        guard space == .sRGB || space == .displayP3 else {
            throw ColorError.invalid("color space \(space.rawValue): display transfer must be sRGB or displayP3")
        }
        self.space = space
    }

    /// Equals `try Color3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    /// .converted(from: space, to: .linearSRGB)`.
    public func decode(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color3 {
        let table = Self.decodeTable
        let c = Color3(table[Int(r)], table[Int(g)], table[Int(b)])
        return space == .displayP3 ? Matrix3.linearSRGBFromP3 * c : c
    }

    /// For a finite color: each component of
    /// `(try linear.converted(from: .linearSRGB, to: space)).clampedToUnit()`,
    /// times 255, rounded to nearest. NaN gives 0.
    public func encode(_ linear: Color3) -> (UInt8, UInt8, UInt8) {
        let p = space == .displayP3 ? Matrix3.p3FromLinearSRGB * linear : linear
        let least = Self.least
        return (Self.count(p.c0, least), Self.count(p.c1, least), Self.count(p.c2, least))
    }

    /// A value clamped to 0...1, times 255, rounded to nearest: the alpha
    /// rule. NaN gives 0.
    public static func byte(_ value: Double) -> UInt8 {
        guard value > 0 else { return 0 }
        guard value < 1 else { return 255 }
        return UInt8((value * 255).rounded())
    }

    /// `TransferCurve.decode(Double(b) / 255)` for every byte b.
    static let decodeTable: [Double] = (0...255).map { TransferCurve.decode(Double($0) / 255) }

    /// `least[k]`, k in 1...255: the smallest Double v with `step(v) >= k`.
    /// `least[0]` is 0 and never read by the search.
    static let least: [Double] = [0] + (1...255).map(threshold)

    /// Today's byte rule for one encoded component: curve, clamp, round.
    /// Non-decreasing in v.
    static func step(_ v: Double) -> UInt8 {
        byte(min(max(TransferCurve.encode(v), 0), 1))
    }

    /// The smallest non-negative Double v with `step(v) >= k`, by bisection
    /// on bit patterns: non-negative Doubles order as their bit patterns do,
    /// and `step(1) == 255`, so the answer lies in [0, 1].
    private static func threshold(_ k: Int) -> Double {
        var lo: UInt64 = 0
        var hi = (1.0 as Double).bitPattern
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if Int(step(Double(bitPattern: mid))) >= k { hi = mid } else { lo = mid + 1 }
        }
        return Double(bitPattern: lo)
    }

    /// How many of `least[1...255]` are at most v, by an 8-step branchless
    /// search over the sorted thresholds. NaN compares false everywhere: 0.
    @inline(__always)
    private static func count(_ v: Double, _ least: [Double]) -> UInt8 {
        var i = 0
        i += least[i + 128] <= v ? 128 : 0
        i += least[i + 64] <= v ? 64 : 0
        i += least[i + 32] <= v ? 32 : 0
        i += least[i + 16] <= v ? 16 : 0
        i += least[i + 8] <= v ? 8 : 0
        i += least[i + 4] <= v ? 4 : 0
        i += least[i + 2] <= v ? 2 : 0
        i += least[i + 1] <= v ? 1 : 0
        return UInt8(truncatingIfNeeded: i)
    }
}
