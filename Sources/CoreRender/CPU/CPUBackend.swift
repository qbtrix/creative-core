// CPUBackend.swift: the reference RenderBackend. It runs every op through
// CoreRaster, so its pixels are CoreRaster's pixels; the other backends are
// measured against it. RB-3 runs display and composite; the other families
// throw `.unsupported` until RB-4 fills them in.

import CoreColor
import CoreRaster
import Foundation

/// The CPU render backend over CoreRaster.
public final class CPUBackend: RenderBackend {
    /// The name every CPU surface carries in `RenderSurface.backend`.
    public static let backendName = "cpu"

    public let name = CPUBackend.backendName
    public let supports: Set<RenderOp> = [.display, .composite]
    public let isHealthy = true

    private let store = CPUSurfaceStore()

    public init() {}

    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        let surface = RenderSurface(id: UUID(), width: buffer.width, height: buffer.height,
                                    backend: name)
        store.insert(buffer, id: surface.id)
        return surface
    }

    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        try store.buffer(for: surface)
    }

    public func release(_ surface: RenderSurface) {
        store.release(surface)
    }

    public func display(_ surface: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        let buffer = try store.buffer(for: surface)
        return try raster { try buffer.rgba8(colorSpace: colorSpace) }
    }

    public func composite(_ source: RenderSurface, onto backdrop: inout RenderSurface,
                          x: Int, y: Int, mode: BlendMode, opacity: Float) throws {
        try store.composite(source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity)
    }

    // RB-4 fills these in. Until then each throws, so a caller never gets a blank result.

    public func cropped(_ surface: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }

    public func rotated(_ surface: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }

    public func resampled(_ surface: RenderSurface, width: Int, height: Int,
                          filter: ResampleFilter) throws -> RenderSurface {
        throw RenderError.unsupported(.resample)
    }

    public func gaussianBlur(_ surface: RenderSurface, sigma: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }

    public func unsharpMask(_ surface: RenderSurface, amount: Double, sigma: Double,
                            threshold: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }

    public func adjusted(_ surface: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        throw RenderError.unsupported(.adjust)
    }

    public func cloned(_ surface: RenderSurface, offset: (dx: Int, dy: Int),
                       through mask: Mask) throws -> RenderSurface {
        throw RenderError.unsupported(.retouch)
    }
}
