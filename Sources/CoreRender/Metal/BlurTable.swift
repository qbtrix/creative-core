// BlurTable.swift: the 1-D Gaussian the Metal blur kernel uploads (MB-11), built as CoreRaster's `gaussianBlur`
// builds its kernel (`gaussianKernel` is private): 2 ceil(3 sigma) + 1 weights exp(-x^2 / 2 sigma^2) normalised
// in Double and stored as Float, sigma 0 the single weight 1. BlurTableTests pins every weight to CoreRaster's
// blur of an impulse, so the copy cannot drift from CoreRaster's kernel unnoticed. Invariants: sigma is finite and at least 0 and the
// radius is at most twice the image's larger side, else it throws the CPU backend's exact error (CoreRaster's
// message as `RenderError.raster`); the weights are symmetric and sum to 1; `apply` clamps taps to the edge.
// Linux-safe.
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The Gaussian of `sigma` for a `width` x `height` image: output `i` of a line sums
/// `weights[k] * line[clamp(i + k - radius)]` for every `k`.
public struct BlurTable: Equatable, Sendable {
    /// The Gaussian's standard deviation in pixels, as `gaussianBlur(sigma:)` takes it; 0 is the identity.
    public let sigma: Double
    /// The 2 ceil(3 sigma) + 1 normalised weights, centre in the middle: one tap per pixel offset from `-radius`.
    public let weights: [Float]

    /// Throws `RenderError.raster` with CoreRaster's message for a negative or non-finite sigma, or one whose
    /// radius ceil(3 sigma) is over twice the larger of `width` and `height`.
    public init(sigma: Double, width: Int, height: Int) throws {
        guard sigma.isFinite, sigma >= 0 else {
            throw RenderError.raster("blur sigma \(sigma): must be finite and at least 0")
        }
        let radius = (3 * sigma).rounded(.up)
        let limit = 2 * max(width, height)
        guard radius <= Double(limit) else {
            throw RenderError.raster("blur sigma \(sigma): radius \(radius) is over \(limit)")
        }
        let r = Int(radius)
        let raw = (-r...r).map { x in sigma == 0 ? 1 : exp(-Double(x) * Double(x) / (2 * sigma * sigma)) }
        let total = raw.reduce(0, +)
        (self.sigma, self.weights) = (sigma, raw.map { Float($0 / total) })
    }

    /// The taps either side of the centre.
    public var radius: Int { weights.count / 2 }

    /// True for sigma 0 (one weight): the CPU returns the image unchanged.
    public var isIdentity: Bool { weights.count == 1 }

    /// A line through the kernel with clamp-to-edge taps, summed in Float as the kernel sums; empty for an empty line.
    public func apply(_ line: [Float]) -> [Float] {
        let last = line.count - 1
        return line.indices.map { i in
            weights.indices.reduce(Float(0)) { sum, k in sum + weights[k] * line[min(max(i + k - radius, 0), last)] }
        }
    }
}
