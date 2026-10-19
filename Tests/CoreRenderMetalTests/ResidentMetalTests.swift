// ResidentMetalTests.swift: resident rendering on the GPU. The Float16 upload encodes every component as
// HalfFloat does, bit for bit; `blank` reads back clear; the batched composite gives the bits of one in-place
// composite per step, resident or evicted, and a `read` straight after it (the composite commits with no wait)
// sees those pixels even with the sources released; and ResidentSurfaces on Metal uploads
// 0 tiles for an unchanged render, 1 for one written tile, and rebuilds every tile onto a new backend after a
// device loss. Skipped without a device.
#if canImport(Metal)
import CoreRaster
import CoreRender
@testable import CoreRenderMetal
import Metal
import Testing

private let hasDevice = MetalBackend.defaultDevice != nil

/// `metal.read(s)`, compared bit for bit with `expected`.
private func expectBits(_ metal: MetalBackend, _ s: RenderSurface, _ expected: PixelBuffer, _ label: String) throws {
    #expect(try metal.read(s) == expected, "\(label)")
}

@Suite(.serialized) struct ResidentMetalTests {
    @Test func theUploadEncodesEveryComponentAsHalfFloatDoes() throws {
        var state: UInt64 = 0xF16
        let edges: [Float] = [0, -0, 1, -1, 65504, 65519, 65520, 1e9, -1e9, 0x1p-24, 0x1p-25, 0x1.8p-25, 2047.5, 1e-45, 0.1, 1 / 3]
        let random = (0..<20_000).map { _ -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(bitPattern: UInt32(truncatingIfNeeded: state >> 32))
        }.filter(\.isFinite)
        for value in edges + random {
            let clamped = min(max(value, -MetalSurface.halfMax), MetalSurface.halfMax)
            #expect(MetalSurface.half(value) == HalfFloat.encode(clamped), "\(value)")
        }
    }

    @Test(.enabled(if: hasDevice)) func aBlankSurfaceReadsBackClear() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let s = try metal.blank(width: 300, height: 270)
        try expectBits(metal, s, PixelBuffer(width: 300, height: 270), "blank")
    }

    @Test(.enabled(if: hasDevice)) func theBatchedCompositeGivesTheBitsOfOneCompositePerStep() throws {
        let metal = try MetalBackend.onDefaultDevice()
        guard metal.supports.contains(.composite) else { return }
        let backdrop = try PixelBuffer.seeded(width: 300, height: 270, seed: 0xBA7C)
        let sources = try [(260, 200, 1), (100, 90, 2), (300, 270, 3)].map { try PixelBuffer.seeded(width: $0.0, height: $0.1, seed: UInt64($0.2)) }
        var modes: [(BlendMode, Float)] = [(.normal, 1), (.multiply, 0.6), (.normal, 0.37)]
        if metal.supports.contains(.blendNonSeparable) { modes[2] = (.hue, 0.5) }
        let offsets = [(-130, 35), (170, 170), (0, 0)]
        for budget in [metal.budgetBytes, 0] {
            metal.budgetBytes = budget
            let surfaces = try sources.map { try metal.surface($0) }
            var batched = try metal.surface(backdrop), stepped = try metal.surface(backdrop)
            let steps = zip(zip(surfaces, modes), offsets).map { pair, at in
                CompositeStep(pair.0, x: at.0, y: at.1, mode: pair.1.0, opacity: pair.1.1)
            }
            try metal.composite(steps, onto: &batched)
            for step in steps {
                try metal.composite(step.surface, onto: &stepped, x: step.x, y: step.y, mode: step.mode, opacity: step.opacity)
            }
            try expectBits(metal, batched, metal.read(stepped), "budget \(budget)")
        }
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: hasDevice)) func aReadStraightAfterTheBatchedCompositeSeesItsPixels() throws {
        let metal = try MetalBackend.onDefaultDevice()
        guard metal.supports.contains(.composite) else { return }
        // Big enough (12 tiles, three full-size steps) that the GPU is still at work when `read` is queued.
        let backdrop = try PixelBuffer.seeded(width: 1024, height: 768, seed: 0x5EE)
        let sources = try (1...3).map { try PixelBuffer.seeded(width: 1024, height: 768, seed: UInt64($0)) }
        var batched = try metal.surface(backdrop), stepped = try metal.surface(backdrop)
        let modes: [(BlendMode, Float)] = [(.normal, 0.5), (.multiply, 0.8), (.screen, 0.3)]
        var surfaces = try sources.map { try metal.surface($0) }
        try metal.composite(zip(surfaces, modes).map { CompositeStep($0, x: 0, y: 0, mode: $1.0, opacity: $1.1) }, onto: &batched)
        surfaces.forEach(metal.release)  // the command buffer holds the source textures, not the backend
        let seen = try metal.read(batched)
        surfaces = try sources.map { try metal.surface($0) }
        for (surface, mode) in zip(surfaces, modes) {
            try metal.composite(surface, onto: &stepped, x: 0, y: 0, mode: mode.0, opacity: mode.1)
        }
        #expect(seen != backdrop)
        #expect(try seen == metal.read(stepped))
        #expect(metal.isHealthy)
    }

    @Test(.enabled(if: hasDevice)) func aBatchWithAnUnsupportedOrForeignStepChangesNothing() throws {
        let metal = try MetalBackend.onDefaultDevice()
        guard metal.supports.contains(.composite) else { return }
        let backdrop = try PixelBuffer.seeded(width: 40, height: 30, seed: 9)
        let s = try metal.surface(PixelBuffer.seeded(width: 20, height: 20, seed: 10))
        var b = try metal.surface(backdrop)
        let before = try metal.read(b)
        let foreign = try CPUBackend().surface(backdrop)
        #expect(throws: RenderError.surfaceMismatch) {
            try metal.composite([CompositeStep(s, x: 0, y: 0, mode: .normal, opacity: 1),
                                 CompositeStep(foreign, x: 0, y: 0, mode: .normal, opacity: 1)], onto: &b)
        }
        try expectBits(metal, b, before, "unchanged")
    }

    @Test(.enabled(if: hasDevice)) func residentTilesOnMetalUploadOnlyWhatChangedAndRebuildAfterALoss() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let resident = ResidentSurfaces(backend: metal)
        var tiles = try (0..<4).map { try PixelBuffer.seeded(width: 256, height: 256, seed: UInt64(20 + $0)) }
        func sync() throws -> [RenderSurface?] {
            try tiles.enumerated().map { try resident.surface(ResidentKey(layer: "paint", tile: $0.offset), pixels: $0.element) }
        }
        _ = try sync()
        #expect(resident.uploads == 4)
        _ = try sync()
        #expect(resident.uploads == 4, "a second render with no changes uploads 0 tiles")
        try tiles[2].setPixel(x: 9, y: 9, RGBA(r: 0.5, g: 0, b: 0, a: 0.5))
        _ = try sync()
        #expect(resident.uploads == 5, "one dirty tile uploads exactly 1")
        metal.fail("test: device lost")
        let fresh = try MetalBackend.onDefaultDevice()
        try resident.rebuild(on: fresh)
        let after = try sync()
        #expect(resident.uploads == 9)
        for (surface, pixels) in zip(after, tiles) {
            #expect(try fresh.worstDelta(reading: #require(surface), against: pixels) <= 1.0 / 1024)
        }
    }
}
#endif
