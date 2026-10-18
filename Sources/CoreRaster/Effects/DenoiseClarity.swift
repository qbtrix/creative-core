// DenoiseClarity.swift: edge-preserving denoise (a bilateral filter,
// strength and detail 0...1) and clarity (mid-tone local contrast, amount
// -100...100). A stub until effects-engine task FX-4 fills it: both throw
// `RasterError.invalid("not built")`.

extension PixelBuffer {
    /// This buffer denoised. Not built yet: throws.
    public func denoised(strength: Double, detail: Double) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// This buffer with its local contrast changed by `amount`. Not built yet: throws.
    public func clarity(amount: Double, radius: Double) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
