// Effects.swift: the one entry point for layer effects, `applying(_:)` of a
// `LayerEffect`, which keeps the buffer's size. Each case is exactly the op
// it names, its arguments passed through in order: box and motion blur
// (BlurFamily), denoise and clarity (DenoiseClarity), stroke (AlphaEffects),
// glow and shadow (AlphaEffects+Light). No effect is computed here.
// Invariants: every case reaches its own op with every parameter, the `inner`
// flag and the stroke position included; a bad parameter throws that op's
// `RasterError.invalid`.

extension PixelBuffer {
    /// This buffer with `effect` applied, the same size. Throws the effect
    /// op's `RasterError.invalid` for a parameter outside its range.
    public func applying(_ effect: LayerEffect) throws -> PixelBuffer {
        switch effect {
        case .boxBlur(let radius):
            try boxBlurred(radius: radius)
        case let .motionBlur(degrees, distance):
            try motionBlurred(degrees: degrees, distance: distance)
        case let .denoise(strength, detail):
            try denoised(strength: strength, detail: detail)
        case let .clarity(amount, radius):
            try clarity(amount: amount, radius: radius)
        case let .glow(color, radius, intensity, inner):
            try glowing(color: color, radius: radius, intensity: intensity, inner: inner)
        case let .shadow(color, dx, dy, blur, inner):
            try shadowed(color: color, dx: dx, dy: dy, blur: blur, inner: inner)
        case let .stroke(color, width, position):
            try stroked(color: color, width: width, position: position)
        }
    }
}
