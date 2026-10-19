// CPUBackend+MaskedComposite.swift: the CPU backend's `.maskedComposite`
// family (masks-mattes MM-5), a composite whose coverage is scaled by a mask.
// It is exactly CoreRaster's in-place masked composite (CompositeMasked.swift)
// with its arguments passed through in order, so its pixels equal the direct
// call with `==`; nothing is blended here.
// Invariants: the call is gated by `.maskedComposite` and reads `s`
// unchanged; it writes `b`'s stored pixels in place under the store's lock
// (`SurfaceStore.update`), as `composite` does, so composites onto one
// backdrop apply one at a time and `b` keeps its id and size; a surface this
// backend cannot resolve throws `surfaceMismatch` before anything is written;
// every CoreRaster error comes back as `RenderError.raster`.
import CoreRaster

extension CPUBackend {
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode,
                          opacity: Float, mask: Mask, maskX: Int, maskY: Int) throws {
        guard supports.contains(.maskedComposite) else { throw RenderError.unsupported(.maskedComposite) }
        let source = try read(s)
        try store.update(b) { backdrop in
            try RenderError.mapping {
                try backdrop.composite(source, x: x, y: y, mode: mode, opacity: opacity,
                                       mask: mask, maskX: maskX, maskY: maskY)
            }
        }
    }
}
