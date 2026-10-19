// CPUBackend+Affine.swift: the CPU backend's `.affine` family (`transformed`,
// `flipped` and the composite through a matrix), affine-composite AC-6. Each
// is exactly the CoreRaster call it names (AffineTransform.swift,
// CompositeAffine.swift) with its arguments passed through in order, so its
// pixels equal the direct call with `==`; nothing is sampled or blended here.
// Invariants: every call is gated by `.affine` and reads `s` unchanged;
// `transformed` and `flipped` return a new surface (`derived`); the composite
// writes `b`'s stored pixels in place (`SurfaceStore.update`), so `b` keeps
// its id and size, a bad opacity or matrix throws with `b` unchanged, and a
// non-finite overshoot throws with only rows inside `m.writeBounds` written; a
// surface this backend cannot resolve throws `surfaceMismatch`; every
// CoreRaster error comes back as `RenderError.raster`.
import CoreRaster

extension CPUBackend {
    public func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int,
                            filter: ResampleFilter) throws -> RenderSurface {
        try derived(s, .affine) { try $0.transformed(m, width: width, height: height, filter: filter) }
    }

    public func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface {
        try derived(s, .affine) { $0.flipped(axis) }
    }

    /// CoreRaster's in-place `composite(_:through:mode:opacity:filter:)` on
    /// `b`'s stored pixels, under the store's lock as the offset composite runs.
    /// Writes only inside `m.writeBounds`; a bad opacity or matrix throws
    /// with `b` unchanged, but a non-finite lanczos3 overshoot or blend
    /// result throws after the rows above it in that box were composited.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                          opacity: Float, filter: ResampleFilter) throws {
        guard supports.contains(.affine) else { throw RenderError.unsupported(.affine) }
        let source = try read(s)
        try store.update(b) { backdrop in
            try RenderError.mapping {
                try backdrop.composite(source, through: m, mode: mode, opacity: opacity, filter: filter)
            }
        }
    }
}
