// MetalPipelines.swift: the backend's compute pipeline cache (metal-backend MB-2). Shader
// source is MSL in Swift string constants compiled at runtime with `makeLibrary(source:)`,
// so no `.metal` file or resource bundle is needed. Each pipeline is compiled once per
// `PipelineKey` and memoised in `states`; later requests for the key reuse it, and Metal's
// own shader cache speeds the compile across launches. Nothing is read from or written to
// disk. Invariants: every state in `states` and `probeState` was made on `device`; the
// health probe's pipeline lives only in `probeState`, so no caller key can replace it;
// `compileCount` counts pipelines built from source and `loadCount` requests answered from
// a memo; a failed compile memoises nothing. Callers hold the backend's lock: nothing here is Sendable or
// synchronised.
#if canImport(Metal)
import CoreRender
import Metal

/// The compute pipelines of one `MetalBackend`, keyed by `PipelineKey` and memoised in
/// process. Internal: the backend owns one and calls it with its lock held.
final class MetalPipelines {
    /// The key of the health probe kernel: `display_probe` in `probeSource`. Its pipeline is
    /// memoised in `probeState`, apart from `states`, so `preparePipeline(op: .display, variant: "probe")`
    /// neither replaces the probe nor gets it.
    static let probeKey = PipelineKey(op: .display, variant: "probe")

    /// The health probe: doubles each float of buffer 0 in place; `probe()` checks the result.
    static let probeSource = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void display_probe(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        out[id] = out[id] * 2.0f;
    }
    """

    /// Pipelines built from source since init.
    private(set) var compileCount = 0
    /// Requests answered from the memo without a compile.
    private(set) var loadCount = 0

    private let device: any MTLDevice
    private var states: [PipelineKey: any MTLComputePipelineState] = [:]
    /// The health probe's pipeline, compiled from `probeSource` on first use.
    private var probeState: (any MTLComputePipelineState)?

    init(device: any MTLDevice) {
        self.device = device
    }

    /// The pipeline for `key`: the memoised one (`loadCount`), else `source` compiled and
    /// memoised (`compileCount`). The memo is keyed by `key` alone, so a later `source` for
    /// a key already held is not compiled. Throws as `compile` does, memoising nothing.
    func pipeline(for key: PipelineKey, source: String) throws -> any MTLComputePipelineState {
        if let state = states[key] {
            loadCount += 1
            return state
        }
        let state = try compile(key, source: source)
        states[key] = state
        return state
    }

    /// The health probe's pipeline: `probeState` (`loadCount`), else `probeSource` compiled
    /// into it (`compileCount`). Throws as `compile` does, memoising nothing.
    func probePipeline() throws -> any MTLComputePipelineState {
        if let state = probeState {
            loadCount += 1
            return state
        }
        let state = try compile(Self.probeKey, source: Self.probeSource)
        probeState = state
        return state
    }

    /// Builds `source`'s kernel `key.functionName` without touching the memo and counts it in
    /// `compileCount`. Throws as `build` does.
    func compile(_ key: PipelineKey, source: String) throws -> any MTLComputePipelineState {
        let state = try Self.build(key, source: source, on: device)
        noteCompile()
        return state
    }

    /// Counts a pipeline built with `build` outside the lock (a custom probe source).
    func noteCompile() { compileCount += 1 }

    /// Compiles `source` on `device` and builds the pipeline of its kernel `key.functionName`.
    /// Touches no state, so it runs with the backend's lock free. Throws `RenderError.raster`
    /// when `source` has no kernel of that name (caller input, not a device loss), and Metal's
    /// own error when the source does not compile or the pipeline cannot be made.
    static func build(_ key: PipelineKey, source: String, on device: any MTLDevice) throws -> any MTLComputePipelineState {
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: key.functionName) else {
            throw RenderError.raster("no kernel '\(key.functionName)' in the source for \(key.op.rawValue)")
        }
        return try device.makeComputePipelineState(function: function)
    }
}
#endif
