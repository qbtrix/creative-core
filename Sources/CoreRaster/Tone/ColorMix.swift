// ColorMix.swift: black and white, channel mixer and colour balance on a
// PixelBuffer, the tone-pack contract slice (docs/blueprints/core/features/tone-pack.md).
// TP-0 stub: each op throws `RasterError.invalid("not built")` until TP-4
// fills it with the packet's formulas and turns on `ColorMixTests`.
extension PixelBuffer {
    /// Gray from six hue-range weights, with the mix's optional tint.
    public func blackAndWhite(_ mix: GrayMix) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Each output channel as a weighted sum of the inputs plus a constant.
    public func channelMixer(_ m: ChannelMatrix) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }

    /// Shifts per tonal zone (shadows, midtones, highlights).
    public func colorBalance(_ b: ToneBalance) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
