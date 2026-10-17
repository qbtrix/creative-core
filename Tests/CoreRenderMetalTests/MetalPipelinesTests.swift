// MetalPipelinesTests.swift: the pipeline memo and the health wiring on a real device (MB-2):
// a key compiles once and its memo is reused, another variant compiles again, a bad variant is
// rejected, a missing kernel is caller input (not a device loss), a file at `cacheURL` is never
// touched, a probe or command-buffer failure fails the backend, `fail` empties `supports`, `recover`
// restores only once its probe passes, a caller's `display_probe` never replaces the probe, a
// caller's `display_encode` never replaces the display kernel, `display`, `composite`, crop, rotate,
// resample, adjust, blur and unsharp refuse while unhealthy (`unsupported` of their family),
// and the tile storage mode follows unified memory. Device-gated; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
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
        let fresh = backend.capabilities
        #expect(backend.isHealthy && fresh.lastError == nil && !fresh.supported.isEmpty, "healthy before the failure")
        backend.fail("mock")
        #expect(!backend.isHealthy && backend.supports.isEmpty)
        #expect(backend.capabilities.lastError == "mock" && !backend.capabilities.healthy)
        #expect(backend.capabilities.supported == fresh.supported, "supported is kept as it was")
        try backend.recover()
        #expect(backend.isHealthy && backend.capabilities == fresh, "recover restores the fresh state")
        #expect(backend.pipelineCompileCount == 1, "recover ran the probe before reporting healthy")
        try backend.probe()
        #expect(backend.isHealthy && backend.pipelineLoadCount == 1, "the new queue runs the probe")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func recoverStaysUnhealthyWhenItsProbeFails() throws {
        let backend = try MetalBackend.onDefaultDevice()
        backend.fail("mock")
        #expect(throws: RenderError.deviceLost("probe: expected [2.0, 4.0, 6.0, 8.0], got [3.0, 6.0, 9.0, 12.0]")) {
            try backend.recover(probeSource: Self.wrongProbe)
        }
        #expect(!backend.isHealthy && backend.supports.isEmpty, "a failed probe keeps the backend failed")
        #expect(backend.capabilities.lastError?.hasPrefix("probe: expected") == true)
        try backend.recover()
        #expect(backend.isHealthy && backend.capabilities.lastError == nil)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aMissingKernelIsCallerInputNotADeviceLoss() throws {
        let backend = try MetalBackend.onDefaultDevice()
        #expect(throws: RenderError.raster("no kernel 'composite_c' in the source for composite")) {
            try backend.preparePipeline(op: .composite, variant: "c", source: Self.twoKernels)
        }
        #expect(backend.isHealthy && backend.pipelineCompileCount == 0, "nothing compiled, nothing failed")
        #expect(throws: RenderError.deviceLost("probe: no kernel 'display_probe' in the source for display")) {
            try backend.probe(source: Self.twoKernels)
        }
        #expect(backend.capabilities.lastError == "probe: no kernel 'display_probe' in the source for display")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aCallersDisplayProbeNeverReplacesTheHealthProbe() throws {
        let backend = try MetalBackend.onDefaultDevice()
        try backend.preparePipeline(op: .display, variant: "probe", source: Self.wrongProbe)
        try backend.probe()
        #expect(backend.isHealthy, "the probe ran its own kernel, not the caller's")
        #expect(backend.pipelineCompileCount == 2 && backend.pipelineLoadCount == 0, "two separate memos")
    }

    /// A `display_encode` that writes 255 to every byte, under the display kernel's own key.
    private static let whiteEncode = """
    #include <metal_stdlib>
    using namespace metal;
    kernel void display_encode(device uchar4 *out [[buffer(0)]], uint id [[thread_position_in_grid]]) {
        out[id] = uchar4(255);
    }
    """

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func aCallersDisplayEncodeNeverReplacesTheDisplayKernel() throws {
        let backend = try MetalBackend.onDefaultDevice()
        try backend.preparePipeline(op: .display, variant: "encode", source: Self.whiteEncode)
        let image = try PixelBuffer.seeded(width: 9, height: 7, seed: 0xE4C0)
        let cpu = CPUBackend()
        let expected = try cpu.display(cpu.surface(image), colorSpace: .sRGB)
        let got = try backend.display(backend.surface(image), colorSpace: .sRGB)
        let worst = zip(got, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(got.count == expected.count && worst <= Int(ParityTolerance.standard.bytes), "worst \(worst)")
        #expect(backend.pipelineCompileCount == 2, "the caller's kernel and the display kernel, apart")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func displayRefusesWhileUnhealthy() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let surface = try backend.surface(PixelBuffer.seeded(width: 4, height: 3, seed: 7))
        backend.fail("mock")
        #expect(throws: RenderError.unsupported(.display)) { try backend.display(surface, colorSpace: .sRGB) }
        #expect(backend.pipelineCompileCount == 0, "no GPU work for an unhealthy backend")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func compositeRefusesWhileUnhealthy() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let source = try backend.surface(PixelBuffer.seeded(width: 4, height: 3, seed: 8))
        var backdrop = try backend.surface(PixelBuffer.seeded(width: 5, height: 4, seed: 9))
        let held = try backend.read(backdrop)
        backend.fail("x")
        #expect(throws: RenderError.unsupported(.composite)) {
            try backend.composite(source, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1)
        }
        #expect(throws: RenderError.unsupported(.blendSeparable)) {
            try backend.composite(source, onto: &backdrop, x: 0, y: 0, mode: .multiply, opacity: 1)
        }
        #expect(try backend.read(backdrop) == held && backend.pipelineCompileCount == 0, "no GPU work for an unhealthy backend")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func transformAndResampleRefuseWhileUnhealthy() throws {
        let backend = try MetalBackend.onDefaultDevice()
        let surface = try backend.surface(PixelBuffer.seeded(width: 4, height: 3, seed: 7))
        backend.fail("mock")
        #expect(throws: RenderError.unsupported(.transform)) { try backend.cropped(surface, x: 0, y: 0, width: 2, height: 2) }
        #expect(throws: RenderError.unsupported(.transform)) { try backend.rotated(surface, .degrees90) }
        #expect(throws: RenderError.unsupported(.resample)) { try backend.resampled(surface, width: 8, height: 6, filter: .bilinear) }
        #expect(throws: RenderError.unsupported(.adjust)) { try backend.adjusted(surface, .contrast(40)) }
        #expect(throws: RenderError.unsupported(.blur)) { try backend.gaussianBlur(surface, sigma: 1) }
        #expect(throws: RenderError.unsupported(.blur)) { try backend.unsharpMask(surface, amount: 1, sigma: 1, threshold: 0) }
        #expect(backend.pipelineCompileCount == 0, "no GPU work for an unhealthy backend")
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
        #expect(backend.isHealthy && backend.pipelineCompileCount == 2, "recover compiled and ran the real probe")
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
