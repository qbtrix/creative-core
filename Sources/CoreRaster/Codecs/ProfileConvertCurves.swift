// ProfileConvertCurves.swift: the dense lookup tables that make a profile
// conversion's curve passes fast. A curve pass maps each channel on its own
// (both sides share primaries), so it is three 1-D functions, sampled here
// once per conversion instead of evaluated (pow per channel) per pixel. The
// nodes sit on the bits of a Double: `2^perOctaveBits` evenly spaced nodes in
// each octave from 2^-24 up to 2, so a power-law curve keeps a small relative
// error even near 0, and a value's node index and fraction are its exponent
// and top mantissa bits; 0 itself has its own exact entry. Values outside
// 0 and [2^-24, 2) (negative, tiny, far out of gamut, non-finite) have no
// entry: the caller takes the exact path for them, so nothing is clamped. A
// table whose linear interpolation misses the exact function by more than
// `tolerance` at any interval's midpoint is not built, and the conversion
// takes the exact path for every pixel.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor

struct CurveTables: Sendable {
    // The constants are computed, not stored, so they fold into the per-pixel loop instead of
    // going through a lazy global's initialization check on every lookup.
    /// Octaves covered, from 2^-24 up to 2.
    static var octaves: Int { 25 }
    /// log2 of the nodes per octave.
    static var perOctaveBits: Int { 8 }
    /// Mantissa bits below a node index.
    static var shift: UInt64 { 52 - UInt64(perOctaveBits) }
    static var low: Double { 0x1p-24 }
    static var high: Double { 2 }
    /// The node index of `low` in a Double's bits shifted right by `shift`.
    static var base: UInt64 { low.bitPattern >> shift }
    /// The weight of one mantissa step below a node index: 2^-shift.
    static var step: Double { 1 / Double(UInt64(1) << shift) }
    /// Nodes per channel, `high` included, so every covered value has a right neighbour.
    static var nodes: Int { octaves << perOctaveBits + 1 }
    /// Entries per channel: the nodes, then the exact value at 0.
    static var stride: Int { nodes + 1 }
    /// The largest interpolation error accepted at an interval midpoint, well inside the 1e-5 contract.
    static var tolerance: Double { 1e-6 }

    /// Channel k's node j at `k * stride + j`, its value at 0 at `k * stride + nodes`. Float halves the
    /// footprint, so the nodes a photo touches stay in the nearest cache; it costs ~6e-8 relative.
    let table: [Float]

    /// Samples `map`, which applies three per-channel functions, each to the same value. Nil when
    /// interpolating the samples misses `map` by more than `tolerance` anywhere, or a sample is not finite.
    init?(_ map: (Double) -> Color3) {
        let (n, w) = (Self.nodes, Self.stride)
        var v = [Float](repeating: 0, count: 3 * w)
        for j in 0...n {
            let y = map(j == n ? 0 : Self.node(j))
            (v[j], v[w + j], v[2 * w + j]) = (Float(y.c0), Float(y.c1), Float(y.c2))
        }
        guard v.allSatisfy(\.isFinite) else { return nil }
        for j in 0..<(n - 1) {
            let y = map((Self.node(j) + Self.node(j + 1)) / 2)
            func misses(_ k: Int, _ exact: Double) -> Bool {
                !(abs((Double(v[k * w + j]) + Double(v[k * w + j + 1])) / 2 - exact) <= Self.tolerance)
            }
            if misses(0, y.c0) || misses(1, y.c1) || misses(2, y.c2) { return nil }
        }
        table = v
    }

    /// The value at node `j`.
    private static func node(_ j: Int) -> Double {
        Double(bitPattern: (base + UInt64(j)) << shift)
    }

    /// True when `x` has a table entry: 0, or in [2^-24, 2) (so NaN does not).
    @inline(__always)
    static func covers(_ x: Double) -> Bool {
        (x >= low && x < high) || x == 0
    }

    /// The channel table starting at `offset` (0, `stride` or `2 * stride`) of `table` at an `x` that
    /// `covers` accepts: the exact entry for 0, else linear interpolation between the nodes around `x`.
    @inline(__always)
    static func lookup(_ t: UnsafeBufferPointer<Float>, _ offset: Int, _ x: Double) -> Double {
        guard x != 0 else { return Double(t[offset + nodes]) }
        let bits = x.bitPattern
        let i = offset + Int(truncatingIfNeeded: (bits >> shift) &- base)
        let fraction = Double(bits & ((1 << shift) - 1)) * step
        let (left, right) = (Double(t[i]), Double(t[i + 1]))
        return left + (right - left) * fraction
    }
}
