// MetalBackend.swift: the Metal RenderBackend (metal-backend MB-1, MB-2): a device, its
// command queue, the capability state, the pipeline cache and the live MetalSurfaces keyed
// by RenderSurface id. Metal's protocols are not Sendable, so the class is @unchecked
// Sendable and every access to mutable state goes through `withLock` (internal, so the
// extension files of later slices share it; `fail` and `recover` take it themselves, so
// never call them with it held). Invariants: `supports` is empty while not healthy,
// `residentBytes` sums the live surfaces' textures, a surface this backend did not make
// throws `surfaceMismatch`, every op throws `unsupported` until its slice, and a probe that
// fails leaves the backend unhealthy with the reason in `capabilities.lastError`.
#if canImport(Metal)
import CoreColor
import CoreRaster
import CoreRender
import Foundation
import Metal

/// The Metal `RenderBackend`: tiled rgba16Float surfaces on one GPU. Every op throws
/// `RenderError.unsupported` until its slice lands; `supports` tells the dispatcher which do not.
public final class MetalBackend: RenderBackend, @unchecked Sendable {
    /// The system's default GPU, or nil without one; tests gate on `.enabled(if: defaultDevice != nil)`.
    public static var defaultDevice: (any MTLDevice)? { MTLCreateSystemDefaultDevice() }

    /// The GPU this backend draws on.
    public let device: any MTLDevice
    /// Where the pipeline binary archive lives; nil keeps the compiled pipelines in memory only.
    public let cacheURL: URL?
    /// The queue every slice's command buffers go through; `recover` replaces it. Read under the lock.
    private(set) var commandQueue: any MTLCommandQueue
    /// The compute pipelines, compiled on first use and cached at `cacheURL`. Call under the lock.
    let pipelines: MetalPipelines

    private let lock = NSLock()
    var state = MetalCapabilities()
    var surfaces: [UUID: MetalSurface] = [:]

    /// Opens a backend on `device`. Throws `RenderError.deviceLost` when it gives no command
    /// queue or no binary archive; a cache file at `cacheURL` that Metal rejects is replaced, not thrown.
    public init(device: any MTLDevice, cacheURL: URL?) throws {
        self.device = device
        self.commandQueue = try Self.makeQueue(on: device)
        self.pipelines = try MetalPipelines(device: device, cacheURL: cacheURL)
        self.cacheURL = cacheURL
    }

    /// "Metal (<device name>)": the status note's text and every surface's `backend`.
    public var name: String { "Metal (\(device.name))" }
    /// The op families this backend has proven, plus its health and last error.
    public var capabilities: MetalCapabilities { withLock { state } }
    /// `capabilities.supported` while healthy, else empty: the dispatcher drops to CPU on a device loss.
    public var supports: Set<RenderOp> { withLock { state.healthy ? state.supported : [] } }
    /// False after a command buffer error or a lost device, until `recover`.
    public var isHealthy: Bool { withLock { state.healthy } }
    /// Bytes of tile textures held by the live surfaces (8 per pixel).
    public var residentBytes: Int { withLock { surfaces.values.reduce(0) { $0 + $1.residentBytes } } }
    /// Pipelines built by compiling shader source since init: 0 after a warm start from `cacheURL`.
    public var pipelineCompileCount: Int { withLock { pipelines.compileCount } }
    /// Pipelines taken from the binary archive without a compile.
    public var pipelineLoadCount: Int { withLock { pipelines.loadCount } }

    /// Changes the capability state under the lock (a slice enables its family; `fail` and `recover`).
    func withCapabilities<R>(_ body: (inout MetalCapabilities) throws -> R) rethrows -> R {
        try withLock { try body(&state) }
    }

    /// Records a device loss or command-buffer error: `isHealthy` turns false, `supports` empty and
    /// `capabilities.lastError` holds `reason`, until `recover`. `capabilities.supported` is kept.
    public func fail(_ reason: String) { withCapabilities { $0.fail(reason) } }

    /// Makes a new command queue on `device` and clears the failure: `isHealthy` true, `lastError` nil.
    /// Throws `RenderError.deviceLost` when the device gives no queue, leaving the failure in place.
    public func recover() throws {
        let queue = try Self.makeQueue(on: device)
        withCapabilities { capabilities in
            commandQueue = queue
            capabilities.recover()
        }
    }

    /// Runs the probe kernel once (four floats doubled in place) and checks the result. On any
    /// failure (no command buffer, encoder or buffer, a command-buffer error, or wrong output) the
    /// backend is marked failed with the reason and `RenderError.deviceLost` carries the same
    /// reason. The dispatcher or an app calls this after a device-loss notification.
    public func probe() throws {
        do {
            try withLock { try runProbe() }
        } catch {
            let reason: String
            if case RenderError.deviceLost(let text) = error { reason = text } else { reason = "probe: \(error)" }
            fail(reason)
            throw RenderError.deviceLost(reason)
        }
    }

    /// The probe's GPU work; call with the lock held. Throws `RenderError.deviceLost("probe: ...")`.
    private func runProbe() throws {
        let pipeline = try pipelines.pipeline(for: MetalPipelines.probeKey, source: MetalPipelines.probeSource)
        let input: [Float] = [1, 2, 3, 4]
        let made = input.withUnsafeBytes { raw -> (any MTLBuffer)? in
            guard let base = raw.baseAddress else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
        guard let buffer = made else { throw RenderError.deviceLost("probe: no buffer on \(device.name)") }
        guard let commands = commandQueue.makeCommandBuffer() else {
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
        if let error = commands.error { throw RenderError.deviceLost("probe: command buffer failed: \(error)") }
        let output = Array(UnsafeBufferPointer(
            start: buffer.contents().bindMemory(to: Float.self, capacity: input.count), count: input.count))
        guard output == input.map({ $0 * 2 }) else {
            throw RenderError.deviceLost("probe: expected \(input.map { $0 * 2 }), got \(output)")
        }
    }

    /// Uploads `buffer` as a tiled rgba16Float surface. Throws `RenderError.raster` for a size the
    /// tiling rejects and `RenderError.deviceLost` when a texture cannot be made.
    public func surface(_ buffer: PixelBuffer) throws -> RenderSurface {
        let stored = try MetalSurface(device: device, buffer: buffer)
        let id = UUID()
        withLock { surfaces[id] = stored }
        return handle(id: id, width: stored.tiling.width, height: stored.tiling.height)
    }

    /// Downloads a surface's pixels as Float32. Throws `RenderError.surfaceMismatch` for a surface
    /// this backend does not hold and `RenderError.raster` when a value cannot be stored.
    public func read(_ surface: RenderSurface) throws -> PixelBuffer {
        try withLock { try lookup(surface).read() }
    }

    /// Frees a surface's textures; an unknown or already released id is a no-op.
    public func release(_ surface: RenderSurface) { withLock { surfaces[surface.id] = nil } }

    /// Display encode through the DisplayTransfer tables: MB-3. Throws `unsupported(.display)`.
    public func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        throw RenderError.unsupported(.display)
    }
    /// Composite: MB-4 (`.normal`), MB-5 to MB-10 (blend families). Throws `unsupported(.composite)`.
    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                          mode: BlendMode, opacity: Float) throws {
        throw RenderError.unsupported(.composite)
    }
    /// Crop as a blit: MB-7. Throws `unsupported(.transform)`.
    public func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }
    /// Quarter turns: MB-7. Throws `unsupported(.transform)`.
    public func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }
    /// Bilinear and lanczos3 resampling: MB-8. Throws `unsupported(.resample)`.
    public func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        throw RenderError.unsupported(.resample)
    }
    /// Two-pass gaussian blur: MB-11. Throws `unsupported(.blur)`.
    public func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    /// Unsharp mask over the blur: MB-12. Throws `unsupported(.blur)`.
    public func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double,
                            threshold: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    /// Tone adjustments: MB-13 and MB-14. Throws `unsupported(.adjust)`.
    public func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        throw RenderError.unsupported(.adjust)
    }
    /// Clone through a mask: MB-15. Throws `unsupported(.retouch)`.
    public func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        throw RenderError.unsupported(.retouch)
    }

    /// The one place a `RenderSurface` is built, so a change to its init touches one line.
    private func handle(id: UUID, width: Int, height: Int) -> RenderSurface {
        RenderSurface(id: id, width: width, height: height, backend: name)
    }

    /// The stored surface behind `surface`; call with the lock held. Throws
    /// `RenderError.surfaceMismatch` for another backend's name or an id not held (never made, or released).
    private func lookup(_ surface: RenderSurface) throws -> MetalSurface {
        guard surface.backend == name, let stored = surfaces[surface.id] else { throw RenderError.surfaceMismatch }
        return stored
    }

    /// A command queue on `device`, for init and `recover`. Throws `RenderError.deviceLost` on nil.
    private static func makeQueue(on device: any MTLDevice) throws -> any MTLCommandQueue {
        guard let queue = device.makeCommandQueue() else {
            throw RenderError.deviceLost("no command queue on \(device.name)")
        }
        return queue
    }

    /// Runs `body` with the backend's lock held. The lock is not recursive: `body` must not call
    /// `withLock`, `withCapabilities`, `fail`, `recover`, `probe` or a public property.
    func withLock<R>(_ body: () throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
#endif
