// MetalPipelines.swift: the backend's compute pipeline cache (metal-backend MB-2). Shader
// source is MSL in Swift string constants compiled at runtime with `makeLibrary(source:)`,
// so no `.metal` file or resource bundle is needed; the compiled pipelines go into an
// `MTLBinaryArchive` serialised at `cacheURL`, so a later launch loads them without the
// back-end compile. Invariants: every state in `states` was made on `device`; `loadCount`
// counts pipelines the archive already held and `compileCount` those built from source;
// a cache that cannot be opened, written or extended is dropped or noted in
// `lastCacheError`, never thrown: the archive is an optimisation. Callers hold the
// backend's lock: nothing here is Sendable or synchronised.
#if canImport(Metal)
import CoreRender
import Foundation
import Metal

/// The compute pipelines of one `MetalBackend`, keyed by `PipelineKey`, backed by a binary
/// archive. Internal: the backend owns one and calls it with its lock held.
final class MetalPipelines {
    /// The key of the health probe kernel: `display_probe` in `probeSource`.
    static let probeKey = PipelineKey(op: .display, variant: "probe")

    /// The health probe: doubles each float of buffer 0 in place; `probe()` checks the result.
    static let probeSource = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void display_probe(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        out[id] = out[id] * 2.0f;
    }
    """

    /// Pipelines built from source since init (a cold cache or a key the archive lacks).
    private(set) var compileCount = 0
    /// Pipelines the archive already held: no back-end compile was needed.
    private(set) var loadCount = 0
    /// Why the last archive write or add failed, nil while the cache is working.
    private(set) var lastCacheError: String?

    private let device: any MTLDevice
    private let cacheURL: URL?
    private let archive: any MTLBinaryArchive
    private var states: [PipelineKey: any MTLComputePipelineState] = [:]

    /// Opens the archive at `cacheURL` when a file is there; a file Metal rejects (corrupt or
    /// from another GPU or OS) is removed and an empty archive starts over. A nil `cacheURL`
    /// keeps an in-memory archive only. Throws `RenderError.deviceLost` when the device
    /// gives no archive at all.
    init(device: any MTLDevice, cacheURL: URL?) throws {
        self.device = device
        self.cacheURL = cacheURL
        let files = FileManager.default
        if let url = cacheURL, files.fileExists(atPath: url.path) {
            let descriptor = MTLBinaryArchiveDescriptor()
            descriptor.url = url
            if let opened = try? device.makeBinaryArchive(descriptor: descriptor) {
                archive = opened
                return
            }
            try? files.removeItem(at: url)
        } else if let url = cacheURL {
            try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        do {
            archive = try device.makeBinaryArchive(descriptor: MTLBinaryArchiveDescriptor())
        } catch {
            throw RenderError.deviceLost("no binary archive on \(device.name): \(error)")
        }
    }

    /// The pipeline for `key`, compiling `source` (MSL holding `key.functionName`) on the first
    /// request: taken from `states`, else from the archive (`loadCount`), else compiled and added
    /// to the archive and the file at `cacheURL` (`compileCount`). Throws `RenderError.deviceLost`
    /// when `source` has no kernel named `key.functionName`, and Metal's own error when the
    /// source does not compile or the pipeline cannot be made.
    func pipeline(for key: PipelineKey, source: String) throws -> any MTLComputePipelineState {
        if let state = states[key] { return state }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: key.functionName) else {
            throw RenderError.deviceLost("no kernel '\(key.functionName)' in the \(key.op.rawValue) library")
        }
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = function
        descriptor.binaryArchives = [archive]
        let state: any MTLComputePipelineState
        if let held = try? device.makeComputePipelineState(
            descriptor: descriptor, options: [.failOnBinaryArchiveMiss], reflection: nil) {
            state = held
            loadCount += 1
        } else {
            state = try device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
            compileCount += 1
            store(descriptor)
        }
        states[key] = state
        return state
    }

    /// Adds a compiled descriptor to the archive and rewrites the file at `cacheURL`. A failure
    /// goes to `lastCacheError`: the pipeline is already usable, the cache is only a speed-up.
    private func store(_ descriptor: MTLComputePipelineDescriptor) {
        do {
            try archive.addComputePipelineFunctions(descriptor: descriptor)
            lastCacheError = nil
        } catch {
            lastCacheError = "pipeline cache add failed: \(error)"
            return
        }
        guard let url = cacheURL else { return }
        do {
            try archive.serialize(to: url)
        } catch {
            lastCacheError = "pipeline cache write failed: \(error)"
        }
    }
}
#endif
