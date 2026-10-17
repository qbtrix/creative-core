// MetalBackend.swift: the Metal RenderBackend (metal-backend MB-1, MB-2): a device, its
// command queue, the capability state, the pipeline cache and the live MetalSurfaces keyed
// by RenderSurface id. Metal's protocols are not Sendable, so the class is @unchecked
// Sendable and every access to mutable state goes through `withLock` (internal, so the
// extension files of later slices share it; `fail` and `recover` take it themselves, so
// never call them with it held). Invariants: `supports` is empty while not healthy,
// `residentBytes` sums the live surfaces' resident tiles and stays at or under `budgetBytes`
// after every upload (MetalBackend+Memory.swift), a surface this backend did not make
// throws `surfaceMismatch`, `.display`, `.transform` and (read-write tier 2) `.composite` and `.blendSeparable` start enabled; every other op throws
// `unsupported` until its slice, a probe, a command
// buffer or a texture allocation that fails leaves the backend unhealthy with the reason in
// `capabilities.lastError` (so `deviceLost` is only ever thrown with `isHealthy` false), and only a
// `recover` whose probe passes makes it healthy again. No GPU wait or runtime compile of a custom
// source runs under the lock: `supports` and `isHealthy` answer while a probe is in flight.
#if canImport(Metal)
import CoreColor
import CoreRaster
import CoreRender
import Foundation
import Metal

/// The Metal `RenderBackend`: tiled rgba16Float surfaces on one GPU. Display encode runs; every other
/// op throws `RenderError.unsupported` until its slice lands; `supports` tells the dispatcher which do not.
public final class MetalBackend: RenderBackend, @unchecked Sendable {
    /// The system's default GPU, or nil without one; tests gate on `.enabled(if: defaultDevice != nil)`.
    public static var defaultDevice: (any MTLDevice)? { MTLCreateSystemDefaultDevice() }

    /// The GPU this backend draws on.
    public let device: any MTLDevice
    /// Reserved for an on-disk pipeline cache; unused today. The backend never reads, writes or
    /// deletes anything at this URL: pipelines are memoised in process and Metal keeps its own shader cache.
    public let cacheURL: URL?
    /// The queue every slice's command buffers go through; `recover` replaces it. Read under the lock.
    private(set) var commandQueue: any MTLCommandQueue
    /// The compute pipelines, compiled once per key and memoised. Call under the lock.
    let pipelines: MetalPipelines

    private let lock = NSLock()
    var state = MetalCapabilities()
    var surfaces: [UUID: MetalSurface] = [:]
    /// `budgetBytes`' storage; read and write under the lock.
    var budget: Int
    /// Counts uploads, reads and restores: the `lastUse` stamp. Advance with `tick` under the lock.
    private var useClock: UInt64 = 0
    /// Rows the opaque-row fast path blitted (MB-6, MetalBackend+OpaqueRows.swift); under the lock.
    var blittedRows = 0
    /// One full tile's texture bytes (256 x 256 x 8): the floor of `budgetBytes`.
    private static let tileBytes = SurfaceTiling.tileSize * SurfaceTiling.tileSize * MetalSurface.bytesPerPixel

    /// Opens a backend on `device`. Throws `RenderError.deviceLost` when it gives no command
    /// queue. `cacheURL` is reserved (see the property) and never touched.
    public init(device: any MTLDevice, cacheURL: URL?) throws {
        self.device = device
        self.commandQueue = try Self.makeQueue(on: device)
        self.pipelines = MetalPipelines(device: device)
        self.cacheURL = cacheURL
        self.budget = SurfaceTiling.defaultBudget(workingSet: device.recommendedMaxWorkingSetSize, tileBytes: Self.tileBytes)
        state.enable(.display)
        state.enable(.transform)
        if Self.compositesInPlace(on: device) {
            state.enable(.composite)
            state.enable(.blendSeparable)  // MB-6
        }
        state.enable(.resample)
    }

    /// "Metal (<device name>)": the status note's text and every surface's `backend`.
    public var name: String { "Metal (\(device.name))" }
    /// The op families this backend has proven, plus its health and last error.
    public var capabilities: MetalCapabilities { withLock { state } }
    /// `capabilities.supported` while healthy, else empty: the dispatcher drops to CPU on a device loss.
    public var supports: Set<RenderOp> { withLock { state.effectiveSupports } }
    /// False after a command buffer error, a failed probe or texture allocation, or a lost device,
    /// until a `recover` whose probe passes.
    public var isHealthy: Bool { withLock { state.healthy } }
    /// Bytes of resident tile textures held by the live surfaces (8 per pixel); evicted tiles count 0.
    public var residentBytes: Int { withLock { residentBytesLocked } }
    /// The most texture bytes the surfaces keep resident: above it, least recently used tiles move to
    /// CPU shadows after each upload. Default: half the device's `recommendedMaxWorkingSetSize`, at
    /// least one full tile (256 x 256 x 8 bytes). Setting it evicts at once (0 shadows every tile); no value fails.
    public var budgetBytes: Int {
        get { withLock { budget } }
        set {
            withLock { budget = newValue }
            evictIfNeeded()
        }
    }
    /// `residentBytes` for a caller holding the lock.
    var residentBytesLocked: Int { surfaces.values.reduce(0) { $0 + $1.residentBytes } }
    /// Pipelines built by compiling shader source since init, one per key (plus each custom probe).
    public var pipelineCompileCount: Int { withLock { pipelines.compileCount } }
    /// Pipeline requests answered from the in-process memo without a compile.
    public var pipelineLoadCount: Int { withLock { pipelines.loadCount } }

    /// The storage mode of tile textures: `.shared` on a GPU with unified memory, `.managed` on a
    /// discrete one, where the CPU and GPU keep separate copies. Until a GPU write to a tile,
    /// `replace` and `getBytes` see current pixels in either mode; the first slice that encodes GPU
    /// writes to a managed tile must synchronize it with a blit before a CPU read.
    public static func tileStorageMode(unifiedMemory: Bool) -> MTLStorageMode {
        #if os(macOS)
        return unifiedMemory ? .shared : .managed
        #else
        return .shared
        #endif
    }

    /// Compiles and memoises the caller's kernel named by `op` and `variant` in `source` (MSL), to
    /// check it builds on this device; a key already memoised is not compiled again. `variant` may
    /// come from outside: it goes through `PipelineKey.validated`. Throws `RenderError.raster` for a
    /// variant outside `[A-Za-z0-9_]` or when `source` has no such kernel, and Metal's error when it
    /// does not compile. Never fails the backend. Caller pipelines are kept apart from the backend's
    /// own: `.display` with variant "encode" or "probe" compiles the caller's kernel and no op runs it.
    /// Built-in ops compile their own pipeline on first use.
    public func preparePipeline(op: RenderOp, variant: String, source: String) throws {
        let key = try PipelineKey.validated(op: op, variant: variant)
        _ = try withLock { try pipelines.prepared(for: key, source: source) }
    }

    /// Reports a finished command buffer's `status` and `error` (after `waitUntilCompleted` or in a
    /// completed handler). Anything but `.completed` with no error is a device failure: the backend
    /// is marked failed with "<label>: ..." (`isHealthy` false, `supports` empty) and
    /// `RenderError.deviceLost` carries the same reason. Call it with the lock free.
    public func recordCompletion(status: MTLCommandBufferStatus, error: (any Error)?, label: String) throws {
        guard let reason = Self.commandBufferFailure(status: status, error: error, label: label) else { return }
        fail(reason)
        throw RenderError.deviceLost(reason)
    }

    /// Why a finished command buffer failed, or nil when it completed cleanly: a non-nil `error`,
    /// or any `status` other than `.completed`.
    static func commandBufferFailure(status: MTLCommandBufferStatus, error: (any Error)?, label: String) -> String? {
        if let error { return "\(label): command buffer failed: \(error)" }
        guard status == .completed else { return "\(label): command buffer ended with status \(status.rawValue)" }
        return nil
    }

    /// Changes the capability state under the lock (a slice enables its family; `fail` and `recover`).
    func withCapabilities<R>(_ body: (inout MetalCapabilities) throws -> R) rethrows -> R {
        try withLock { try body(&state) }
    }

    /// Records a device loss or command-buffer error: `isHealthy` turns false, `supports` empty and
    /// `capabilities.lastError` holds `reason`, until `recover`. `capabilities.supported` is kept.
    public func fail(_ reason: String) { withCapabilities { $0.fail(reason) } }

    /// Makes a new command queue on `device`, runs the probe on it and, only if the probe passes,
    /// installs the queue and clears the failure: `isHealthy` true, `lastError` nil. Throws
    /// `RenderError.deviceLost` when the device gives no queue (the failure stays in place) or the
    /// probe fails (the backend is marked failed with the probe's reason, as `probe` does).
    /// `device` cannot change: after a real device loss, open a new `MetalBackend` on a new device.
    /// `probeSource` replaces the probe's MSL, as `probe(source:)`'s does; tests use it.
    public func recover(probeSource: String? = nil) throws {
        let queue = try Self.makeQueue(on: device)
        try checkedProbe(source: probeSource, on: queue)
        withCapabilities { capabilities in
            commandQueue = queue
            capabilities.recover()
        }
    }

    /// Runs the probe kernel once (four floats doubled in place) and checks the result. On any
    /// failure (a compile error, no command buffer, encoder or buffer, a command-buffer error, or
    /// wrong output) the backend is marked failed with the reason and `RenderError.deviceLost`
    /// carries the same reason. The dispatcher or an app calls this after a device-loss
    /// notification. `source`, when given, replaces the probe's MSL (it must define
    /// `display_probe`) and is compiled fresh, never memoised: tests use it to drive the failure path.
    /// The lock is held only to read the queue and pipeline: the compile of a custom source and the
    /// GPU wait run with it free, so `supports` and `isHealthy` answer while the probe runs.
    public func probe(source: String? = nil) throws {
        try checkedProbe(source: source, on: withLock { commandQueue })
    }

    /// `runProbe` on `queue`; on any failure marks the backend failed with "probe: ..." and throws
    /// `RenderError.deviceLost` with that reason. Call with the lock free.
    private func checkedProbe(source: String?, on queue: any MTLCommandQueue) throws {
        do {
            try runProbe(source: source, on: queue)
        } catch {
            let reason = Self.probeReason(error)
            fail(reason)
            throw RenderError.deviceLost(reason)
        }
    }

    /// A probe error's text, prefixed "probe: " unless it already is.
    static func probeReason(_ error: any Error) -> String {
        let text: String
        switch error {
        case RenderError.deviceLost(let message), RenderError.raster(let message): text = message
        default: text = "\(error)"
        }
        return text.hasPrefix("probe: ") ? text : "probe: \(text)"
    }

    /// The probe's GPU work on `queue`; call with the lock free (it takes it only for the pipeline
    /// memo and the compile count). Throws `RenderError.deviceLost("probe: ...")`, or the compile's error.
    private func runProbe(source: String?, on queue: any MTLCommandQueue) throws {
        let pipeline: any MTLComputePipelineState
        if let source {
            pipeline = try MetalPipelines.build(MetalPipelines.probeKey, source: source, on: device)
            withLock { pipelines.noteCompile() }
        } else {
            pipeline = try withLock { try pipelines.probePipeline() }
        }
        let input: [Float] = [1, 2, 3, 4]
        let made = input.withUnsafeBytes { raw -> (any MTLBuffer)? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        guard let buffer = made else { throw RenderError.deviceLost("probe: no buffer on \(device.name)") }
        guard let commands = queue.makeCommandBuffer() else {
            throw RenderError.deviceLost("probe: no command buffer on \(device.name)")
        }
        guard let encoder = commands.makeComputeCommandEncoder() else {
            throw RenderError.deviceLost("probe: no compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(buffer, offset: 0, index: 0)
        encoder.dispatchThreadgroups(
            MTLSize(width: 1, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: input.count, height: 1, depth: 1))
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        if let reason = Self.commandBufferFailure(status: commands.status, error: commands.error, label: "probe") {
            throw RenderError.deviceLost(reason)
        }
        let output = Array(UnsafeBufferPointer(
            start: buffer.contents().bindMemory(to: Float.self, capacity: input.count), count: input.count))
        guard output == input.map({ $0 * 2 }) else {
            throw RenderError.deviceLost("probe: expected \(input.map { $0 * 2 }), got \(output)")
        }
    }

    /// Uploads `buffer` as a tiled rgba16Float surface, then evicts least recently used tiles until
    /// `residentBytes` fits `budgetBytes`. Throws `RenderError.raster` for a size the tiling rejects
    /// and `RenderError.deviceLost` when a texture cannot be made, after marking the backend failed
    /// with that reason. A texture that will not allocate means the device is out of memory: release
    /// surfaces or lower `budgetBytes`, since `recover` alone passes and the same upload fails again.
    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        let clock = withLock { tick() }
        let stored: MetalSurface
        do {
            stored = try MetalSurface(device: device, buffer: buffer, clock: clock)
        } catch RenderError.deviceLost(let reason) {
            fail(reason)
            throw RenderError.deviceLost(reason)
        }
        let id = UUID()
        withLock { surfaces[id] = stored }
        evictIfNeeded()
        return handle(id: id, width: stored.tiling.width, height: stored.tiling.height)
    }

    /// Downloads a surface's pixels as Float32 (evicted tiles come from their shadows) and marks
    /// every tile of it used. Throws `RenderError.surfaceMismatch` for a surface this backend does
    /// not hold and `RenderError.raster` when a value cannot be stored.
    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        try withLock {
            let stored = try lookup(surface)
            stored.touch(tick())
            return try stored.read()
        }
    }

    /// Frees a surface's textures; an unknown or already released id is a no-op.
    public func release(_ surface: RenderSurface) { withLock { surfaces[surface.id] = nil } }

    /// Display encode through the DisplayTransfer tables (MB-3): see MetalBackend+Display.swift.
    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try encodeDisplay(s, colorSpace: colorSpace)
    }
    /// Composite in place: `.normal` MB-4, the separable modes MB-5, opaque rows blitted MB-6, see
    /// MetalBackend+Composite.swift, +BlendSeparable.swift and +OpaqueRows.swift. Non-separable modes throw `unsupported(.blendNonSeparable)`.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        guard RenderOp(compositing: mode) != .blendNonSeparable else { throw RenderError.unsupported(.blendNonSeparable) }
        try compositeInPlace(s, onto: b, x: x, y: y, mode: mode, opacity: opacity)
    }
    /// Crop as blits: MB-7 (MetalBackend+Transform.swift). An invalid rectangle throws the CPU's error.
    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try transformed(s, blit: true) { try TileMap.crop($0, x: x, y: y, width: width, height: height) }
    }
    /// Quarter turns through the rotate kernel: MB-7 (MetalBackend+Transform.swift).
    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        try transformed(s, blit: false) { TileMap.turn($0, turn) }
    }
    /// Bilinear and lanczos3 as two separable passes: MB-8 (MetalBackend+Resample.swift). A bad size throws the CPU's error.
    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        try resample(s, width: width, height: height, filter: filter)
    }
    /// Two-pass gaussian blur: MB-11 (MetalBackend+Blur.swift); `.blur` joins `supports` with MB-12.
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        try blur(s, sigma: sigma)
    }
    /// Unsharp mask over the blur: MB-12. Throws `unsupported(.blur)`.
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double,
                            threshold: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    /// Tone adjustments: exposure, levels and curves (MB-13, MetalBackend+Adjust.swift); the develop
    /// sliders throw `unsupported(.adjust)` until MB-14, which also enables `.adjust` in `supports`.
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try adjust(s, adjustment)
    }
    /// Clone through a mask: MB-15. Throws `unsupported(.retouch)`.
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        throw RenderError.unsupported(.retouch)
    }

    /// The one place a `RenderSurface` is built, so a change to its init touches one line.
    func handle(id: UUID, width: Int, height: Int) -> RenderSurface {
        RenderSurface(id: id, width: width, height: height, backend: name)
    }

    /// The stored surface behind `surface`; call with the lock held. Throws
    /// `RenderError.surfaceMismatch` for another backend's name, an id not held (never made, or released),
    /// or a handle whose width and height differ from the stored tiling, the same checks as `SurfaceStore`.
    func lookup(_ surface: RenderSurface) throws -> MetalSurface {
        guard surface.backend == name, let stored = surfaces[surface.id],
              stored.tiling.width == surface.width, stored.tiling.height == surface.height else {
            throw RenderError.surfaceMismatch
        }
        return stored
    }

    /// A command queue on `device`, for init and `recover`. Throws `RenderError.deviceLost` on nil.
    private static func makeQueue(on device: any MTLDevice) throws -> any MTLCommandQueue {
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.deviceLost("no command queue on \(device.name)")
        }
        return queue
    }

    /// The next use-clock value, for `lastUse` stamps; call with the lock held. Wraps at `UInt64.max`.
    func tick() -> UInt64 { useClock &+= 1; return useClock }

    /// Runs `body` with the backend's lock held. The lock is not recursive: `body` must not call
    /// `withLock`, `withCapabilities`, `fail`, `recover`, `probe`, `evictIfNeeded` or a public property.
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
#endif
