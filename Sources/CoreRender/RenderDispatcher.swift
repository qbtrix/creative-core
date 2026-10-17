// RenderDispatcher.swift: routing between a preferred backend (the GPU) and
// the CPU backend, the pixel reference (render-backend RB-5). Each op goes to
// the preferred backend when it lists the op's family and is healthy, else to
// the CPU, and the routing never looks at which families the CPU has.
// Invariants: health is checked before support, so an unhealthy preferred
// backend gives every op to the CPU with reason "unhealthy"; `lastFallback`
// keeps the last fallback until the next one replaces it (a success never
// clears it), and nothing is recorded with no preferred backend; a surface
// made by the other backend is read from its owner and uploaded to the
// target first, so a fallback never changes a pixel. An uploaded input is
// released after the op; an uploaded backdrop replaces the caller's handle
// and the owner's copy is released. A surface neither backend made is passed
// on, and the target throws `surfaceMismatch`. Copies share `lastFallback`.
import CoreColor
import CoreRaster

/// Sends each op to the preferred backend when it can run it, else to the CPU.
public struct RenderDispatcher: Sendable {
    /// The backend ops go to when it supports them and is healthy.
    public let preferred: (any RenderBackend)?
    /// Where every other op goes.
    public let fallback: CPUBackend

    private let last = Locked<(op: RenderOp, reason: String)?>(nil)

    /// Routes to `preferred` where it can, else to `fallback`; with no
    /// preferred backend, everything goes to `fallback`.
    public init(preferred: (any RenderBackend)?, fallback: CPUBackend) {
        self.preferred = preferred
        self.fallback = fallback
    }

    /// The last op that fell back and why ("unsupported" or "unhealthy"), nil
    /// until one does. A later op on the preferred backend does not clear it.
    public var lastFallback: (op: RenderOp, reason: String)? { last.withLock { $0 } }

    /// The preferred backend when it supports `op` and is healthy, else the
    /// fallback, recording why in `lastFallback` when there is a preferred one.
    public func backend(for op: RenderOp) -> any RenderBackend {
        guard let preferred else { return fallback }
        let reason: String
        if !preferred.isHealthy {
            reason = "unhealthy"
        } else if !preferred.supports.contains(op) {
            reason = "unsupported"
        } else {
            return preferred
        }
        last.withLock { $0 = (op, reason) }
        return fallback
    }

    /// Uploads `buffer` to the preferred backend while it is healthy, else to the CPU.
    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        if let preferred, preferred.isHealthy { return try preferred.surface(buffer) }
        return try fallback.surface(buffer)
    }

    /// Reads `surface` from the backend that made it; `surfaceMismatch` for neither.
    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        guard let owner = owner(of: surface) else { throw RenderError.surfaceMismatch }
        return try owner.read(surface)
    }

    /// Releases `surface` on the backend that made it; any other is ignored.
    public func release(_ surface: RenderSurface) {
        owner(of: surface)?.release(surface)
    }

    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try run(.display, s) { try $0.display($1, colorSpace: colorSpace) }
    }

    /// Composites on the routed backend. When `b` was made by the other
    /// backend, `b` becomes the routed backend's copy and the old one is released.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        let original = b
        let target = backend(for: RenderOp(compositing: mode))
        let (backdrop, moved) = try local(b, on: target)
        var result = backdrop
        do {
            try run(target, s) { try $0.composite($1, onto: &result, x: x, y: y, mode: mode, opacity: opacity) }
        } catch {
            if moved { target.release(backdrop) }
            throw error
        }
        b = result
        if moved { release(original) }
    }

    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try run(.transform, s) { try $0.cropped($1, x: x, y: y, width: width, height: height) }
    }
    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        try run(.transform, s) { try $0.rotated($1, turn) }
    }
    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        try run(.resample, s) { try $0.resampled($1, width: width, height: height, filter: filter) }
    }
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        try run(.blur, s) { try $0.gaussianBlur($1, sigma: sigma) }
    }
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        try run(.blur, s) { try $0.unsharpMask($1, amount: amount, sigma: sigma, threshold: threshold) }
    }
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try run(.adjust, s) { try $0.adjusted($1, adjustment) }
    }
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        try run(.retouch, s) { try $0.cloned($1, offset: offset, through: mask) }
    }

    /// Routes `op`, then runs `body` there with `s` uploaded to it if needed.
    private func run<T>(_ op: RenderOp, _ s: RenderSurface,
                        _ body: (any RenderBackend, RenderSurface) throws -> T) throws -> T {
        try run(backend(for: op), s, body)
    }

    /// Runs `body` on `target` with `s` on it, releasing an uploaded copy after.
    private func run<T>(_ target: any RenderBackend, _ s: RenderSurface,
                        _ body: (any RenderBackend, RenderSurface) throws -> T) throws -> T {
        let (input, uploaded) = try local(s, on: target)
        defer { if uploaded { target.release(input) } }
        return try body(target, input)
    }

    /// `s` on `target`: itself when `target` made it or no backend here did,
    /// else read from its owner and uploaded, with `uploaded` true.
    private func local(_ s: RenderSurface, on target: any RenderBackend) throws -> (RenderSurface, uploaded: Bool) {
        guard s.backend != target.name, let owner = owner(of: s) else { return (s, false) }
        return (try target.surface(owner.read(s)), true)
    }

    /// The backend here whose name `s` carries, the CPU first.
    private func owner(of s: RenderSurface) -> (any RenderBackend)? {
        if s.backend == fallback.name { return fallback }
        if let preferred, s.backend == preferred.name { return preferred }
        return nil
    }
}
