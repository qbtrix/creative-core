// Blur.swift: Gaussian blur and unsharp mask on a PixelBuffer. The blur is
// separable: one horizontal 1-D pass, then one vertical, both through
// `convolved` (Resample.swift) with clamp-to-edge taps, on premultiplied
// components. One kernel builder (`gaussianKernel`) and one tap builder
// (`taps`) serve both functions and `Mask.feathered`.
// Invariants: sigma is finite and at least 0, and the kernel radius ceil(3
// sigma) is at most twice the buffer's larger side; the kernel sums to 1, so
// every blurred component is a convex mix of input components and stays finite.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension PixelBuffer {
    /// This image blurred by a Gaussian of standard deviation `sigma` pixels,
    /// kernel radius ceil(3 sigma). Sigma 0 returns the image unchanged. Throws
    /// `RasterError.invalid` for a negative or non-finite sigma, or one whose
    /// radius is over twice the larger side.
    public func gaussianBlur(sigma: Double) throws -> PixelBuffer {
        let kernel = try Self.gaussianKernel(sigma: sigma, width: width, height: height)
        guard kernel.count > 1 else { return self }
        let c = Self.channels
        var data = Self.convolved(components, lines: height, newLength: width,
                                  src: (c, width * c), dst: (c, width * c), tap: Self.taps(kernel, length: width))
        data = Self.convolved(data, lines: width, newLength: height,
                              src: (width * c, c), dst: (width * c, c), tap: Self.taps(kernel, length: height))
        return PixelBuffer(checkedWidth: width, height: height, storage: data)
    }

    /// This image sharpened: each component moves away from its blurred value
    /// by `amount` times their difference, where that difference is over
    /// `threshold`; smaller differences are left as they are. Amount 0 returns
    /// the image unchanged. Works on premultiplied components, alpha included.
    /// Throws `RasterError.invalid` for an invalid sigma (see `gaussianBlur`),
    /// a non-finite amount, a negative or non-finite threshold, or a result
    /// component that overflows.
    public func unsharpMask(amount: Double, sigma: Double, threshold: Double) throws -> PixelBuffer {
        guard amount.isFinite else {
            throw RasterError.invalid("unsharp amount \(amount): must be finite")
        }
        guard threshold.isFinite, threshold >= 0 else {
            throw RasterError.invalid("unsharp threshold \(threshold): must be finite and at least 0")
        }
        let blurred = try gaussianBlur(sigma: sigma).components
        let data = zip(components, blurred).map { x, b -> Float in
            let difference = Double(x) - Double(b)
            guard abs(difference) > threshold else { return x }
            return Float(Double(x) + amount * difference)
        }
        guard data.allSatisfy(\.isFinite) else {
            throw RasterError.invalid("unsharp amount \(amount): a component overflowed")
        }
        return PixelBuffer(checkedWidth: width, height: height, storage: data)
    }

    /// The clamp-to-edge taps of `kernel` (odd length, centred) for each
    /// output pixel of a line of `length` pixels.
    static func taps(_ kernel: [Double], length: Int) -> (Int) -> Taps {
        let r = kernel.count / 2
        return { i in
            var tap = Taps()
            for (k, w) in kernel.enumerated() { tap.add(i + k - r, weight: w, length: length) }
            return tap
        }
    }

    /// The normalized 1-D Gaussian of `sigma`, 2 ceil(3 sigma) + 1 weights
    /// centered on the middle one, for a `width` x `height` image (its radius
    /// limit). Sigma 0, or one so small that 2 sigma² is 0 or subnormal (its
    /// side weights would round to 0 or be NaN), gives the single weight 1.
    /// Masks feather with it too.
    static func gaussianKernel(sigma: Double, width: Int, height: Int) throws -> [Double] {
        guard sigma.isFinite, sigma >= 0 else {
            throw RasterError.invalid("blur sigma \(sigma): must be finite and at least 0")
        }
        let radius = (3 * sigma).rounded(.up)
        let limit = 2 * max(width, height)
        guard radius <= Double(limit) else {
            throw RasterError.invalid("blur sigma \(sigma): radius \(radius) is over \(limit)")
        }
        let denominator = 2 * sigma * sigma
        guard denominator.isNormal else { return [1] }
        let r = Int(radius)
        let weights = (-r...r).map { x in exp(-Double(x) * Double(x) / denominator) }
        let total = weights.reduce(0, +)
        return weights.map { $0 / total }
    }
}
