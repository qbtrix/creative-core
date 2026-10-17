// MetalPipelinesTests.swift: the pipeline cache and the health wiring on a real device (MB-2):
// a cold cache compiles and writes the archive, a warm start loads without compiling, a
// corrupt archive recompiles and rewrites, `fail` empties `supports` and `recover` restores.
// Each test owns a fresh archive path under the temporary directory. Device-gated; compiled
// out on Linux.
#if canImport(Metal)
import CoreRender
import CoreRenderMetal
import Foundation
import Testing

@Suite struct MetalPipelinesTests {
    /// A backend on the default device with its archive at `cacheURL`.
    private static func backend(cacheURL: URL?) throws -> MetalBackend {
        guard let device = MetalBackend.defaultDevice else { throw RenderError.deviceLost("no default device") }
        return try MetalBackend(device: device, cacheURL: cacheURL)
    }

    /// A path no other test writes: one archive per test run.
    private static func freshCacheURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pipelines-\(UUID().uuidString).metallib")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func coldCacheCompilesOnceAndWritesTheArchive() throws {
        let url = Self.freshCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let backend = try Self.backend(cacheURL: url)
        #expect(backend.pipelineCompileCount == 0 && backend.pipelineLoadCount == 0)
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 0)
        #expect(FileManager.default.fileExists(atPath: url.path), "the archive is written after the compile")
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1, "the second probe reuses the state")
        #expect(backend.isHealthy)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func warmStartLoadsWithoutCompiling() throws {
        let url = Self.freshCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.backend(cacheURL: url).probe()
        let warm = try Self.backend(cacheURL: url)
        try warm.probe()
        #expect(warm.pipelineCompileCount == 0 && warm.pipelineLoadCount == 1)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func corruptArchiveRecompilesAndRewrites() throws {
        let url = Self.freshCacheURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.backend(cacheURL: url).probe()
        let junk = Data((0..<64).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) })
        try junk.write(to: url)
        let backend = try Self.backend(cacheURL: url)
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 0)
        #expect(try Data(contentsOf: url) != junk, "the archive is rewritten over the junk")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func inMemoryCacheWritesNoFile() throws {
        let backend = try Self.backend(cacheURL: nil)
        try backend.probe()
        try backend.probe()
        #expect(backend.pipelineCompileCount == 1 && backend.pipelineLoadCount == 0)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func failEmptiesSupportsAndRecoverRestores() throws {
        let backend = try Self.backend(cacheURL: nil)
        backend.fail("mock")
        #expect(!backend.isHealthy && backend.supports.isEmpty)
        #expect(backend.capabilities.lastError == "mock")
        #expect(backend.capabilities.supported.isEmpty, "supported is kept as it was")
        try backend.recover()
        #expect(backend.isHealthy && backend.capabilities.lastError == nil)
        try backend.probe()
        #expect(backend.isHealthy, "the new queue runs the probe")
    }
}
#endif
