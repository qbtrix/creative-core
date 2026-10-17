// UnsharpRule.swift: CoreRaster's unsharp-mask rule (MB-12), which the Metal unsharp kernel runs per premultiplied
// component: a difference from the blur strictly over the threshold moves the component by `amount` times it.
// Invariants: a non-finite amount, then a negative or non-finite threshold, throws the CPU backend's exact error
// (BlurTable checks sigma after); a non-finite result throws CoreRaster's overflow error. Linux-safe.

/// The amount and threshold of one unsharp mask.
public struct UnsharpRule: Equatable, Sendable {
    public let amount: Double, threshold: Double

    /// Throws CoreRaster's message as `RenderError.raster` for a non-finite amount, then a bad threshold.
    public init(amount: Double, threshold: Double) throws {
        guard amount.isFinite else { throw RenderError.raster("unsharp amount \(amount): must be finite") }
        guard threshold.isFinite, threshold >= 0 else { throw RenderError.raster("unsharp threshold \(threshold): must be finite and at least 0") }
        (self.amount, self.threshold) = (amount, threshold)
    }

    /// Amount and threshold as the kernel reads them (two Floats).
    public var parameters: [Float] { [Float(amount), Float(threshold)] }

    /// Component `x` sharpened against its blurred value `blurred`, in Double as CoreRaster computes it.
    public func apply(_ x: Float, blurred: Float) -> Float {
        let difference = Double(x) - Double(blurred)
        guard abs(difference) > threshold else { return x }
        return Float(Double(x) + amount * difference)
    }

    /// Throws CoreRaster's overflow error when any of `components` is not finite.
    public func check<C: Sequence<Float>>(_ components: C) throws {
        guard components.allSatisfy(\.isFinite) else { throw RenderError.raster("unsharp amount \(amount): a component overflowed") }
    }
}
