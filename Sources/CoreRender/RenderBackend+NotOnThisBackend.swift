// RenderBackend+NotOnThisBackend.swift: the "not on this backend" default of
// each RenderBackend method the W1 families add. Each throws
// `RenderError.unsupported(<its family>)` and touches nothing (a composite's
// backdrop is left as it was), so a backend written before W1 (the Metal
// backend, test doubles) compiles unchanged and answers a W1 call the way it
// answers any family it does not run. A default throws whether or not the
// family is in `supports`: a backend that runs a family implements its
// methods, which replace these.
import CoreRaster

extension RenderBackend {
    /// Not on this backend: throws `unsupported(.maskedComposite)`.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode,
                          opacity: Float, mask: Mask, maskX: Int, maskY: Int) throws {
        throw RenderError.unsupported(.maskedComposite)
    }

    /// Not on this backend: throws `unsupported(.affine)`.
    public func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int,
                            filter: ResampleFilter) throws -> RenderSurface {
        throw RenderError.unsupported(.affine)
    }

    /// Not on this backend: throws `unsupported(.affine)`.
    public func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface { throw RenderError.unsupported(.affine) }

    /// Not on this backend: throws `unsupported(.affine)`.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                          opacity: Float, filter: ResampleFilter) throws {
        throw RenderError.unsupported(.affine)
    }

    /// Not on this backend: throws `unsupported(.effect)`.
    public func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface {
        throw RenderError.unsupported(.effect)
    }
}
