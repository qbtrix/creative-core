// CPUBackend+Effect.swift: the CPU backend's `.effect` family, every
// `LayerEffect`. A stub until the effects-engine feature fills this file: it
// checks `s` under the family's gate (`notBuilt`) and throws
// `RenderError.unsupported(.effect)`.
// Invariants: `s` is left unchanged; a surface this backend cannot resolve
// throws `surfaceMismatch` first.
import CoreRaster

extension CPUBackend {
    public func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface {
        try notBuilt(s, .effect)
    }
}
