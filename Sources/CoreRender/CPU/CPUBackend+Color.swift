// CPUBackend+Color.swift: the CPU backend's `.color` family, the W1 colour
// tone adjustments (vibrance to invert). `adjusted` (CPUBackend+Ops.swift)
// gates `s` by `.color` and hands its pixels here. Each case is exactly the
// CoreRaster `PixelBuffer` method it names (tone-pack TP-3 to TP-5), with its
// arguments passed through, so its pixels equal the direct call with `==`;
// no colour math lives in CoreRender.
// Invariants: each case calls its own op once; the buffer is not changed; an
// `.adjust` case (never routed here) throws `unsupported(.adjust)`.
import CoreRaster

extension CPUBackend {
    /// `buffer` with the `.color` case `adjustment` applied.
    func colorAdjusted(_ buffer: PixelBuffer, _ adjustment: ToneAdjustment) throws -> PixelBuffer {
        switch adjustment {
        case .vibrance(let amount):
            try buffer.vibrance(amount)
        case let .hueSaturation(hue, saturation, lightness):
            try buffer.hueSaturation(hue: hue, saturation: saturation, lightness: lightness)
        case .hsl(let shifts):
            try buffer.hsl(shifts)
        case .blackAndWhite(let mix):
            try buffer.blackAndWhite(mix)
        case .channelMixer(let matrix):
            try buffer.channelMixer(matrix)
        case .colorBalance(let balance):
            try buffer.colorBalance(balance)
        case .gradientMap(let stops):
            try buffer.gradientMap(stops)
        case .lut(let lut):
            try buffer.applying(lut)
        case .posterize(let levels):
            try buffer.posterized(levels: levels)
        case .threshold(let level):
            try buffer.thresholded(level)
        case .invert:
            buffer.inverted()
        case .exposure, .levels, .curves, .whiteBalance, .contrast, .highlightsShadows:
            throw RenderError.unsupported(.adjust)  // `adjusted` runs these itself
        }
    }
}
