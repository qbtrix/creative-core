// ResampleTable.swift: one resample axis's taps as flat arrays the Metal resample kernel uploads (MB-8):
// CoreRaster's own `ResampleFilter.taps` (clamp-to-edge indices, zero weights dropped, weights normalised in
// Double), flattened and stored as Float; an unchanged length is the identity, as `resized` skips that pass.
// Also the largest float4 buffer a resample allocates, which the backend checks against its device limit.
// Invariants: `offsets` runs from 0 to `indices.count` in `newLength + 1` entries, every output has a tap,
// every index is in 0..<length, and every Int32 is in range. Linux-safe.
import CoreRaster

/// The taps of one axis resampled from `length` to `newLength` pixels: output `i` sums
/// `weights[k] * input[indices[k]]` for `k` in `offsets[i]..<offsets[i + 1]`.
public struct ResampleTable: Equatable, Sendable {
    /// The axis's input length in pixels (at least 1).
    public let length: Int
    /// The axis's output length in pixels (at least 1).
    public let newLength: Int
    /// Where each output's taps start in `indices` and `weights`: `newLength + 1` entries from 0 to `indices.count`.
    public let offsets: [Int32]
    /// The input pixel each tap reads, in 0..<length (clamped to the edge).
    public let indices: [Int32]
    /// Each tap's weight; one output's weights sum to 1 before they are rounded to Float.
    public let weights: [Float]

    /// The table for `filter` from `length` to `newLength`. Throws `RenderError.raster` for a length
    /// under 1, or when a length or the tap count does not fit an Int32.
    public init(length: Int, newLength: Int, filter: ResampleFilter) throws {
        let limit = Int(Int32.max)
        guard length >= 1, newLength >= 1, length <= limit, newLength <= limit else {
            throw RenderError.raster("resample table \(length) to \(newLength): lengths must be in 1...\(limit)")
        }
        let identity = length == newLength
        let rows = identity ? (0..<newLength).map { ([$0], [1.0]) } : filter.taps(length: length, newLength: newLength)
        var (offsets, indices, weights): ([Int32], [Int32], [Float]) = ([0], [], [])
        offsets.reserveCapacity(newLength + 1)
        for (taps, row) in rows {
            indices.append(contentsOf: taps.map { Int32(truncatingIfNeeded: $0) })
            weights.append(contentsOf: row.map { Float($0) })
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

    /// The most pixels any one buffer of a `width` x `height` to `newWidth` x `newHeight` resample holds:
    /// the input, the output, or the intermediate of the pass that runs first (the smaller one, as CoreRaster
    /// orders them), so never more than the larger of input and output. `Int.max` when a product overflows.
    public static func peakPixels(width: Int, height: Int, newWidth: Int, newHeight: Int) -> Int {
        let product = { (a: Int, b: Int) in a.multipliedReportingOverflow(by: b).overflow ? Int.max : a * b }
        let intermediate = min(product(newWidth, height), product(width, newHeight))
        return max(product(width, height), intermediate, product(newWidth, newHeight))
    }
}
