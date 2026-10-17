// RenderBackend.swift: the one contract every app's Model draws through. A
// backend holds images as surfaces and implements some of the `RenderOp`
// families; a CPU backend over CoreRaster, as it lands, implements them all and
// is the pixel reference the others are measured against. Every method that
// performs an op throws `RenderError.unsupported(op)` when the op's family is
// not in `supports`, and `RenderError.surfaceMismatch` for a surface it did not
// make or has released, or a handle whose width and height do not match its
// stored pixels. Parameter ranges are CoreRaster's; a CoreRaster error comes
// back as `RenderError.raster`.
import CoreColor
import CoreRaster

/// A render backend: surfaces in, surfaces out, one method per op.
public protocol RenderBackend: Sendable {
    /// The backend's name, written into every surface it makes.
    var name: String { get }
    /// The op families this backend implements. An op outside them throws
    /// `RenderError.unsupported`.
    var supports: Set<RenderOp> { get }
    /// False once the device is lost; routing, as it lands, then falls back.
    var isHealthy: Bool { get }

    /// Uploads `buffer` into a new surface the backend holds. Not gated.
    func surface(_ buffer: PixelBuffer) throws -> RenderSurface
    /// Reads the surface's pixels back into a buffer. Not gated.
    func read(_ surface: RenderSurface) throws -> PixelBuffer
    /// Frees the surface's storage; a surface of another backend, or one
    /// already released, is ignored.
    func release(_ surface: RenderSurface)

    /// The surface as 8-bit RGBA bytes encoded for `colorSpace`, row-major,
    /// top row first, as `PixelBuffer.rgba8` gives them. Gated by `.display`.
    func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8]
    /// Blends `s` onto `b` in place, with its top-left pixel at (`x`, `y`) in
    /// `b`, through `mode` at `opacity`; `b` keeps its id and size. Gated by
    /// `.composite` for `.normal`, `.blendSeparable` for the other separable
    /// modes and `.blendNonSeparable` for hue, saturation, color and luminosity.
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float) throws
    /// The `width` x `height` region of `s` whose top-left pixel is at
    /// (`x`, `y`), as a new surface. Gated by `.transform`.
    func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface
    /// `s` turned clockwise by `turn`, as a new surface. Gated by `.transform`.
    func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface
    /// `s` resampled to `width` x `height` with `filter`, as a new surface.
    /// Gated by `.resample`.
    func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface
    /// `s` blurred with a Gaussian of standard deviation `sigma` pixels, as a
    /// new surface. Gated by `.blur`.
    func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface
    /// `s` sharpened by `amount` of the difference from its `sigma` blur where
    /// that difference exceeds `threshold`, as a new surface. Gated by `.blur`.
    func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface
    /// `s` with `adjustment` applied to every pixel, as a new surface. Gated
    /// by `.adjust`.
    func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface
    /// `s` with the pixels under `mask` replaced by the pixels `offset` away,
    /// weighted by the mask's coverage, as a new surface. Gated by `.retouch`.
    func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface
}
