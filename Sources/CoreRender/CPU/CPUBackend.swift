// CPUBackend.swift: the CPU RenderBackend, the pixel reference every other
// backend is measured against. Its surfaces are PixelBuffers in a SurfaceStore
// (one lock, so the protocol stays non-mutating and Sendable): surface, read
// and release are its insert, lookup and remove, and every other op is the
// CoreRaster call itself, so its pixels equal the direct call with `==`.
// This file (render-backend RB-3) covers surface, read, release, display and
// the compositing families; CPUBackend+Ops.swift (RB-4) holds transform,
// resample, blur, adjust and retouch, each a new surface through `derived`.
// Invariants: a surface this backend did not make, has released, or whose
// size disagrees with its pixels throws `surfaceMismatch`; `composite` blends
// in place through CoreRaster at the given opacity and stores the result under
// the backdrop's id, so `read(b)` sees it; every CoreRaster error comes back as
// `RenderError.raster` through `RenderError.mapping`. Sizes are CoreRaster's
// (`PixelBuffer.validatedSize`), so no size arithmetic happens here.
// Two composites at once onto copies of one backdrop handle keep only one
// result: each reads, blends and stores the whole backdrop, and the last
// store wins.
import CoreColor
import CoreRaster

/// The CPU RenderBackend: CoreRaster behind the RenderBackend contract.
public struct CPUBackend: RenderBackend {
    public let name: String
    /// Every family: the CPU is the reference.
    public let supports: Set<RenderOp> = Set(RenderOp.allCases)
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

    /// `body` run on `s`'s pixels, gated by `op`, with any CoreRaster error
    /// mapped to `.raster`, its result stored as a new surface; `s` is unchanged.
    func derived(_ s: RenderSurface, _ op: RenderOp,
                 _ body: (PixelBuffer) throws -> PixelBuffer) throws -> RenderSurface {
        let source = try input(s, op)
        return store.insert(try RenderError.mapping { try body(source) })
    }

    /// Throws `unsupported(op)` outside `supports`, then returns `s`'s pixels
    /// or throws `surfaceMismatch`.
    private func input(_ s: RenderSurface, _ op: RenderOp) throws -> PixelBuffer {
        guard supports.contains(op) else { throw RenderError.unsupported(op) }
        return try store.buffer(for: s)
    }
}
