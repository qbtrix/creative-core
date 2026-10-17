// MetalPipelinesTests.swift: the pipeline memo and the health wiring on a real device (MB-2):
// a key compiles once and its memo is reused, another variant compiles again, a bad variant is
// rejected, a file at `cacheURL` is never touched, a probe or command-buffer failure fails the
// backend, `fail` empties `supports` and `recover` restores, and the tile storage mode follows
// unified memory. Device-gated; compiled out on Linux.
#if canImport(Metal)
import CoreRender
import CoreRenderMetal
import Foundation
import Metal
import Testing

@Suite struct MetalPipelinesTests {
    /// Two composite kernels for `preparePipeline`: variants `a` and `b`.
    private static let twoKernels = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void composite_a(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) { out[id] = 0.0f; }
    kernel void composite_b(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) { out[id] = 1.0f; }
    """

    /// A probe kernel that triples instead of doubling, so the output check fails.
    private static let wrongProbe = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void display_probe(device float *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        out[id] = out[id] * 3.0f;
    }
    """

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func firstRequestCompilesOnceAndTheMemoIsReused() throws {
        let backend = try MetalBackend.onDefaultDevice()
        #expect(backend.pipelineCompileCount == 0 && backend.pipelineLoadCount == 0)
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 0)
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 1, "the second probe reuses the memo")
        #expect(backend.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func anotherVariantCompilesAgainAndABadVariantThrows() throws {
        let backend = try MetalBackend.onDefaultDevice()
        try backend.preparePipeline(op: .composite, variant: "a", source: Self.twoKernels)
        try backend.preparePipeline(op: .composite, variant: "a", source: Self.twoKernels)
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 1)
        try backend.preparePipeline(op: .composite, variant: "b", source: Self.twoKernels)
        #expect(backend.pipelineCompileCount == 2 && backend.pipelineLoadCount == 1)
        #expect(throws: RenderError.raster("pipeline variant 'a-b' must be [A-Za-z0-9_]")) {
            try backend.preparePipeline(op: .composite, variant: "a-b", source: Self.twoKernels)
        }
        #expect(backend.pipelineCompileCount == 2 && backend.isHealthy, "a rejected variant compiles nothing")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aFileAtCacheURLIsLeftUntouched() throws {
        guard let device = MetalBackend.defaultDevice else { throw RenderError.deviceLost("no default device") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipelines-\(UUID().uuidString).metallib")
        defer { try? FileManager.default.removeItem(at: url) }
        let junk = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        try junk.write(to: url)
        let backend = try MetalBackend(device: device, cacheURL: url)
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.isHealthy, "pipelines still build")
        #expect(try Data(contentsOf: url) == junk, "the file is byte-for-byte as it was")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func failEmptiesSupportsAndRecoverRestores() throws {
        let backend = try MetalBackend.onDefaultDevice()
        // No op family is enabled yet, so `supports` is empty either way: the oracle is health and lastError.
        #expect(backend.isHealthy && backend.capabilities == MetalCapabilities(), "healthy before the failure")
        backend.fail("mock")
        #expect(!backend.isHealthy && backend.supports.isEmpty)
        #expect(backend.capabilities.lastError == "mock" && !backend.capabilities.healthy)
        #expect(backend.capabilities.supported.isEmpty, "supported is kept as it was")
        try backend.recover()
        #expect(backend.isHealthy && backend.capabilities == MetalCapabilities(), "recover restores the fresh state")
        try backend.probe()
        #expect(backend.isHealthy, "the new queue runs the probe")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aFailedProbeLeavesTheBackendUnhealthy() throws {
        let backend = try MetalBackend.onDefaultDevice()
        #expect(throws: RenderError.deviceLost("probe: expected [2.0, 4.0, 6.0, 8.0], got [3.0, 6.0, 9.0, 12.0]")) {
            try backend.probe(source: Self.wrongProbe)
        }
        #expect(!backend.isHealthy && backend.supports.isEmpty)
        #expect(backend.capabilities.lastError?.hasPrefix("probe: expected") == true)
        try backend.recover()
        try backend.probe()
        #expect(backend.isHealthy, "the custom source was never memoised: the real probe passes")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aCommandBufferErrorFailsTheBackend() throws {
        let backend = try MetalBackend.onDefaultDevice()
        try backend.recordCompletion(status: .completed, error: nil, label: "upload")
        #expect(backend.isHealthy, "a clean completion is not a failure")
        #expect(throws: RenderError.deviceLost("read: command buffer ended with status \(MTLCommandBufferStatus.error.rawValue)")) {
            try backend.recordCompletion(status: .error, error: nil, label: "read")
        }
        #expect(!backend.isHealthy && backend.supports.isEmpty)
        try backend.recover()
        #expect(throws: RenderError.self) {
            try backend.recordCompletion(status: .completed, error: RenderError.deviceLost("gone"), label: "probe")
        }
        #expect(!backend.isHealthy && backend.capabilities.lastError?.hasPrefix("probe: command buffer failed") == true)
    }

    @Test func tileStorageFollowsUnifiedMemory() {
        #expect(MetalBackend.tileStorageMode(unifiedMemory: true) == .shared)
        #expect(MetalBackend.tileStorageMode(unifiedMemory: false) == .managed)
    }
}
#endif
