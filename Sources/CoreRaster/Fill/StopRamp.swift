// StopRamp.swift: the stop ramp that the raster gradient (fill-tools) and the
// gradient map (tone-pack) share: one stop limit, one set of offset checks
// and one segment lookup, so both read stops the same way. Each caller checks
// and mixes its own colours, in its own space.
extension PixelBuffer {
    /// The most stops `gradient(...)` and `gradientMap(_:)` take; both need
    /// at least 2.
    public static let maxGradientStops = 64
}

/// Checked stop offsets: 2...`PixelBuffer.maxGradientStops` of them, each in
/// 0...1, sorted. Two equal offsets make a hard edge.
struct StopRamp: Sendable {
    let offsets: [Double]

    /// Checks `offsets`; each error starts with `what` and names the stop by
    /// its index.
    /// - Throws: `RasterError.invalid` for a bad count, an offset outside
    ///   0...1 (or NaN), or an offset below the one before it.
    init(_ offsets: [Float], what: String) throws {
        let counts = 2...PixelBuffer.maxGradientStops
        guard counts.contains(offsets.count) else {
            throw RasterError.invalid("\(what) with \(offsets.count) stops: needs \(counts)")
        }
        for (i, o) in offsets.enumerated() {
            guard (0...1).contains(o) else {
                throw RasterError.invalid("\(what) stop \(i) offset \(o): must be in 0...1")
            }
            if i > 0, o < offsets[i - 1] {
                throw RasterError.invalid("\(what) stop \(i) offset \(o): below stop \(i - 1) offset "
                    + "\(offsets[i - 1]), stops must be sorted by offset")
            }
        }
        self.offsets = offsets.map(Double.init)
    }

    /// The colour at `t` is stop `lo` mixed toward stop `lo + 1` by `f` in
    /// 0...1. Below the first stop (or NaN) that stop holds, `(0, 0)`; at or
    /// past the last, the last holds, `(count - 2, 1)`. At a hard edge, `t`
    /// exactly on the shared offset takes the later stop.
    func segment(at t: Double) -> (lo: Int, f: Double) {
        let last = offsets.count - 1
        guard t >= offsets[0] else { return (0, 0) }
        guard t < offsets[last] else { return (last - 1, 1) }
        var hi = 1
        while offsets[hi] <= t { hi += 1 }  // stops by `last`, whose offset is above t
        let lo = hi - 1
        return (lo, (t - offsets[lo]) / (offsets[hi] - offsets[lo]))
    }
}
