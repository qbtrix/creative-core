// PerceptualHash.swift: a 64-bit DCT perceptual hash of a PixelBuffer, for
// finding near-duplicate pictures. The buffer is resampled to 32 x 32
// (`resized` with the bilinear filter, which widens to cover every input
// pixel when shrinking, so it averages areas), each pixel's Rec. 709 luminance
// (`Histogram.luminanceWeights`, on premultiplied values, so over black) is
// sRGB-encoded with CoreColor's `TransferCurve`, and a 2-D DCT-II is taken.
// The 8 x 8 lowest frequencies after the DC row and column (u, v in 1...8)
// give one bit each: set when the coefficient is above their median. The DC
// term carries only overall brightness, so dropping it keeps the hash steady
// under exposure; the median sets half the bits, so different pictures land
// far apart. Bit i is coefficient (u, v) = (1 + i % 8, 1 + i / 8). `distance`
// is the Hamming distance, the popcount of the XOR. Same buffer, same bits,
// on every platform: sums run in Double in a fixed order.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import CoreColor

/// A 64-bit perceptual hash: near copies of a picture (resized, re-encoded,
/// slightly re-toned) hash a few bits apart, different pictures far apart.
public struct PerceptualHash: Hashable, Codable, Sendable {
    public let bits: UInt64

    /// A hash with these bits, as stored or decoded.
    public init(bits: UInt64) {
        self.bits = bits
    }

    /// The hash of `buffer`. Throws `RasterError.invalid` when resampling it
    /// to the hash's working size fails.
    public init(of buffer: PixelBuffer) throws {
        let side = 32
        let window = 1...8
        let small = try buffer.resized(width: side, height: side, filter: .bilinear)
        let w = Histogram.luminanceWeights
        var luma = [Double](repeating: 0, count: side * side)
        let c = small.components
        for i in 0..<luma.count {
            let p = i * PixelBuffer.channels
            luma[i] = TransferCurve.encode(Double(w.r * c[p] + w.g * c[p + 1] + w.b * c[p + 2]))
        }
        // basis[k][n] = cos(pi * (2n + 1) * k / 2N), the DCT-II basis.
        let basis = (0...window.upperBound).map { k in
            (0..<side).map { n in cos(Double.pi * Double(2 * n + 1) * Double(k) / Double(2 * side)) }
        }
        // Rows first: rows[y][u] = sum over x of luma[y][x] * basis[u][x].
        let rows = (0..<side).map { y in
            window.map { u in (0..<side).reduce(0.0) { $0 + luma[y * side + $1] * basis[u][$1] } }
        }
        var coefficients: [Double] = []
        for v in window {
            for column in 0..<window.count {
                coefficients.append((0..<side).reduce(0.0) { $0 + rows[$1][column] * basis[v][$1] })
            }
        }
        let sorted = coefficients.sorted()
        let middle = sorted.count / 2
        guard middle >= 1, coefficients.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("perceptual hash: \(coefficients.count) coefficients, or one is not finite")
        }
        let threshold = (sorted[middle - 1] + sorted[middle]) / 2
        var bits: UInt64 = 0
        for (i, value) in coefficients.enumerated() where value > threshold {
            bits |= 1 << UInt64(i)
        }
        self.bits = bits
    }

    /// The number of bits that differ: 0 for the same picture, about 32 for
    /// unrelated ones.
    public func distance(to other: PerceptualHash) -> Int {
        (bits ^ other.bits).nonzeroBitCount
    }
}
