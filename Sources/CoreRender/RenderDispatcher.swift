// RenderDispatcher.swift: routing between a preferred backend (the GPU) and
// the CPU backend, the pixel reference (render-backend RB-5). Each op goes to
// the preferred backend when it lists the op's family and is healthy, else to
// the CPU, and the routing never looks at which families the CPU has.
// Invariants: health is checked before support, so an unhealthy preferred
// backend gives every op to the CPU with reason `reasonUnhealthy`;
// `lastFallback` keeps the last fallback until the next one replaces it (a
// success never clears it), and nothing is recorded with no preferred backend.
// Health gates routing only: surfaces the preferred backend already made are
// still read from it and may throw `deviceLost`, and an op whose backend loses
// health after routing throws instead of retrying on the CPU. A surface
// made by the other backend is read from its owner and uploaded to the
// target first, so a fallback never changes a pixel. An uploaded input is
// released after the op; an uploaded backdrop replaces the caller's handle
// and the owner's copy is released, unless the backdrop is also the source,
// which the caller still holds. A surface neither backend made is passed
// on, and the target throws `surfaceMismatch`. Copies share `lastFallback`.
// Composites onto one CPU surface run one at a time under the CPU store's
// lock, and each applies in turn. A backdrop uploaded first becomes a new
// surface on each call, so composites racing onto it do not combine.
// Every W1 method routes by its own family, never an old one: the masked
// composite by `.maskedComposite` (not by its blend mode), `transformed`,
// `flipped` and the composite through a matrix by `.affine`, `applying` by
// `.effect`, and `adjusted` by `adjustment.family` (`.adjust` or `.color`).
// The two W1 composites share `composite`'s backdrop path.
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
    /// preferred backend, everything goes to `fallback`. `preferred.name` must
    /// differ from `fallback.name`: surfaces are told apart by that name, so
    /// with the same name every surface is taken as the fallback's and none
    /// is re-uploaded.
    public init(preferred: (any RenderBackend)?, fallback: CPUBackend) {
        self.preferred = preferred
        self.fallback = fallback
    }

    /// The `lastFallback` reason when the preferred backend does not list the op's family.
    public static let reasonUnsupported = "unsupported"
    /// The `lastFallback` reason when the preferred backend is not healthy.
    public static let reasonUnhealthy = "unhealthy"

    /// The last op that fell back and why (`reasonUnsupported` or
    /// `reasonUnhealthy`), nil until one does. A later op on the preferred
    /// backend does not clear it.
    public var lastFallback: (op: RenderOp, reason: String)? { last.withLock { $0 } }

    /// The preferred backend when it supports `op` and is healthy, else the
    /// fallback, recording why in `lastFallback` when there is a preferred one.
    /// Asking alone records it: a call that only checks where `op` would run
    /// counts as a fallback. Health is read at this call: if the preferred
    /// backend loses it before the op runs, the op throws and is not retried
    /// on the CPU, and surfaces it made are still read from it.
    public func backend(for op: RenderOp) -> any RenderBackend {
        guard let preferred else { return fallback }
        let reason: String
        if !preferred.isHealthy {
            reason = Self.reasonUnhealthy
        } else if !preferred.supports.contains(op) {
            reason = Self.reasonUnsupported
        } else {
            return preferred
        }
        last.withLock { $0 = (op, reason) }
        return fallback
    }

    /// Uploads `buffer` to the preferred backend while it is healthy, else to the CPU.
    /// Placement ignores `supports`; ops the preferred backend lacks re-upload to the CPU.
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

    /// Display bytes on the backend routed for `.display`, `s` uploaded to it if needed.
    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try run(.display, s) { try $0.display($1, colorSpace: colorSpace) }
    }

    /// Composites on the routed backend. When `b` was made by the other
    /// backend, `b` becomes the routed backend's copy and the old one is released,
    /// unless it is also `s`, which the caller still holds.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        try onBackdrop(RenderOp(compositing: mode), s, &b) {
            try $0.composite($1, onto: &$2, x: x, y: y, mode: mode, opacity: opacity)
        }
    }

    /// A masked composite on the backend routed for `.maskedComposite`, its
    /// own family whatever `mode` is, with `b` moved as `composite` moves it.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode,
                          opacity: Float, mask: Mask, maskX: Int, maskY: Int) throws {
        try onBackdrop(.maskedComposite, s, &b) {
            try $0.composite($1, onto: &$2, x: x, y: y, mode: mode, opacity: opacity,
                             mask: mask, maskX: maskX, maskY: maskY)
        }
    }

    /// A composite through `m` on the backend routed for `.affine`, with `b`
    /// moved as `composite` moves it.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                          opacity: Float, filter: ResampleFilter) throws {
        try onBackdrop(.affine, s, &b) {
            try $0.composite($1, onto: &$2, through: m, mode: mode, opacity: opacity, filter: filter)
        }
    }

    /// A crop on the backend routed for `.transform`.
    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try run(.transform, s) { try $0.cropped($1, x: x, y: y, width: width, height: height) }
    }
    /// A quarter turn on the backend routed for `.transform`.
    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        try run(.transform, s) { try $0.rotated($1, turn) }
    }
    /// A resample on the backend routed for `.resample`.
    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        try run(.resample, s) { try $0.resampled($1, width: width, height: height, filter: filter) }
    }
    /// A gaussian blur on the backend routed for `.blur`.
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        try run(.blur, s) { try $0.gaussianBlur($1, sigma: sigma) }
    }
    /// An unsharp mask on the backend routed for `.blur`, the family it shares with the blur.
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        try run(.blur, s) { try $0.unsharpMask($1, amount: amount, sigma: sigma, threshold: threshold) }
    }
    /// A tone adjustment on the backend routed for its family: `.adjust` for
    /// the six old cases, `.color` for the W1 colour cases.
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try run(adjustment.family, s) { try $0.adjusted($1, adjustment) }
    }
    /// A clone through `mask` on the backend routed for `.retouch`.
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        try run(.retouch, s) { try $0.cloned($1, offset: offset, through: mask) }
    }

    /// An affine resample on the backend routed for `.affine`.
    public func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int,
                            filter: ResampleFilter) throws -> RenderSurface {
        try run(.affine, s) { try $0.transformed($1, m, width: width, height: height, filter: filter) }
    }
    /// A mirror on the backend routed for `.affine`.
    public func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface {
        try run(.affine, s) { try $0.flipped($1, axis) }
    }
    /// A layer effect on the backend routed for `.effect`.
    public func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface {
        try run(.effect, s) { try $0.applying($1, effect) }
    }

    /// Routes `op`, then runs `body` on `s` and `b` there, each uploaded if
    /// needed. A moved `b` becomes the routed backend's copy and the owner's
    /// is released, unless it is also `s`; if `body` throws, the copy is
    /// released and `b` is left as it was.
    private func onBackdrop(_ op: RenderOp, _ s: RenderSurface, _ b: inout RenderSurface,
                            _ body: (any RenderBackend, RenderSurface, inout RenderSurface) throws -> Void) throws {
        let original = b
        let target = backend(for: op)
        let (backdrop, moved) = try local(b, on: target)
        var result = backdrop
        do {
            try run(target, s) { try body($0, $1, &result) }
        } catch {
            if moved { target.release(backdrop) }
            throw error
        }
        b = result
        if moved, original != s { release(original) }
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
