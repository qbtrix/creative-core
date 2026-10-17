// UnsharpRule.swift: the Metal unsharp kernel's per-component rule (MB-12) and its parameter checks. A
// premultiplied component whose difference from its blurred value is strictly over the threshold moves by
// `amount` times that difference. The kernel computes it in Float32 with Float(amount) and Float(threshold) and a
// fused multiply-add, and `apply` computes exactly that, so it is the kernel's Linux-side mirror. CoreRaster's
// `unsharpMask` computes the same rule in Double, so the two can differ by Float rounding, and a difference
// within Float rounding of the threshold can take the other branch. Invariants: a non-finite amount, then a
// negative or non-finite threshold, throws the CPU backend's exact error (BlurTable checks sigma after); a
// non-finite result throws CoreRaster's overflow error. Linux-safe.

/// The amount and threshold of one unsharp mask.
public struct UnsharpRule: Equatable, Sendable {
    /// How far a component moves, as a multiple of its difference from its blurred value; 0 leaves the image
    /// unchanged and a negative amount softens.
    public let amount: Double
    /// The largest absolute difference left alone: a premultiplied linear component on a 0...1 scale (not
    /// bytes) is sharpened only where it differs from its blurred value by strictly more than this.
    public let threshold: Double

    /// Throws CoreRaster's message as `RenderError.raster` for a non-finite amount, then a bad threshold.
    public init(amount: Double, threshold: Double) throws {
        guard amount.isFinite else { throw RenderError.raster("unsharp amount \(amount): must be finite") }
        guard threshold.isFinite, threshold >= 0 else { throw RenderError.raster("unsharp threshold \(threshold): must be finite and at least 0") }
        (self.amount, self.threshold) = (amount, threshold)
    }

    /// Amount and threshold as the kernel reads them (two Floats).
    public var parameters: [Float] { [Float(amount), Float(threshold)] }

    /// Component `x` sharpened against its blurred value `blurred` as the kernel's `sharpen` computes it: the
    /// difference in Float, compared strictly with Float(threshold), then x + Float(amount) * difference fused.
    public func apply(_ x: Float, blurred: Float) -> Float {
        let (gain, limit) = (Float(amount), Float(threshold))
        let difference = x - blurred
        guard difference > limit || difference < -limit else { return x }
        return x.addingProduct(gain, difference)
    }

    /// Throws CoreRaster's overflow error when any of `components` is not finite.
    public func check<C: Sequence<Float>>(_ components: C) throws {
        guard components.allSatisfy(\.isFinite) else { throw RenderError.raster("unsharp amount \(amount): a component overflowed") }
    }
}
