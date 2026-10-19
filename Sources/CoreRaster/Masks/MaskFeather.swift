// MaskFeather.swift: feathering a mask by a radius, a Gaussian of sigma =
// radius / 3. Up to sigma 2 it is that Gaussian (`gaussianKernel`); past it,
// four passes along each axis of the extended box of
// `PixelBuffer.extendedBox` (Gwosdek et al., SSVM 2011), whose variances sum
// to sigma² exactly, each pass a running sum, so a pixel costs the same at any
// radius. Each line is padded with its end samples first, so the edges
// repeat as `gaussianBlur`'s clamp-to-edge taps do. The boxes stay within
// 0.025 of the exact Gaussian (cut at 3 sigma); MaskFeatherBoxTests bounds it.
// Invariants: the radius is finite, at least 0 and within `gaussianBlur`'s
// limit, checked by its kernel builder; each output is a mean of inputs, so
// every value is a convex mix, kept in 0...1; a column filter runs along the
// column's length. Lines run 64 at a time as interleaved lanes, so their
// running sums are independent and a strip stays in cache through all passes.

extension Mask {
    /// This mask feathered: blurred by a Gaussian (past sigma 2, almost) of
    /// sigma `radius` / 3, so a hard edge fades over about `radius` pixels each
    /// side and reads 0.5 on the edge itself. Area is kept away from the mask's
    /// border; at the border the nearest pixel repeats, so a full mask stays
    /// full. Radius 0 returns this mask. Throws `RasterError.invalid` for a
    /// radius that is negative, not finite, or over twice the mask's larger side.
    public func feathered(radius: Double) throws -> Mask {
        guard radius.isFinite, radius >= 0 else {
            throw RasterError.invalid("feather radius \(radius): must be finite and at least 0")
        }
        let sigma = radius / 3
        // The exact blur's checks and its identity: a sigma too small to spread returns this mask.
        let kernel = try PixelBuffer.gaussianKernel(sigma: sigma, width: width, height: height)
        guard kernel.count > 1 else { return self }
        // Up to `exactSigma` the Gaussian itself (at most 13 taps); past it the boxes.
        let filter = FeatherFilter(kernel: sigma <= Self.exactSigma ? kernel : [],
                                   box: PixelBuffer.extendedBox(sigma: sigma, passes: Self.featherPasses))
        let across = Self.smooth(storage, width: width, height: height, alongRows: true, filter)
        return Mask(checkedWidth: width, height: height,
                    storage: Self.smooth(across, width: width, height: height, alongRows: false, filter))
    }

    /// The box passes a feather makes: four, so the boxes reach past 3 sigma.
    static let featherPasses = 4
    /// The largest sigma feathered by the Gaussian itself: boxes are too
    /// coarse below it, and its kernel is short there.
    static let exactSigma = 2.0

    /// Every row (or column) of the `w` x `h` image `src` through `filter`,
    /// its ends repeated `filter.reach` times, each value clamped to 0...1 (a
    /// NaN reads 0). Lines go `FeatherFilter.lanes` at a time, line l of a
    /// strip at position i in `a[i * lanes + l]`, spare lanes 0.
    private static func smooth(_ src: [Float], width w: Int, height h: Int, alongRows: Bool,
                               _ filter: FeatherFilter) -> [Float] {
        let lines = alongRows ? h : w, length = alongRows ? w : h, lanes = FeatherFilter.lanes
        let lineStep = alongRows ? w : 1, sampleStep = alongRows ? 1 : w, padded = length + 2 * filter.reach
        let a = UnsafeMutablePointer<Float>.allocate(capacity: padded * lanes)
        let b = UnsafeMutablePointer<Float>.allocate(capacity: padded * lanes)
        let sums = UnsafeMutablePointer<SIMD4<Double>>.allocate(capacity: lanes / 4)
        defer { a.deallocate(); b.deallocate(); sums.deallocate() }
        var out = [Float](repeating: 0, count: w * h)
        src.withUnsafeBufferPointer { s in
            out.withUnsafeMutableBufferPointer { o in
                guard let s = s.baseAddress, let o = o.baseAddress else { return }
                for k0 in stride(from: 0, to: lines, by: lanes) {
                    let count = min(lanes, lines - k0)
                    for i in 0..<padded {
                        let line = a + i * lanes, from = s + k0 * lineStep + min(max(i - filter.reach, 0), length - 1) * sampleStep
                        if alongRows {
                            for l in 0..<count { line[l] = from[l * w] }
                        } else {
                            line.update(from: from, count: count)
                        }
                        (line + count).update(repeating: 0, count: lanes - count)
                    }
                    let result = filter.run(a, b, sums, length: padded)
                    // Stores run along memory: a row's samples, or a column strip's row of lanes.
                    for (outer, inner) in alongRows ? [(count, length)] : [(length, count)] {
                        for j in 0..<outer {
                            for k in 0..<inner {
                                let (l, i) = alongRows ? (j, k) : (k, j)
                                let v = result[i * lanes + l]
                                o[(k0 + l) * lineStep + i * sampleStep] = v >= 1 ? 1 : v > 0 ? v : 0
                            }
                        }
                    }
                }
            }
        }
        return out
    }
}

/// The feather's 1-D filter: `kernel` when it is not empty, else
/// `Mask.featherPasses` passes of the extended `box`. It runs on `lanes`
/// interleaved lines of `length` samples (position p of lane l at p * lanes
/// + l), each output p from inputs p ... p + 2 `reach` / passes, so lines
/// padded by `reach` each side come out at their own length.
private struct FeatherFilter {
    let kernel: [Double], radius: Int, alpha: Double, reach: Int

    init(kernel: [Double], box: (radius: Int, alpha: Double)) {
        self.kernel = kernel
        radius = box.radius
        alpha = box.alpha
        reach = kernel.isEmpty ? Mask.featherPasses * (box.radius + 1) : kernel.count / 2
    }

    /// The lines a strip holds: 64, so a strip stays in cache through every pass.
    static let lanes = 64

    /// The filtered lines, in `a` or `b` (both hold `lanes` x `length`).
    func run(_ a: UnsafeMutablePointer<Float>, _ b: UnsafeMutablePointer<Float>, _ sums: UnsafeMutablePointer<SIMD4<Double>>,
             length: Int) -> UnsafeMutablePointer<Float> {
        let lanes = Self.lanes
        if !kernel.isEmpty {
            for p in 0..<(length - kernel.count + 1) {
                for l in 0..<lanes {
                    var sum = 0.0
                    for (j, k) in kernel.enumerated() { sum += k * Double(a[(p + j) * lanes + l]) }
                    b[p * lanes + l] = Float(sum)
                }
            }
            return b
        }
        // Each pass: the mean of 2 r + 3 inputs, the two ends weighted alpha;
        // one running sum per lane holds the inner 2 r + 1, so a sample costs
        // the same at any radius. Lanes go four at a time.
        let span = 2 * radius + 2, scale = 1 / (Double(span - 1) + 2 * alpha), row = lanes * 4
        var from = a, to = b, valid = length
        for _ in 0..<Mask.featherPasses {
            valid -= span
            let start = UnsafeRawPointer(from)
            for c in 0..<(lanes / 4) {
                sums[c] = .zero
                for p in 1..<span { sums[c] += Self.load(start, p * row + c * 16) }
            }
            var low = start, high = start + span * row, out = UnsafeMutableRawPointer(to)
            for _ in 0..<valid {
                for c in 0..<(lanes / 4) {
                    let end = Self.load(high, c * 16)
                    let mean = (sums[c] + alpha * (Self.load(low, c * 16) + end)) * scale
                    out.storeBytes(of: SIMD4<Float>(mean), toByteOffset: c * 16, as: SIMD4<Float>.self)
                    sums[c] += end - Self.load(low, row + c * 16)
                }
                low += row
                high += row
                out += row
            }
            swap(&from, &to)
        }
        return from
    }

    /// Four floats at `offset` bytes, widened.
    private static func load(_ p: UnsafeRawPointer, _ offset: Int) -> SIMD4<Double> {
        SIMD4<Double>(p.loadUnaligned(fromByteOffset: offset, as: SIMD4<Float>.self))
    }
}
