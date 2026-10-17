// RenderBackend.swift: the contract every render backend implements. An app's
// Model draws through a RenderDispatcher, which calls one of these per op. The
// backend owns its surfaces: callers hold handles and never see the storage.

import CoreColor
import CoreRaster

/// A place pixels are drawn: the CPU today, Metal later. Every method either
/// runs the op or throws; a backend never silently skips work it was asked for.
public protocol RenderBackend: Sendable {
    /// Names the backend in `RenderSurface.backend` and in fallback reasons.
    var name: String { get }
    /// The op families this backend runs. Anything else throws `.unsupported`.
    var supports: Set<RenderOp> { get }
    /// False when the backend has lost its device; the dispatcher then routes
    /// every op to the CPU.
    var isHealthy: Bool { get }

    /// Copies `buffer` into storage this backend owns.
    func surface(_ buffer: PixelBuffer) throws -> RenderSurface
    /// Copies a surface's pixels out. Throws `.surfaceMismatch` for a surface
    /// this backend does not hold.
    func read(_ surface: RenderSurface) throws -> PixelBuffer
    /// Frees a surface. Using it afterwards throws `.surfaceMismatch`.
    func release(_ surface: RenderSurface)

    /// The surface as display bytes in `colorSpace`, RGBA8, one row after another.
    func display(_ surface: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8]
    /// Composites `source` onto `backdrop` in place at (x, y), as CoreRaster does.
    func composite(_ source: RenderSurface, onto backdrop: inout RenderSurface,
                   x: Int, y: Int, mode: BlendMode, opacity: Float) throws
    func cropped(_ surface: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface
    func rotated(_ surface: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface
    func resampled(_ surface: RenderSurface, width: Int, height: Int,
                   filter: ResampleFilter) throws -> RenderSurface
    func gaussianBlur(_ surface: RenderSurface, sigma: Double) throws -> RenderSurface
    func unsharpMask(_ surface: RenderSurface, amount: Double, sigma: Double,
                     threshold: Double) throws -> RenderSurface
    func adjusted(_ surface: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface
    func cloned(_ surface: RenderSurface, offset: (dx: Int, dy: Int),
                through mask: Mask) throws -> RenderSurface
}
