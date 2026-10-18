// Effects.swift: the one entry point for layer effects, `applying(_:)` of a
// `LayerEffect`, which keeps the buffer's size. A stub until effects-engine
// task FX-7 fills it: every case throws `RasterError.invalid("not built")`.

extension PixelBuffer {
    /// This buffer with `effect` applied, the same size. Not built yet: throws.
    public func applying(_ effect: LayerEffect) throws -> PixelBuffer {
        throw RasterError.invalid("not built")
    }
}
