// RenderDispatcherTests.swift: render-backend RB-5's acceptance. RenderDispatcher
// routes by support and health, keeps the last fallback, records none without a
// preferred backend, moves surfaces between backends, and gives the direct CPU
// result whenever it falls back. Each pixel check expects success and compares
// the pixels with a fresh CPUBackend running the same op.
import CoreColor
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

/// A fresh CPU backend's composite of `source` onto `backdrop`.
private func directComposite(_ source: PixelBuffer, onto backdrop: PixelBuffer, mode: BlendMode) throws -> PixelBuffer {
    let cpu = CPUBackend()
    var b = try cpu.surface(backdrop)
    try cpu.composite(cpu.surface(source), onto: &b, x: 1, y: -1, mode: mode, opacity: 0.37)
    return try cpu.read(b)
}

private let unsupported = RenderDispatcher.reasonUnsupported
private let unhealthy = RenderDispatcher.reasonUnhealthy

private func fallback(_ d: RenderDispatcher) -> String? {
    d.lastFallback.map { "\($0.op.rawValue) \($0.reason)" }
}

@Suite struct RenderDispatcherTests {
    @Test func aBlurOnAFakePreferringCompositeGoesToTheCPU() throws {
        let fake = FakeBackend(supports: [.composite])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let buffer = try seededBuffer(width: 5, height: 4, seed: 1)
        #expect(d.backend(for: .composite).name == "fake")
        #expect(d.lastFallback == nil)
        #expect(d.backend(for: .blur).name == "cpu")
        #expect(d.lastFallback?.op == .blur && d.lastFallback?.reason == unsupported)
        let s = try fake.surface(buffer)
        let cpu = CPUBackend()
        #expect(try d.read(d.gaussianBlur(s, sigma: 1.5)) == cpu.read(cpu.gaussianBlur(cpu.surface(buffer), sigma: 1.5)))
        #expect(!fake.calls.contains(.op(.blur)))
        #expect(fake.calls.contains(.read(s)))
    }

    @Test func anUnhealthyFakeRoutesEverythingToTheCPU() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases), healthy: false)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        for op in RenderOp.allCases {
            #expect(d.backend(for: op).name == "cpu")
            #expect(d.lastFallback?.op == op && d.lastFallback?.reason == unhealthy)
        }
        let source = try seededBuffer(width: 4, height: 3, seed: 2)
        let backdrop = try seededBuffer(width: 6, height: 5, seed: 3)
        #expect(try d.surface(source).backend == "cpu")
        var b = try fake.surface(backdrop)
        try d.composite(fake.surface(source), onto: &b, x: 1, y: -1, mode: .multiply, opacity: 0.37)
        #expect(b.backend == "cpu")
        #expect(try d.read(b) == directComposite(source, onto: backdrop, mode: .multiply))
        #expect(try d.display(fake.surface(source), colorSpace: .displayP3) == source.rgba8(colorSpace: .displayP3))
        #expect(fallback(d) == "display \(unhealthy)")
        #expect(!fake.calls.contains { if case .op = $0 { return true } else { return false } })
    }

    @Test func noPreferredBackendRoutesToTheCPUWithNoFallback() throws {
        let d = RenderDispatcher(preferred: nil, fallback: CPUBackend())
        for op in RenderOp.allCases { #expect(d.backend(for: op).name == "cpu") }
        let source = try seededBuffer(width: 4, height: 3, seed: 4)
        let backdrop = try seededBuffer(width: 6, height: 5, seed: 5)
        var b = try d.surface(backdrop)
        #expect(b.backend == "cpu")
        try d.composite(d.surface(source), onto: &b, x: 1, y: -1, mode: .luminosity, opacity: 0.37)
        #expect(try d.read(b) == directComposite(source, onto: backdrop, mode: .luminosity))
        #expect(d.lastFallback == nil)
    }

    @Test func aFakeSurfaceHandedToACPUOpIsReUploaded() throws {
        let fake = FakeBackend(supports: [.blur])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let source = try seededBuffer(width: 4, height: 3, seed: 6)
        let backdrop = try seededBuffer(width: 6, height: 5, seed: 7)
        let s = try d.surface(source)
        var b = try d.surface(backdrop)
        let original = b
        #expect(s.backend == "fake" && b.backend == "fake")
        try d.composite(s, onto: &b, x: 1, y: -1, mode: .normal, opacity: 0.37)
        #expect(b.backend == "cpu" && b.width == 6 && b.height == 5)
        #expect(try d.read(b) == directComposite(source, onto: backdrop, mode: .normal))
        #expect(fallback(d) == "composite \(unsupported)")
        #expect(fake.calls.contains(.read(s)) && fake.calls.contains(.read(original)))
        #expect(fake.calls.last == .release(original))
        #expect(throws: RenderError.surfaceMismatch) { try fake.read(original) }
        #expect(try fake.read(s) == source)
    }

    @Test func theLastFallbackIsKeptUntilTheNextOne() throws {
        let fake = FakeBackend(supports: [.composite])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(try seededBuffer(width: 3, height: 3, seed: 8))
        var b = try d.surface(try seededBuffer(width: 3, height: 3, seed: 9))
        let copy = d
        _ = d.backend(for: .blur)
        try d.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1)
        #expect(fake.calls.contains(.op(.composite)) && b.backend == "fake")
        #expect(fallback(d) == "blur \(unsupported)")
        _ = try d.display(s, colorSpace: .sRGB)
        #expect(fallback(d) == "display \(unsupported)")
        #expect(fallback(copy) == "display \(unsupported)")
    }

    @Test func aCPUSurfaceHandedToThePreferredBackendIsUploadedThenReleased() throws {
        let fake = FakeBackend(supports: [.transform])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let buffer = try seededBuffer(width: 5, height: 2, seed: 10)
        let s = try d.fallback.surface(buffer)
        let r = try d.rotated(s, .degrees90)
        let calls = fake.calls
        #expect(r.backend == "fake")
        #expect(try d.read(r) == buffer.rotated(.degrees90))
        #expect(d.lastFallback == nil)
        #expect(calls.count == 3 && calls.first == .surface(width: 5, height: 2) && calls[1] == .op(.transform))
        if case .release(let uploaded)? = calls.last {
            #expect(uploaded.backend == "fake" && uploaded != r)
        } else {
            Issue.record("the uploaded copy was not released: \(calls)")
        }
        #expect(try d.read(s) == buffer)
    }

    @Test func aFailedCompositeReleasesTheMovedBackdropAndKeepsTheHandle() throws {
        let fake = FakeBackend(supports: [.composite])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let backdrop = try seededBuffer(width: 3, height: 2, seed: 11)
        var b = try d.fallback.surface(backdrop)
        let original = b
        let stranger = try FakeBackend(name: "other", supports: []).surface(backdrop)
        #expect(throws: RenderError.surfaceMismatch) {
            try d.composite(stranger, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1)
        }
        #expect(b == original)
        #expect(try d.read(b) == backdrop)
        if case .release(let uploaded)? = fake.calls.last {
            #expect(uploaded.backend == "fake")
        } else {
            Issue.record("the moved backdrop was not released: \(fake.calls)")
        }
    }

    @Test func aSurfaceNeitherBackendMadeIsAMismatch() throws {
        let d = RenderDispatcher(preferred: nil, fallback: CPUBackend())
        let stranger = try FakeBackend(name: "other", supports: []).surface(try PixelBuffer(width: 2, height: 2))
        #expect(throws: RenderError.surfaceMismatch) { try d.read(stranger) }
        #expect(throws: RenderError.surfaceMismatch) { try d.display(stranger, colorSpace: .sRGB) }
        d.release(stranger)
    }
}
