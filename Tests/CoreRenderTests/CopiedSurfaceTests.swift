// CopiedSurfaceTests.swift: `copied(_:)` on the CPU backend, the fake and the dispatcher. A copy holds
// the source's pixels under a new id and outlives the source; the fake records one `.copied` call and
// no upload; the dispatcher copies on the backend that already holds the surface, uploads instead of
// copying when it lives on the other one (the upload is the copy), and goes to the CPU while the
// preferred backend is unhealthy.
import CoreRaster
import CoreRender
import Testing

private func pixels() throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: 5, height: 3, fill: RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5))
    try buffer.setPixel(x: 4, y: 2, RGBA(r: 1, g: 0, b: 0, a: 1))
    return buffer
}

private func uploads(_ fake: FakeBackend) -> Int {
    fake.calls.filter { if case .surface = $0 { true } else { false } }.count
}

@Suite struct CopiedSurfaceTests {
    @Test func theCPUCopyHoldsTheSourcePixelsUnderANewIDAndOutlivesIt() throws {
        let cpu = CPUBackend()
        let source = try cpu.surface(pixels())
        let copy = try cpu.copied(source)
        #expect(copy != source)
        #expect(try cpu.read(copy) == pixels())
        cpu.release(source)
        #expect(try cpu.read(copy) == pixels())
    }

    @Test func theFakeRecordsOneCopiedCallAndNoUpload() throws {
        let fake = FakeBackend(supports: [])
        let source = try fake.surface(pixels())
        let copy = try fake.copied(source)
        #expect(fake.calls.last == .copied(source))
        #expect(uploads(fake) == 1)
        #expect(try fake.read(copy) == pixels())
    }

    @Test func theDispatcherCopiesWhereTheSurfaceLivesAndUploadsAcross() throws {
        let fake = FakeBackend(name: "gpu", supports: [])
        let cpu = CPUBackend()
        let dispatcher = RenderDispatcher(preferred: fake, fallback: cpu)
        let onGPU = try dispatcher.surface(pixels())
        let copy = try dispatcher.copied(onGPU)
        #expect(fake.calls.contains(.copied(onGPU)) && uploads(fake) == 1)
        #expect(copy.backend == "gpu" && copy != onGPU)
        let onCPU = try cpu.surface(pixels())
        let moved = try dispatcher.copied(onCPU)
        #expect(moved.backend == "gpu" && uploads(fake) == 2)
        #expect(fake.calls.filter { if case .copied = $0 { true } else { false } }.count == 1, "the upload is the copy")
        #expect(try dispatcher.read(moved) == pixels())
    }

    @Test func anUnhealthyPreferredBackendCopiesOnTheCPU() throws {
        let fake = FakeBackend(name: "gpu", supports: [], healthy: false)
        let dispatcher = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let onCPU = try dispatcher.surface(pixels())
        let copy = try dispatcher.copied(onCPU)
        #expect(copy.backend == dispatcher.fallback.name && fake.calls.isEmpty)
        #expect(try dispatcher.read(copy) == pixels())
    }
}
