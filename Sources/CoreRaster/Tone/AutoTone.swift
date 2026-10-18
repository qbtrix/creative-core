// AutoTone.swift: the levels and white balance auto tone suggests from a
// buffer's histogram, the tone-pack contract slice
// (docs/blueprints/core/features/tone-pack.md).
// TP-0 stub: `suggest` throws `RasterError.invalid("not built")` until TP-6
// fills it and turns on `AutoToneTests`.
public struct AutoTone: Hashable, Sendable {
    public var inBlack: Float, inWhite: Float, gamma: Float, temperature: Float, tint: Float

    public init(inBlack: Float, inWhite: Float, gamma: Float, temperature: Float, tint: Float) {
        self.inBlack = inBlack
        self.inWhite = inWhite
        self.gamma = gamma
        self.temperature = temperature
        self.tint = tint
    }

    /// Levels (black and white points at 0.1% and 99.9%, a gamma) and a white
    /// balance that neutralise the buffer's cast.
    public static func suggest(for buffer: PixelBuffer) throws -> AutoTone {
        throw RasterError.invalid("not built")
    }
}
