// CPUBackend.swift: the CPU RenderBackend, the pixel reference every other
// backend is measured against. Its surfaces are PixelBuffers in a SurfaceStore
// (one lock, so the protocol stays non-mutating and Sendable), and every op is
// the CoreRaster call itself, so its pixels equal the direct call with `==`.
// This file (render-backend RB-3) covers surface, read, release, display and
// the compositing families; transform, resample, blur, adjust and retouch are
// RB-4's and throw `unsupported` until then.
// Invariants: a surface this backend did not make, has released, or whose
// size disagrees with its pixels throws `surfaceMismatch`; `composite` blends
// in place through CoreRaster at the given opacity and stores the result under
// the backdrop's id, so `read(b)` sees it; every CoreRaster error comes back as
// `RenderError.raster` through `RenderError.mapping`. Sizes are CoreRaster's
// (`PixelBuffer.validatedSize`), so no size arithmetic happens here.
// Two composites onto one backdrop at once from two threads keep only one
// result: a backdrop surface is the caller's `inout` value, written by one
// caller at a time.
import CoreColor
import CoreRaster

/// The CPU RenderBackend: CoreRaster behind the RenderBackend contract.
public struct CPUBackend: RenderBackend {
    public let name: String
    /// Display and the compositing families (RB-3).
    public let supports: Set<RenderOp> = [.display, .composite, .blendSeparable, .blendNonSeparable]
    /// The CPU is never lost.
    public var isHealthy: Bool { true }

    private let store: SurfaceStore

    /// A CPU backend named `name`, written into every surface it makes.
    public init(name: String = "cpu") {
        self.name = name
        self.store = SurfaceStore(backend: name)
    }

    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        store.insert(buffer)
    }

    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        try store.buffer(for: surface)
    }

    public func release(_ surface: RenderSurface) {
        store.remove(surface)
    }

    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        let buffer = try input(s, .display)
        return try RenderError.mapping { try buffer.rgba8(colorSpace: colorSpace) }
    }

    /// Blends `s` onto `b` with CoreRaster's in-place composite and stores the
    /// result under `b`'s id. A throw leaves `b`'s stored pixels unchanged.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        let source = try input(s, RenderOp(compositing: mode))
        var backdrop = try store.buffer(for: b)
        try RenderError.mapping { try backdrop.composite(source, x: x, y: y, mode: mode, opacity: opacity) }
        try store.replace(b, with: backdrop)
    }

    // RB-4's families: not supported yet.
    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }
    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }
    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        throw RenderError.unsupported(.resample)
    }
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        throw RenderError.unsupported(.adjust)
    }
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        throw RenderError.unsupported(.retouch)
    }

    /// Throws `unsupported(op)` outside `supports`, then returns `s`'s pixels
    /// or throws `surfaceMismatch`.
    private func input(_ s: RenderSurface, _ op: RenderOp) throws -> PixelBuffer {
        guard supports.contains(op) else { throw RenderError.unsupported(op) }
        return try store.buffer(for: s)
    }
}
