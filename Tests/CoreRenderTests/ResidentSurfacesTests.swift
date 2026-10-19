// ResidentSurfacesTests.swift: layer tiles stay on their backend between
// renders. A second render with nothing changed uploads 0 tiles, one written
// tile uploads exactly 1, equal pixels in new storage upload again (the dirty
// check is storage identity), a clear tile never uploads, prune and rebuild move
// and release surfaces, and the batched composite (default and through the
// dispatcher) gives the pixels of one composite per step. Counts come from the
// FakeBackend's `.surface` calls and `uploads`; pixels from the CPU backend.
import CoreRaster
import CoreRender
import Testing

/// A `size` x `size` tile of one opaque grey `level`.
private func tile(_ level: Float, size: Int = 4) throws -> PixelBuffer {
    try PixelBuffer(width: size, height: size, fill: RGBA(r: level, g: level, b: level, a: 1))
}

/// `tiles` synced as layer `layer`, in order.
private func sync(_ resident: ResidentSurfaces, _ layer: String, _ tiles: [PixelBuffer]) throws -> [RenderSurface?] {
    try tiles.enumerated().map { try resident.surface(ResidentKey(layer: layer, tile: $0.offset), pixels: $0.element) }
}

private func uploads(_ fake: FakeBackend) -> Int {
    fake.calls.filter { if case .surface = $0 { true } else { false } }.count
}

@Suite struct ResidentSurfacesTests {
    @Test func aSecondRenderWithNoChangesUploadsNoTiles() throws {
        let fake = FakeBackend(supports: [.composite])
        let resident = ResidentSurfaces(backend: fake)
        let layer = try (0..<6).map { try tile(Float($0) / 10 + 0.1) }
        let first = try sync(resident, "paint", layer)
        #expect(uploads(fake) == 6)
        let second = try sync(resident, "paint", layer)
        #expect(uploads(fake) == 6)
        #expect(resident.uploads == 6)
        #expect(second == first)
    }

    @Test func oneDirtyTileUploadsExactlyOneAndReleasesItsOldSurface() throws {
        let fake = FakeBackend(supports: [.composite])
        let resident = ResidentSurfaces(backend: fake)
        var layer = try (0..<6).map { try tile(Float($0) / 10 + 0.1) }
        let first = try sync(resident, "paint", layer)
        try layer[3].setPixel(x: 1, y: 2, RGBA(r: 1, g: 0, b: 0, a: 1))
        let second = try sync(resident, "paint", layer)
        #expect(uploads(fake) == 7)
        #expect(resident.uploads == 7)
        #expect(second[3] != first[3])
        #expect(Array(second[0..<3]) == Array(first[0..<3]) && Array(second[4...]) == Array(first[4...]))
        let old = try #require(first[3])
        #expect(fake.calls.contains(.release(old)))
    }

    @Test func equalPixelsInNewStorageUploadAgain() throws {
        let resident = ResidentSurfaces(backend: FakeBackend(supports: [.composite]))
        let first = try sync(resident, "paint", [tile(0.3)])
        let second = try sync(resident, "paint", [tile(0.3)])
        #expect(resident.uploads == 2)
        #expect(second != first)
    }

    @Test func aClearTileKeepsNoSurfaceAndNeverUploads() throws {
        let fake = FakeBackend(supports: [.composite])
        let resident = ResidentSurfaces(backend: fake)
        let clear = try PixelBuffer(width: 4, height: 4)
        #expect(try resident.surface(ResidentKey(layer: "paint", tile: 0), pixels: clear) == nil)
        #expect(try resident.surface(ResidentKey(layer: "paint", tile: 0), pixels: clear) == nil)
        #expect(uploads(fake) == 0 && resident.uploads == 0 && resident.count == 1)
    }

    @Test func pruneReleasesTheTilesOfLayersNotKept() throws {
        let fake = FakeBackend(supports: [.composite])
        let resident = ResidentSurfaces(backend: fake)
        let kept = try tile(0.4)
        let a = try sync(resident, "a", [tile(0.2)]), b = try sync(resident, "b", [kept])
        resident.prune(keeping: ["b"])
        #expect(fake.calls.contains(.release(try #require(a[0]))))
        #expect(!fake.calls.contains(.release(try #require(b[0]))))
        #expect(resident.count == 1)
        _ = try sync(resident, "b", [kept])
        #expect(resident.uploads == 2)
    }

    @Test func rebuildUploadsEveryHeldTileFromItsCPUPixelsOntoTheNewBackend() throws {
        let lost = FakeBackend(name: "lost", supports: [.composite])
        let resident = ResidentSurfaces(backend: lost)
        let layer = try [tile(0.3), PixelBuffer(width: 4, height: 4), tile(0.6)]
        let before = try sync(resident, "paint", layer)
        let cpu = CPUBackend()
        try resident.rebuild(on: cpu)
        #expect(resident.backend.name == "cpu")
        #expect(resident.uploads == 4)  // 2 on the lost backend, 2 rebuilt; the clear tile never
        for surface in before.compactMap({ $0 }) { #expect(lost.calls.contains(.release(surface))) }
        let after = try sync(resident, "paint", layer)
        #expect(resident.uploads == 4)
        #expect(after[1] == nil)
        #expect(try cpu.read(#require(after[0])) == layer[0])
        #expect(try cpu.read(#require(after[2])) == layer[2])
    }

    @Test func theBatchedDefaultEqualsOneCompositePerStep() throws {
        let cpu = CPUBackend()
        let backdrop = try PixelBuffer(width: 6, height: 5, fill: RGBA(r: 0.1, g: 0.2, b: 0.3, a: 1))
        let a = try cpu.surface(tile(0.5)), b = try cpu.surface(tile(0.9, size: 3))
        var batched = try cpu.surface(backdrop), stepped = try cpu.surface(backdrop)
        try cpu.composite([CompositeStep(a, x: 1, y: 0, mode: .multiply, opacity: 0.6),
                           CompositeStep(b, x: 3, y: 2, mode: .normal, opacity: 0.8)], onto: &batched)
        try cpu.composite(a, onto: &stepped, x: 1, y: 0, mode: .multiply, opacity: 0.6)
        try cpu.composite(b, onto: &stepped, x: 3, y: 2, mode: .normal, opacity: 0.8)
        #expect(try cpu.read(batched) == cpu.read(stepped))
    }

    @Test func theBatchedDefaultChecksEveryFamilyBeforeTheFirstBlend() throws {
        let fake = FakeBackend(supports: [.composite])
        let s = try fake.surface(tile(0.5))
        var b = try fake.surface(tile(0.1))
        #expect(throws: RenderError.unsupported(.blendSeparable)) {
            try fake.composite([CompositeStep(s, x: 0, y: 0, mode: .normal, opacity: 1),
                                CompositeStep(s, x: 0, y: 0, mode: .screen, opacity: 1)], onto: &b)
        }
        #expect(!fake.calls.contains(.op(.composite)))
    }

    @Test func theDispatcherRunsABatchOnTheCPUWhenOneStepFallsBack() throws {
        let fake = FakeBackend(supports: [.composite])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(tile(0.5))
        var b = try d.blank(width: 4, height: 4)
        #expect(b.backend == "fake")
        try d.composite([CompositeStep(s, x: 0, y: 0, mode: .normal, opacity: 1),
                         CompositeStep(s, x: 1, y: 1, mode: .screen, opacity: 0.5)], onto: &b)
        #expect(b.backend == "cpu")
        #expect(d.lastFallback?.op == .blendSeparable)
        let direct = CPUBackend()
        var expected = try direct.blank(width: 4, height: 4)
        let source = try direct.surface(tile(0.5))
        try direct.composite(source, onto: &expected, x: 0, y: 0, mode: .normal, opacity: 1)
        try direct.composite(source, onto: &expected, x: 1, y: 1, mode: .screen, opacity: 0.5)
        #expect(try d.read(b) == direct.read(expected))
    }

    @Test func aBatchFallsBackWhicheverOfItsFamiliesTheFallbackOneIs() throws {
        let fake = FakeBackend(supports: [.blendSeparable])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(tile(0.5))
        var b = try d.blank(width: 4, height: 4)
        try d.composite([CompositeStep(s, x: 0, y: 0, mode: .screen, opacity: 1),
                         CompositeStep(s, x: 1, y: 1, mode: .normal, opacity: 0.5)], onto: &b)
        #expect(b.backend == "cpu")
        #expect(d.lastFallback?.op == .composite)
    }

    @Test func theDispatcherRunsAnAllSupportedBatchOnThePreferredBackend() throws {
        let fake = FakeBackend(supports: [.composite])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(tile(0.5))
        var b = try d.blank(width: 4, height: 4)
        try d.composite([CompositeStep(s, x: 0, y: 0, mode: .normal, opacity: 1)], onto: &b)
        #expect(b.backend == "fake" && d.lastFallback == nil)
        #expect(fake.calls.filter { $0 == .op(.composite) }.count == 1)
    }
}
