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
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// This buffer denoised by a bilateral filter: `strength` (0...1) widens
    /// the smoothing, `detail` (0...1) narrows the luma difference it smooths
    /// across, so edges stay. Strength 0 returns the buffer unchanged. Throws
    /// `RasterError.invalid` for a parameter that is not finite or not in 0...1.
    public func denoised(strength: Double, detail: Double) throws -> PixelBuffer {
        for (value, name) in [(strength, "strength"), (detail, "detail")] where !(value.isFinite && (0...1).contains(value)) {
            throw RasterError.invalid("denoise \(name) \(value): must be finite and in 0...1")
        }
        guard strength > 0 else { return self }
        let src = components, c = Self.channels, n = width * height, w = Histogram.luminanceWeights
        var luma = [Double](repeating: 0, count: n), alpha = luma, guide = luma
        var chroma = [[Double]](repeating: luma, count: 3)
        for p in 0..<n {
            let i = p * c, a = Double(src[i + 3])
            let y = Double(w.r * src[i] + w.g * src[i + 1] + w.b * src[i + 2])
            luma[p] = y; alpha[p] = a
            for k in 0..<3 { chroma[k][p] = Double(src[i + k]) - y }
            guide[p] = a > 0 ? y / a : 0
        }
        let sigma = 1 + 4 * strength, rangeSigma = (1 - detail) * 0.2
        let near = bilateral([luma, alpha], guide: guide, sigma: sigma, rangeSigma: rangeSigma)
        let far = bilateral(chroma + [alpha], guide: guide, sigma: 2 * sigma, rangeSigma: rangeSigma)
        var out = src
        for p in 0..<n where src[p * c + 3] > 0 {
            let y = near[1][p] > 0 ? near[0][p] / near[1][p] : 0
            for k in 0..<3 {
                let shade = far[3][p] > 0 ? far[k][p] / far[3][p] : 0
                out[p * c + k] = Float(max(0, (y + shade) * alpha[p]))
            }
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// This buffer with its local contrast raised (positive `amount`) or
    /// lowered (negative), -100...100, against a blur of `radius` px
    /// (0...1,000; 30 is typical). Amount or radius 0 returns the buffer
    /// unchanged. Throws `RasterError.invalid` for a parameter that is not
    /// finite or out of range.
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
        return PixelBuffer(checkedWidth: width, height: height, storage: out)
    }

    /// Clarity's weight for a pixel of straight linear `luma`: 1 over
    /// 0.2...0.8, linear to 0 at 0 and at 1, 0 beyond.
    private static func midToneWeight(_ luma: Double) -> Double {
        min(1, max(0, min(luma, 1 - luma) / 0.2))
    }

    /// `planes` (each `width` x `height`, row-major, the last the alpha that
    /// normalises the rest) smoothed by a separable joint bilateral filter:
    /// each tap weighs exp(-d^2 / (2 sigma^2)) by distance and
    /// exp(-g^2 / (2 rangeSigma^2)) by the `guide` difference g (only equal
    /// guides when rangeSigma is 0). Taps past the edge read the edge pixel.
    private func bilateral(_ planes: [[Double]], guide: [Double], sigma: Double, rangeSigma: Double) -> [[Double]] {
        let r = Int((3 * sigma).rounded(.up))
        let spatial = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        /// The range weight of a guide difference `d`.
        func closeness(_ d: Double) -> Double {
            guard rangeSigma > 0 else { return d == 0 ? 1 : 0 }
            return exp(-d * d / (2 * rangeSigma * rangeSigma))
        }
        /// One 1-D pass: `lines` lines of `length` pixels, `along` and
        /// `across` the index steps within a line and between lines.
        func pass(_ input: [[Double]], lines: Int, length: Int, along: Int, across: Int) -> [[Double]] {
            var output = input
            var sums = [Double](repeating: 0, count: input.count)
            for line in 0..<lines {
                for i in 0..<length {
                    let p = line * across + i * along
                    var total = 0.0
                    for k in sums.indices { sums[k] = 0 }
                    for (t, s) in spatial.enumerated() {
                        let q = line * across + min(max(i + t - r, 0), length - 1) * along
                        let weight = s * closeness(guide[q] - guide[p])
                        total += weight
                        for k in input.indices { sums[k] += weight * input[k][q] }
                    }
                    // The centre tap has weight 1, so total is at least 1.
                    for k in input.indices { output[k][p] = sums[k] / total }
                }
            }
            return output
        }
        let rows = pass(planes, lines: height, length: width, along: 1, across: width)
        return pass(rows, lines: width, length: height, along: width, across: 1)
    }
}
