// RenderBackend.swift: the one contract every app's Model draws through. A
// backend holds images as surfaces and implements some of the `RenderOp`
// families; the CPU backend over CoreRaster is the pixel reference the others
// are measured against, and lists them all in `supports`. Every method that performs
// an op throws `RenderError.unsupported(op)` when the op's family is not in
// `supports`, and `RenderError.surfaceMismatch` for a surface it did not
// make or has released, or a handle whose width and height do not match its
// stored pixels. Parameter ranges are CoreRaster's; a CoreRaster error comes
// back as `RenderError.raster`. Until its feature lands, every backend, the
// CPU included, throws `unsupported(f)` for a W1 family `f` in
// `RenderOp.notOnMetalYet` whose method is not built, even when `supports`
// lists `f`; there is no fallback, and the caller skips the op.
import CoreColor
import CoreRaster

/// A render backend: surfaces in, surfaces out, one method per op.
public protocol RenderBackend: Sendable {
    /// The backend's name, written into every surface it makes.
    var name: String { get }
    /// The op families this backend implements. An op outside them throws
    /// `RenderError.unsupported`.
    var supports: Set<RenderOp> { get }
    /// False once the device is lost; RenderDispatcher then falls back.
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
    /// by `adjustment.family`: `.adjust`, or `.color` for a W1 colour case.
    func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface
    /// `s` with the pixels under `mask` replaced by the pixels `offset` away,
    /// weighted by the mask's coverage, as a new surface. Gated by `.retouch`.
    func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface

    // Resident rendering (RenderBackend+Resident.swift): each has a default built
    // from the methods above, so the CPU backend and the test doubles get it as is.
    /// A new `width` x `height` surface, every pixel clear. Not gated. The
    /// default uploads a clear `PixelBuffer`; a GPU backend clears on the device.
    func blank(width: Int, height: Int) throws -> RenderSurface
    /// Blends each step's surface onto `b` in place, in order, as one
    /// `composite(_:onto:x:y:mode:opacity:)` per step does, gated by each
    /// step's family. The default makes exactly those calls; a GPU backend
    /// encodes them in one command buffer. Nothing changes when a step's
    /// family is unsupported.
    func composite(_ steps: [CompositeStep], onto b: inout RenderSurface) throws

    // The W1 families, CPU first. Each has a default that throws
    // `unsupported(<its family>)` (RenderBackend+NotOnThisBackend.swift), so a
    // backend without the family compiles unchanged.
    /// Blends `s` onto `b` in place as `composite(_:onto:x:y:mode:opacity:)`
    /// does, with each pixel's coverage scaled by `mask`, whose top-left
    /// pixel sits at (`maskX`, `maskY`) in `b`; outside the mask nothing
    /// changes. Gated by `.maskedComposite`.
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float,
                   mask: Mask, maskX: Int, maskY: Int) throws
    /// `s` mapped through `m` (source to output pixels) into a new
    /// `width` x `height` surface, sampled with `filter`; output pixels with
    /// no source are clear. Coordinates are continuous pixel units with
    /// (0, 0) at the top-left corner of the top-left pixel; pixel (x, y) is
    /// sampled at its centre (x + 0.5, y + 0.5). Gated by `.affine`.
    func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int, filter: ResampleFilter) throws
        -> RenderSurface
    /// `s` mirrored across `axis`, as a new surface. Gated by `.affine`.
    func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface
    /// Blends `s` onto `b` in place through `m` (`s`'s pixels to `b`'s),
    /// sampled with `filter`, with `mode` at `opacity`; `b` keeps its id and
    /// size. Coordinates are continuous pixel units with (0, 0) at the
    /// top-left corner of the top-left pixel; pixel (x, y) is sampled at its
    /// centre (x + 0.5, y + 0.5). Gated by `.affine`. Only `b`'s pixels
    /// inside `m.writeBounds(of: s.width, s.height, filter: filter)` can
    /// change. A bad opacity or matrix throws with `b` unchanged; a
    /// non-finite lanczos3 overshoot or blend result throws after the
    /// composite began, so `b` may hold it in some rows of that box and not
    /// in others (never outside it): redo the composite on a copy kept
    /// before the call to recover.
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                   opacity: Float, filter: ResampleFilter) throws
    /// `s` with `effect` applied, as a new surface of the same size. Gated
    /// by `.effect`.
    func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface
    /// `s` drawn with the layer style `stack`, as a new surface of the same
    /// size. Gated by `.style`.
    func styled(_ s: RenderSurface, _ stack: LayerStyleStack) throws -> RenderSurface
}
