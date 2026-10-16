// DisplayTransfer.swift: 8-bit display encoding and decoding of linear sRGB in
// sRGB or Display P3, by table. Decoding reads one of 256 values that
// `TransferCurve.decode` gives for byte / 255. Encoding finds the byte from
// 255 thresholds, where threshold k is the smallest Double whose encoded,
// clamped and rounded byte is at least k: a value's bucket (the exponent and
// top 8 mantissa bits of its Double, which order non-negative Doubles) holds
// the byte at its first Double and at most one threshold, so the byte is
// that base plus one add-and-shift compare. Both spaces share the curve, so
// they share the tables; Display P3 adds the same matrix step, in the same
// order, as `Color3.converted`. The results are bit for bit those of
// `converted` plus the clamp-and-round byte rule, with no `pow`, `throw` or
// call per component and no branch per component beyond the one on the space:
// `decode`, `encode` and `byte` are inlinable and every `DisplayTransfer`
// carries the shared tables, so a pixel loop in another module reads them
// directly. Table reads go through a buffer pointer without a bounds check: a
// byte indexes the 256 decode entries, and `bucket` clamps first, so its index
// is always in range.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// 8-bit display encoding of linear sRGB in sRGB or Display P3, by table.
/// Bit for bit the same as `Color3.converted` followed by DisplayBytes'
/// clamp and round, without a `pow` or a `throw` per component.
public struct DisplayTransfer: Sendable, Hashable {
    /// `.sRGB` or `.displayP3`.
    public let space: ColorSpace

    @usableFromInline let isP3: Bool
    @usableFromInline let tables: Tables

    /// Throws `ColorError.invalid` for a space other than `.sRGB` or `.displayP3`.
    public init(_ space: ColorSpace) throws {
        guard space == .sRGB || space == .displayP3 else {
            throw ColorError.invalid("color space \(space.rawValue): display transfer must be sRGB or displayP3")
        }
        self.space = space
        isP3 = space == .displayP3
        tables = Self.shared
    }

    /// Equals `try Color3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    /// .converted(from: space, to: .linearSRGB)`.
    @inlinable @inline(__always)
    public func decode(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color3 {
        // 256 entries: every byte is in range.
        let (c0, c1, c2) = tables.decoded.withUnsafeBufferPointer { t in (t[Int(r)], t[Int(g)], t[Int(b)]) }
        guard isP3 else { return Color3(c0, c1, c2) }
        let p = Self.times(tables.linearSRGBFromP3, c0, c1, c2)
        return Color3(p.0, p.1, p.2)
    }

    /// For a finite color: each component of
    /// `(try linear.converted(from: .linearSRGB, to: space)).clampedToUnit()`,
    /// times 255, rounded to nearest. NaN gives 0. In sRGB, +infinity gives
    /// 255 and -infinity 0, as the clamp would; in Display P3 an infinite
    /// component can make the matrix give NaN, so its bytes are only
    /// guaranteed not to trap.
    @inlinable @inline(__always)
    public func encode(_ linear: Color3) -> (UInt8, UInt8, UInt8) {
        let p = isP3 ? Self.times(tables.p3FromLinearSRGB, linear.c0, linear.c1, linear.c2)
            : (linear.c0, linear.c1, linear.c2)
        return tables.buckets.withUnsafeBufferPointer { b in
            (Self.level(p.0, b), Self.level(p.1, b), Self.level(p.2, b))
        }
    }

    /// A value clamped to 0...1, times 255, rounded to nearest (half away
    /// from zero): the alpha rule. NaN gives 0.
    @inlinable @inline(__always)
    public static func byte(_ value: Double) -> UInt8 {
        // Without a branch or a call: scaled is in 0...255, so adding 2^52
        // rounds it to the nearest integer, ties to even, into the low bits;
        // a tie that went down (scaled - nearest is exactly 0.5) goes up.
        let scaled = (value > 0 ? (value < 1 ? value : 1) : 0) * 255
        let nearest = scaled + 0x1p52
        let tie: UInt8 = scaled - (nearest - 0x1p52) == 0.5 ? 1 : 0
        return UInt8(truncatingIfNeeded: nearest.bitPattern) &+ tie
    }

    /// Two transfers are equal when their spaces are: the tables are shared.
    public static func == (a: DisplayTransfer, b: DisplayTransfer) -> Bool { a.space == b.space }

    /// Hashes the space only, matching `==`.
    public func hash(into hasher: inout Hasher) { hasher.combine(space) }

    /// A row-major 3x3 matrix's entries.
    @usableFromInline typealias Entries = (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    /// The tables every `DisplayTransfer` carries, built once.
    @usableFromInline
    struct Tables: Sendable {
        /// `TransferCurve.decode(Double(b) / 255)` for every byte b.
        @usableFromInline let decoded: [Double]
        /// Per bucket, with first bit pattern s, byte `step` there = base,
        /// and its one threshold t bits past s (2^bucketShift when it holds
        /// none): (base << baseShift + 2^baseShift - t) &- s. See `level`.
        @usableFromInline let buckets: [UInt64]
        /// `Matrix3.linearSRGBFromP3` and `Matrix3.p3FromLinearSRGB`.
        @usableFromInline let linearSRGBFromP3: Entries
        @usableFromInline let p3FromLinearSRGB: Entries
    }

    static let shared = Tables(
        decoded: (0...255).map { TransferCurve.decode(Double($0) / 255) },
        buckets: (0..<bucketCount).map { b in
            let start = bucketStart(b)
            let t = thresholds(inBucket: b).first.map { $0.bitPattern - start.bitPattern } ?? 1 << bucketShift
            return (UInt64(step(start)) << baseShift + (1 << baseShift - t)) &- start.bitPattern
        },
        linearSRGBFromP3: Matrix3.linearSRGBFromP3.m,
        p3FromLinearSRGB: Matrix3.p3FromLinearSRGB.m)

    /// `Matrix3 * Color3`, the same products summed in the same order.
    @inlinable @inline(__always)
    static func times(_ m: Entries, _ c0: Double, _ c1: Double, _ c2: Double) -> (Double, Double, Double) {
        (m.0 * c0 + m.1 * c1 + m.2 * c2, m.3 * c0 + m.4 * c1 + m.5 * c2, m.6 * c0 + m.7 * c1 + m.8 * c2)
    }

    /// The low mantissa bits a bucket spans: 256 buckets per binade, each
    /// narrower than the gap between two thresholds (the tests check
    /// `thresholds(inBucket:)` for every bucket).
    @inlinable static var bucketShift: UInt64 { 52 - 8 }

    /// Where a bucket entry's base byte starts: just past the threshold field.
    @inlinable static var baseShift: UInt64 { bucketShift + 1 }

    /// The first bucket starts here, under `least[1]`: below it every value,
    /// NaN and negatives included, encodes to 0.
    @inlinable static var bucketFloor: Double { 0x1p-13 }

    /// Buckets from `bucketFloor` up to the one that starts at 1, which
    /// encodes 255.
    static var bucketCount: Int {
        Int((1.0 as Double).bitPattern >> bucketShift - bucketFloor.bitPattern >> bucketShift) + 1
    }

    /// The first Double of bucket b.
    static func bucketStart(_ b: Int) -> Double {
        Double(bitPattern: bucketFloor.bitPattern + UInt64(b) << bucketShift)
    }

    /// The thresholds strictly inside bucket b: past its first Double, before
    /// the next bucket's. `level` is exact when there is at most one.
    static func thresholds(inBucket b: Int) -> [Double] {
        let start = bucketStart(b), end = bucketStart(b + 1)
        return least.dropFirst().filter { $0 > start && $0 < end }
    }

    /// v clamped to `bucketFloor`...1, NaN to `bucketFloor`, as its bit pattern.
    @inlinable @inline(__always)
    static func clampedBits(_ v: Double) -> UInt64 {
        let low = v > bucketFloor ? v : bucketFloor
        return (low < 1 ? low : 1).bitPattern
    }

    /// The bucket of a `clampedBits` pattern, in 0..<bucketCount: the clamp
    /// keeps bits from `bucketFloor`'s to 1's, the first and last bucket starts.
    @inlinable @inline(__always)
    static func bucket(_ bits: UInt64) -> Int {
        Int(truncatingIfNeeded: bits >> bucketShift &- bucketFloor.bitPattern >> bucketShift)
    }

    /// `step(v)`, from `buckets` (the `Tables.buckets` entries). With bits
    /// v's clamped bit pattern and e its bucket's entry, bits - s and t are at
    /// most 2^bucketShift, so e &+ bits = base << baseShift + 2^baseShift +
    /// (bits - s) - t carries into the base exactly when bits - s >= t, that
    /// is when v reaches the threshold.
    @inlinable @inline(__always)
    static func level(_ v: Double, _ buckets: UnsafeBufferPointer<UInt64>) -> UInt8 {
        let bits = clampedBits(v)
        return UInt8(truncatingIfNeeded: (buckets[bucket(bits)] &+ bits) >> baseShift)
    }

    /// `least[k]`, k in 1...255: the smallest Double v with `step(v) >= k`.
    /// `least[0]` is 0 and never read.
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
}
