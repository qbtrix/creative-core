// CPUBackend+Effect.swift: the CPU backend's `.effect` family, every
// `LayerEffect`: CoreRaster's `applying(_:)` on `s`'s pixels, so the result
// equals the direct call with `==`. No effect is computed here.
// Invariants: `s` is read under the `.effect` gate and left unchanged
// (`derived`); a surface this backend cannot resolve throws
// `surfaceMismatch`; a CoreRaster error comes back as `RenderError.raster`.
import CoreRaster

extension CPUBackend {
    public func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface {
        try derived(s, .effect) { try $0.applying(effect) }
    }
}
