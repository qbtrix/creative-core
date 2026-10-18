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
// through CoreRaster at the given opacity on the backdrop's stored pixels, in
// place under the store's lock, so `read(b)` sees it; every CoreRaster error
// comes back as `RenderError.raster` through `RenderError.mapping`. Sizes are CoreRaster's
// (`PixelBuffer.validatedSize`), so no size arithmetic happens here.
// Composites onto one backdrop surface run one at a time under the store's
// lock, and each applies in turn on the result of the one before; every other
// call on this backend waits while a composite runs.
// `supports` lists every family, but until its feature lands a W1 family `f`
// in `RenderOp.notOnMetalYet` whose stub is not filled throws
// `unsupported(f)` here too: no backend runs it, so the caller skips the op.
import CoreColor
import CoreRaster

/// The CPU RenderBackend: CoreRaster behind the RenderBackend contract.
public struct CPUBackend: RenderBackend {
    public let name: String
    /// Every family: the CPU is the reference. A W1 family whose stub is not
    /// filled yet still throws `unsupported` (see `RenderError.unsupported`).
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

    /// Blends `s` onto `b` with CoreRaster's in-place composite, on `b`'s
    /// stored pixels themselves (`SurfaceStore.update`), so a 12 MP backdrop is
    /// never copied. `b` keeps its id and size. A bad opacity, or a surface this
    /// backend cannot resolve, throws before any pixel changes. A result that
    /// overflows to infinity throws with the rows above it already composited,
    /// as CoreRaster's `PixelBuffer.composite` does. The store's lock is held
    /// for the whole blend, so other calls on this backend wait while it runs.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        let source = try input(s, RenderOp(compositing: mode))
        try store.update(b) { backdrop in
            try RenderError.mapping { try backdrop.composite(source, x: x, y: y, mode: mode, opacity: opacity) }
        }
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
