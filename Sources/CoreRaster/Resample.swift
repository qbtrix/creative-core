// Resample.swift: resizing a PixelBuffer with a separable filter, and the 1-D
// convolution pass (`convolved`) that resizing and blurring share. Each axis is
// one 1-D pass over premultiplied components. A sample outside the buffer
// reads the nearest edge pixel (clamp-to-edge, `Taps.add`). Each output's weights are
// normalized to sum to 1, so a constant image stays constant. When
// downscaling, the filter is widened by the scale factor so every input pixel
// counts. Weights are summed in Double. Invariant: the output size passed
// `PixelBuffer.validatedSize` and every output component is finite.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The reconstruction filter `PixelBuffer.resized` uses.
public enum ResampleFilter: Hashable, Sendable {
    /// Tent filter, radius 1. Smooth with no overshoot.
    case bilinear
    /// Windowed sinc, radius 3. Sharper, but can overshoot near hard edges.
    case lanczos3

    var radius: Double {
        switch self {
        case .bilinear: 1
        case .lanczos3: 3
        }
    }

    func weight(_ x: Double) -> Double {
        let d = abs(x)
        guard d < radius else { return 0 }
        switch self {
        case .bilinear:
            return 1 - d
        case .lanczos3:
            guard d > 1e-9 else { return 1 }
            let px = Double.pi * d
            return 3 * sin(px) * sin(px / 3) / (px * px)
        }
    }
}

/// The input pixels one output pixel reads along one axis, with their
/// normalized weights.
struct Taps {
    var indices: [Int] = []
    var weights: [Double] = []

    /// Adds input pixel `j` with weight `w`, clamping `j` to the nearest edge
    /// of a line of `length` pixels.
    mutating func add(_ j: Int, weight w: Double, length: Int) {
        indices.append(min(max(j, 0), length - 1))
        weights.append(w)
    }
}

extension PixelBuffer {
    /// This image resampled to `width x height` with `filter`. Throws
    /// `RasterError.invalid` for a size `validatedSize` rejects, or when
    /// lanczos3's overshoot on extreme values would leave a component that is
    /// not finite.
    public func resized(width newWidth: Int, height newHeight: Int, filter: ResampleFilter) throws -> PixelBuffer {
        _ = try Self.validatedSize(width: newWidth, height: newHeight)
        let c = Self.channels
        let horizontal = (along: c, across: width * c)
        var data = components
        // Run the pass that leaves the smaller intermediate first. Its size is
        // at most max(input, output) pixels, so it never exceeds `maxPixels`.
        if newWidth * height <= width * newHeight {
            data = Self.pass(data, lines: height, length: width, newLength: newWidth,
                             src: horizontal, dst: (c, newWidth * c), filter: filter)
            data = Self.pass(data, lines: newWidth, length: height, newLength: newHeight,
                             src: (newWidth * c, c), dst: (newWidth * c, c), filter: filter)
        } else {
            data = Self.pass(data, lines: width, length: height, newLength: newHeight,
                             src: (width * c, c), dst: (width * c, c), filter: filter)
            data = Self.pass(data, lines: newHeight, length: width, newLength: newWidth,
                             src: horizontal, dst: (c, newWidth * c), filter: filter)
        }
        guard data.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("resize to \(newWidth)x\(newHeight): a component overflowed")
        }
        return PixelBuffer(checkedWidth: newWidth, height: newHeight, storage: data)
    }

    /// One 1-D pass: resamples `lines` lines of `length` pixels to `newLength`.
    /// `src` and `dst` give the storage step between neighbouring pixels along
    /// a line and between neighbouring lines.
    private static func pass(
        _ input: [Float], lines: Int, length: Int, newLength: Int,
        src: (along: Int, across: Int), dst: (along: Int, across: Int), filter: ResampleFilter
    ) -> [Float] {
        if length == newLength { return input }
        let taps = taps(length: length, newLength: newLength, filter: filter)
        return convolved(input, lines: lines, newLength: newLength, src: src, dst: dst) { taps[$0] }
    }

    /// One 1-D convolution pass over `lines` lines: output pixel `i` of each
    /// line is the weighted sum of the input pixels `tap(i)` names, summed in
    /// Double. `tap` is called once per output pixel, not once per line.
    /// `src` and `dst` are the storage steps, as in `pass`.
    static func convolved(
        _ input: [Float], lines: Int, newLength: Int,
        src: (along: Int, across: Int), dst: (along: Int, across: Int), tap: (Int) -> Taps
    ) -> [Float] {
        var output = [Float](repeating: 0, count: lines * newLength * channels)
        var sum = [Double](repeating: 0, count: channels)
        for i in 0..<newLength {
            let tap = tap(i)
            for line in 0..<lines {
                for k in 0..<channels { sum[k] = 0 }
                for (j, w) in zip(tap.indices, tap.weights) {
                    let base = line * src.across + j * src.along
                    for k in 0..<channels { sum[k] += w * Double(input[base + k]) }
                }
                let base = line * dst.across + i * dst.along
                for k in 0..<channels { output[base + k] = Float(sum[k]) }
            }
        }
        return output
    }

    /// The taps of every output pixel along an axis of `length` pixels.
    private static func taps(length: Int, newLength: Int, filter: ResampleFilter) -> [Taps] {
        let scale = Double(length) / Double(newLength)
        let stretch = max(scale, 1)
        let support = filter.radius * stretch
        return (0..<newLength).map { i in
            let center = (Double(i) + 0.5) * scale - 0.5
            let first = Int((center - support).rounded(.up))
            let last = Int((center + support).rounded(.down))
            var tap = Taps()
            for j in first...max(first, last) {
                let w = filter.weight((Double(j) - center) / stretch)
                guard w != 0 else { continue }
                tap.add(j, weight: w, length: length)
            }
            let total = tap.weights.reduce(0, +)
            guard total != 0 else {
                // Unreachable for these filters; read the nearest pixel anyway.
                return Taps(indices: [min(max(Int(center.rounded()), 0), length - 1)], weights: [1])
            }
            tap.weights = tap.weights.map { $0 / total }
            return tap
        }
    }
}
