// ResampleTable.swift: one resample axis's taps as flat arrays the Metal resample kernel uploads (MB-8),
// built as CoreRaster's `resized` builds them (its taps are internal): clamp-to-edge indices, zero weights
// dropped, weights normalised in Double and stored as Float; an unchanged length is the identity. Invariants:
// `offsets` runs from 0 to `indices.count` in `newLength + 1` entries, every output has a tap, every index is
// in 0..<length, and every Int32 is in range. Linux-safe.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreRaster

/// The taps of one axis resampled from `length` to `newLength` pixels: output `i` sums
/// `weights[k] * input[indices[k]]` for `k` in `offsets[i]..<offsets[i + 1]`.
public struct ResampleTable: Equatable, Sendable {
    public let length: Int, newLength: Int
    public let offsets: [Int32], indices: [Int32], weights: [Float]

    /// The table for `filter` from `length` to `newLength`. Throws `RenderError.raster` for a length
    /// under 1, or when a length or the tap count does not fit an Int32.
    public init(length: Int, newLength: Int, filter: ResampleFilter) throws {
        let limit = Int(Int32.max)
        guard length >= 1, newLength >= 1, length <= limit, newLength <= limit else {
            throw RenderError.raster("resample table \(length) to \(newLength): lengths must be in 1...\(limit)")
        }
        var (offsets, indices, weights): ([Int32], [Int32], [Float]) = ([0], [], [])
        offsets.reserveCapacity(newLength + 1)
        for i in 0..<newLength {
            let (taps, row) = length == newLength ? ([i], [1.0]) : Self.taps(i, length, newLength, filter)
            let total = row.reduce(0, +)
            indices.append(contentsOf: taps.map { Int32(truncatingIfNeeded: $0) })
            weights.append(contentsOf: row.map { Float($0 / total) })
            guard indices.count <= limit else {
                throw RenderError.raster("resample table \(length) to \(newLength): over \(limit) taps")
            }
            offsets.append(Int32(truncatingIfNeeded: indices.count))
        }
        (self.length, self.newLength, self.offsets, self.indices, self.weights) = (length, newLength, offsets, indices, weights)
    }

    /// True when the axis keeps its length: every output reads its own pixel with weight 1.
    public var isIdentity: Bool { length == newLength }

    /// A line of `length` values through the table, summed in Float as the kernel sums; empty for a wrong length.
    public func apply(_ line: [Float]) -> [Float] {
        guard line.count == length else { return [] }
        return (0..<newLength).map { i in
            (Int(offsets[i])..<Int(offsets[i + 1])).reduce(Float(0)) { $0 + weights[$1] * line[Int(indices[$1])] }
        }
    }

    /// Output `i`'s clamped input pixels and raw non-zero weights; a zero total (unreachable for these
    /// filters, whose centre tap weighs over 0) falls back to the nearest pixel, as CoreRaster does.
    private static func taps(_ i: Int, _ length: Int, _ newLength: Int, _ filter: ResampleFilter) -> ([Int], [Double]) {
        let (scale, radius) = (Double(length) / Double(newLength), filter == .bilinear ? 1.0 : 3.0)
        let stretch = max(scale, 1), center = (Double(i) + 0.5) * scale - 0.5
        let low = Int((center - radius * stretch).rounded(.up))
        var (taps, row): ([Int], [Double]) = ([], [])
        for j in low...max(low, Int((center + radius * stretch).rounded(.down))) {
            let d = abs(Double(j) - center) / stretch, t = Double.pi * d
            let w = d >= radius ? 0 : filter == .bilinear ? 1 - d : d <= 1e-9 ? 1 : radius * sin(t) * sin(t / radius) / (t * t)
            if w != 0 { taps.append(min(max(j, 0), length - 1)); row.append(w) }
        }
        return row.reduce(0, +) == 0 ? ([min(max(Int(center.rounded()), 0), length - 1)], [1]) : (taps, row)
    }
}
