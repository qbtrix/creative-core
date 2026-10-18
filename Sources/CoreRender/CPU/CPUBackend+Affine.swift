// CPUBackend+Affine.swift: the CPU backend's `.affine` family (`transformed`,
// `flipped` and the composite through a matrix). Stubs until the
// affine-composite feature fills this file: each checks its surfaces under the
// family's gate (`notBuilt`) and throws `RenderError.unsupported(.affine)`.
// Invariants: `s` and `b` are left unchanged; a surface this backend cannot
// resolve throws `surfaceMismatch` first.
import CoreRaster

extension CPUBackend {
    public func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int,
                            filter: ResampleFilter) throws -> RenderSurface {
        try notBuilt(s, .affine)
    }

    public func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface {
        try notBuilt(s, .affine)
    }

    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                          opacity: Float, filter: ResampleFilter) throws {
        _ = try read(b)
        _ = try notBuilt(s, .affine)
    }
}
