// DenoiseClarity.swift: edge-preserving denoise and mid-tone clarity.
// Denoise is a joint bilateral filter guided by the original linear luma
// (Rec. 709, straight colour): spatial sigma 1 + 4 strength px, range sigma
// (1 - detail) x 0.2 luma. It runs separably (one pass along x, then one along
// y, the usual fast approximation), on luma at the spatial sigma and on chroma
// (colour minus luma) at twice it, so colour noise goes first. Colour is
// averaged premultiplied and divided by the alpha averaged through the same
// weights, so transparent pixels lend no colour; alpha itself is kept.
// Clarity is an unsharp mask on straight colour against a Gaussian of kernel
// radius `radius` (sigma radius / 3, capped so the kernel fits the buffer's
// clamped edge), its gain amount / 100 scaled by a mid-tone weight (1 for
// luma 0.2...0.8, falling linearly to 0 at 0 and 1) so the ends don't clip;
// a negative amount blends toward the blurred copy. Alpha is kept.
// Invariants: strength and detail are finite and in 0...1, amount in
// -100...100, radius in 0...1,000; zero strength, amount or radius is identity.
// Denoise's scratch is about 17.5 times the buffer (280 bytes a pixel), so it
// takes at most `maxDenoisePixels` (an eighth of `maxPixels`, room for a 24 MP
// photo); a larger buffer throws, naming the cap and the remedy (tiles or a
// downscale); a result past Float's range throws instead of storing inf.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif
import Dispatch

extension PixelBuffer {
    /// The most pixels `denoised` takes: its Double planes and bilateral
    /// passes need about 280 bytes a pixel (17.5 times the buffer's 16), a
    /// bounded multiple, so an eighth of `maxPixels` (32 Mi px, room for a
    /// 24 MP photo, about 9.4 GB of scratch at the cap) instead of 75 GB at
    /// full size. Denoise a larger buffer in tiles, or downscale it.
    public static let maxDenoisePixels = maxPixels / 8

    /// This buffer denoised by a bilateral filter: `strength` (0...1) widens
    /// the smoothing, `detail` (0...1) narrows the luma difference it smooths
    /// across, so edges stay. Strength 0 returns the buffer unchanged. Throws
    /// `RasterError.invalid` for a parameter that is not finite or not in 0...1,
    /// a buffer over `maxDenoisePixels`, or a result that overflows (source
    /// components too large).
    public func denoised(strength: Double, detail: Double) throws -> PixelBuffer {
        for (value, name) in [(strength, "strength"), (detail, "detail")] where !(value.isFinite && (0...1).contains(value)) {
            throw RasterError.invalid("denoise \(name) \(value): must be finite and in 0...1")
        }
        guard strength > 0 else { return self }
        guard width * height <= Self.maxDenoisePixels else {
            throw RasterError.invalid("denoise size \(width)x\(height): more than maxDenoisePixels (\(Self.maxDenoisePixels)) pixels; denoise it in tiles or downscale it")
        }
        let src = components, c = Self.channels, n = width * height, w = Histogram.luminanceWeights
        // Per pixel, lumaAlpha is (luma, alpha, 0, 0), chromaAlpha (r, g, b minus luma, alpha).
        var lumaAlpha = [SIMD4<Double>](repeating: .zero, count: n), chromaAlpha = lumaAlpha
        var guide = [Double](repeating: 0, count: n)
        for p in 0..<n {
            let i = p * c, a = Double(src[i + 3])
            let y = Double(w.r * src[i] + w.g * src[i + 1] + w.b * src[i + 2])
            lumaAlpha[p] = SIMD4(y, a, 0, 0)
            chromaAlpha[p] = SIMD4(Double(src[i]) - y, Double(src[i + 1]) - y, Double(src[i + 2]) - y, a)
            guide[p] = a > 0 ? y / a : 0
        }
        let sigma = 1 + 4 * strength, rangeSigma = (1 - detail) * 0.2
        let near = bilateral(lumaAlpha, guide: guide, sigma: sigma, rangeSigma: rangeSigma)
        let far = bilateral(chromaAlpha, guide: guide, sigma: 2 * sigma, rangeSigma: rangeSigma)
        var out = src
        for p in 0..<n where src[p * c + 3] > 0 {
            let y = near[p][1] > 0 ? near[p][0] / near[p][1] : 0
            for k in 0..<3 {
                let shade = far[p][3] > 0 ? far[p][k] / far[p][3] : 0
                out[p * c + k] = Float(max(0, (y + shade) * Double(src[p * c + 3])))
            }
        }
        guard out.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("denoise: result overflows Float; source pixel components are too large")
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// This buffer with its local contrast raised (positive `amount`) or
    /// lowered (negative), -100...100, against a blur of `radius` px
    /// (0...1,000; 30 is typical). The radius cap is inclusive: 1,000 is
    /// accepted and anything past it throws `RasterError.invalid`. Below the
    /// cap, a radius past twice the buffer's larger side less one blurs as
    /// that (the kernel fits the clamped edge), so it does not throw. Amount
    /// or radius 0 returns the buffer unchanged. Throws `RasterError.invalid`
    /// for a parameter that is not finite or out of range, or a result that
    /// overflows (source components too large).
    public func clarity(amount: Double, radius: Double) throws -> PixelBuffer {
        guard amount.isFinite, (-100...100).contains(amount) else {
            throw RasterError.invalid("clarity amount \(amount): must be finite and in -100...100")
        }
        guard radius.isFinite, (0...1_000).contains(radius) else {
            throw RasterError.invalid("clarity radius \(radius): must be finite and in 0...1000")
        }
        guard amount != 0, radius > 0 else { return self }
        // ceil(3 sigma) stays within gaussianBlur's limit of twice the larger side.
        let blurred = try gaussianBlur(sigma: min(radius, Double(2 * max(width, height) - 1)) / 3).components
        let src = components, c = Self.channels, k = amount / 100, w = Histogram.luminanceWeights
        var out = src
        for i in stride(from: 0, to: src.count, by: c) {
            let a = Double(src[i + 3]), blurA = Double(blurred[i + 3])
            guard a > 0, blurA > 0 else { continue }
            let luma = Double(w.r * src[i] + w.g * src[i + 1] + w.b * src[i + 2]) / a
            let gain = k * Self.midToneWeight(luma)
            for ch in 0..<3 {
                let x = Double(src[i + ch]) / a, b = Double(blurred[i + ch]) / blurA
                out[i + ch] = Float(max(0, a * (x + gain * (x - b))))
            }
        }
        guard out.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("clarity: result overflows Float; source pixel components are too large")
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// Clarity's weight for a pixel of straight linear `luma`: 1 over
    /// 0.2...0.8, linear to 0 at 0 and at 1, 0 beyond.
    private static func midToneWeight(_ luma: Double) -> Double {
        min(1, max(0, min(luma, 1 - luma) / 0.2))
    }

    /// `pixels` (`width` x `height`, row-major, up to four values a pixel)
    /// smoothed by a separable joint bilateral filter:
    /// each tap weighs exp(-d^2 / (2 sigma^2)) by distance and
    /// exp(-g^2 / (2 rangeSigma^2)) by the `guide` difference g (only equal
    /// guides when rangeSigma is 0; see `RangeWeight`). Taps past the edge
    /// read the edge pixel.
    private func bilateral(_ pixels: [SIMD4<Double>], guide: [Double], sigma: Double, rangeSigma: Double) -> [SIMD4<Double>] {
        let r = Int((3 * sigma).rounded(.up))
        let spatial = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let range = RangeWeight(sigma: rangeSigma)
        /// One 1-D pass along the `lines` rows of `length` pixels of `input`,
        /// guided by `g`. Rows run in parallel bands; each band writes only
        /// its own rows.
        func pass(_ input: [SIMD4<Double>], _ g: [Double], lines: Int, length: Int) -> [SIMD4<Double>] {
            var output = input
            let bands = min(lines, 64)
            output.withUnsafeMutableBufferPointer { buffer in
                let target = BandTarget(buffer: buffer)
                DispatchQueue.concurrentPerform(iterations: bands) { band in
                    var weights = spatial
                    input.withUnsafeBufferPointer { source in
                        g.withUnsafeBufferPointer { guides in
                            weights.withUnsafeMutableBufferPointer { scratch in
                                for line in stride(from: band, to: lines, by: bands) {
                                    Self.filterRow(source, guides, into: target.buffer, base: line * length, length: length,
                                                   spatial: spatial, range: range, weights: scratch)
                                }
                            }
                        }
                    }
                }
            }
            return output
        }
        /// `values` (`rows` rows of `columns`) transposed, so the column pass
        /// also reads along memory.
        func transposed<T>(_ values: [T], columns: Int, rows: Int) -> [T] {
            (0..<values.count).map { values[($0 % rows) * columns + $0 / rows] }
        }
        let along = pass(pixels, guide, lines: height, length: width)
        let down = pass(transposed(along, columns: width, rows: height), transposed(guide, columns: width, rows: height),
                        lines: width, length: height)
        return transposed(down, columns: height, rows: width)
    }

    /// One row of a bilateral pass: the `length` pixels from `base` of
    /// `input`, each the weighted mean of its `spatial.count` taps (clamped
    /// to the row), written to `out`. `weights` is scratch of `spatial.count`.
    /// Every index stays in `base..<base + length`, inside all three buffers.
    private static func filterRow(_ input: UnsafeBufferPointer<SIMD4<Double>>, _ guide: UnsafeBufferPointer<Double>,
                                  into out: UnsafeMutableBufferPointer<SIMD4<Double>>, base: Int, length: Int,
                                  spatial: [Double], range: RangeWeight, weights: UnsafeMutableBufferPointer<Double>) {
        let r = spatial.count / 2, last = base + length - 1
        for i in 0..<length {
            let centre = guide[base + i]
            // Weights first, then one tight multiply-add loop.
            for t in 0..<weights.count {
                weights[t] = spatial[t] * range.weight(guide[min(max(base + i + t - r, base), last)] - centre)
            }
            var total = 0.0, sum = SIMD4<Double>.zero
            for t in 0..<weights.count {
                total += weights[t]
                sum += weights[t] * input[min(max(base + i + t - r, base), last)]
            }
            // The centre tap has weight 1 for a finite guide; a NaN guide
            // leaves total 0 and a NaN the caller rejects.
            out[base + i] = sum / total
        }
    }
}

/// The bilateral range weight exp(-g^2 / (2 sigma^2)) of a guide difference
/// g, read from a table of exp(-t^2 / 2) at steps of 1/1,024 in t = g / sigma
/// and 0 from t = 6 on (exp(-18) < 2e-8), so no tap calls `exp`. A NaN or
/// huge difference weighs 0; sigma 0 weighs only equal guides.
private struct RangeWeight: Sendable {
    static let steps = 1_024.0, limit = 6 * steps
    static let table = (0...Int(limit)).map { exp(-0.5 * (Double($0) / steps) * (Double($0) / steps)) }
    let sigma: Double, scale: Double, table = Self.table

    init(sigma: Double) {
        self.sigma = sigma
        scale = sigma > 0 ? Self.steps / sigma : 0
    }

    func weight(_ d: Double) -> Double {
        guard sigma > 0 else { return d == 0 ? 1 : 0 }
        let t = abs(d) * scale
        return t < Self.limit ? table[Int(t + 0.5)] : 0
    }
}

/// The output of one bilateral pass, shared by its parallel bands. Sound
/// because each band writes a disjoint set of whole lines and the pass waits
/// for every band before the buffer is read or freed.
private struct BandTarget: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<SIMD4<Double>>
}
