// CPUBackendTests.swift: render-backend RB-3's acceptance. CPUBackend's round trip
// over 50 seeded buffers, display bytes equal to CoreRaster's in sRGB and P3,
// composite equal to CoreRaster's for every blend mode at opacities 0, 0.37 and 1
// with sources off every edge, released, unknown, foreign and mis-sized surfaces,
// CoreRaster errors passed through, every family supported, and the parity sample
// set for every family reproduced with zero delta. The store's `update`, which
// composite blends in place through, is checked directly: a throwing body
// leaves the buffer stored with what it wrote, and a bad surface never runs it.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster
@testable import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

@Suite struct CPUBackendTests {
    @Test func readGivesBackEverySeededBuffer() throws {
        let cpu = CPUBackend()
        var rng = SplitMix64(seed: 0xC9B)
        for i in 0..<50 {
            let buffer = try seededBuffer(width: Int.random(in: 1...17, using: &rng),
                                          height: Int.random(in: 1...13, using: &rng), seed: UInt64(i))
            let s = try cpu.surface(buffer)
            #expect(s.width == buffer.width && s.height == buffer.height && s.backend == "cpu")
            #expect(try cpu.read(s) == buffer)
        }
    }

    @Test func displayEqualsCoreRasterBytesInSRGBAndP3() throws {
        let cpu = CPUBackend()
        let buffer = try seededBuffer(width: 7, height: 5, seed: 31)
        let s = try cpu.surface(buffer)
        for space in [ColorSpace.sRGB, .displayP3] {
            #expect(try cpu.display(s, colorSpace: space) == buffer.rgba8(colorSpace: space))
        }
        var message = ""
        do { _ = try buffer.rgba8(colorSpace: .linearSRGB) } catch let RasterError.invalid(m) { message = m }
        #expect(!message.isEmpty)
        #expect(throws: RenderError.raster(message)) { try cpu.display(s, colorSpace: .linearSRGB) }
    }

    @Test func compositeEqualsCoreRasterForEveryModeOpacityAndEdge() throws {
        let cpu = CPUBackend()
        let source = try seededBuffer(width: 4, height: 3, seed: 5)
        let backdropBuffer = try seededBuffer(width: 6, height: 5, seed: 6)
        let s = try cpu.surface(source)
        // Inside, off each edge and corner, and wholly outside.
        let offsets = [(1, 1), (-2, 1), (4, 1), (1, -2), (1, 3), (-2, -1), (5, 4), (-4, 0), (6, 5)]
        for mode in BlendMode.allCases {
            for opacity: Float in [0, 0.37, 1] {
                for (x, y) in offsets {
                    var b = try cpu.surface(backdropBuffer)
                    let before = b
                    try cpu.composite(s, onto: &b, x: x, y: y, mode: mode, opacity: opacity)
                    let expected = try composite(source, onto: backdropBuffer, x: x, y: y, mode: mode, opacity: opacity)
                    #expect(b == before)
                    #expect(try cpu.read(b) == expected, "\(mode) \(opacity) at \(x),\(y)")
                    cpu.release(b)
                }
            }
        }
        #expect(try cpu.read(s) == source)
    }

    @Test func aSurfaceCompositesOntoItself() throws {
        let cpu = CPUBackend()
        let buffer = try seededBuffer(width: 5, height: 4, seed: 9)
        var b = try cpu.surface(buffer)
        try cpu.composite(b, onto: &b, x: 1, y: -1, mode: .multiply, opacity: 0.5)
        #expect(try cpu.read(b) == composite(buffer, onto: buffer, x: 1, y: -1, mode: .multiply, opacity: 0.5))
    }

    @Test func aBadOpacityThrowsCoreRastersMessageAndLeavesTheBackdrop() throws {
        let cpu = CPUBackend()
        let backdropBuffer = try seededBuffer(width: 3, height: 3, seed: 2)
        let s = try cpu.surface(try seededBuffer(width: 3, height: 3, seed: 1))
        var b = try cpu.surface(backdropBuffer)
        for opacity: Float in [1.5, -0.1, .nan] {
            var message = ""
            do { _ = try composite(backdropBuffer, onto: backdropBuffer, mode: .normal, opacity: opacity) }
            catch let RasterError.invalid(m) { message = m }
            #expect(!message.isEmpty)
            #expect(throws: RenderError.raster(message)) { try cpu.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: opacity) }
        }
        #expect(try cpu.read(b) == backdropBuffer)
    }

    @Test func releasedUnknownAndForeignSurfacesThrow() throws {
        let cpu = CPUBackend()
        let buffer = try seededBuffer(width: 3, height: 2, seed: 4)
        let s = try cpu.surface(buffer)
        var b = try cpu.surface(buffer)
        cpu.release(s)
        cpu.release(s)
        #expect(throws: RenderError.surfaceMismatch) { try cpu.read(s) }
        #expect(throws: RenderError.surfaceMismatch) { try cpu.display(s, colorSpace: .sRGB) }
        #expect(throws: RenderError.surfaceMismatch) { try cpu.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1) }
        #expect(try cpu.read(b) == buffer)
        let unknown = RenderSurface(id: UUID(), width: 3, height: 2, backend: "cpu")
        #expect(throws: RenderError.surfaceMismatch) { try cpu.read(unknown) }
        let fake = FakeBackend(supports: Set(RenderOp.allCases))
        var foreign = try fake.surface(buffer)
        #expect(throws: RenderError.surfaceMismatch) { try cpu.read(foreign) }
        #expect(throws: RenderError.surfaceMismatch) { try cpu.composite(b, onto: &foreign, x: 0, y: 0, mode: .normal, opacity: 1) }
        cpu.release(foreign)
        #expect(try fake.read(foreign) == buffer)
        // Releasing the backdrop mid-use: the next composite onto it throws.
        cpu.release(b)
        let live = try cpu.surface(buffer)
        #expect(throws: RenderError.surfaceMismatch) { try cpu.composite(live, onto: &b, x: 0, y: 0, mode: .screen, opacity: 1) }
    }

    @Test func aSurfaceWhoseSizeDisagreesThrows() throws {
        let cpu = CPUBackend()
        let s = try cpu.surface(try seededBuffer(width: 4, height: 3, seed: 8))
        for (w, h) in [(5, 3), (4, 4), (3, 3), (4, 2)] {
            let wrong = RenderSurface(id: s.id, width: w, height: h, backend: s.backend)
            #expect(throws: RenderError.surfaceMismatch) { try cpu.read(wrong) }
            var target = wrong
            #expect(throws: RenderError.surfaceMismatch) { try cpu.composite(s, onto: &target, x: 0, y: 0, mode: .normal, opacity: 1) }
        }
    }

    @Test func storeUpdateKeepsTheBufferWhenTheBodyThrows() throws {
        let store = SurfaceStore(backend: "cpu")
        let buffer = try seededBuffer(width: 4, height: 3, seed: 12)
        let s = store.insert(buffer)
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        #expect(throws: RenderError.surfaceMismatch) {
            try store.update(s) { pixels in
                try pixels.setPixel(x: 1, y: 2, red)
                throw RenderError.surfaceMismatch
            }
        }
        var expected = buffer
        try expected.setPixel(x: 1, y: 2, red)
        #expect(try store.buffer(for: s) == expected)
        let wrong = RenderSurface(id: s.id, width: 4, height: 2, backend: "cpu")
        var ran = false
        #expect(throws: RenderError.surfaceMismatch) { try store.update(wrong) { _ in ran = true } }
        #expect(!ran)
        #expect(try store.buffer(for: s) == expected)
    }

    @Test func supportsEveryFamily() {
        let cpu = CPUBackend()
        #expect(cpu.supports == Set(RenderOp.allCases))
        #expect(cpu.isHealthy)
    }

    @Test func paritySamplesForItsFamiliesMatchCoreRasterWithZeroDelta() throws {
        let cpu = CPUBackend()
        for op in cpu.supports.sorted(by: { $0.rawValue < $1.rawValue }) {
            for sample in try ParityHarness.sampleSet(for: op) {
                let got = try ParityHarness.render(sample, on: cpu)
                let expected: PixelBuffer
                switch sample.call {
                case .display(let space):
                    expected = try PixelBuffer(rgba8: sample.source.rgba8(colorSpace: space), width: sample.source.width,
                                               height: sample.source.height, colorSpace: space)
                case let .composite(x, y, mode, opacity):
                    let backdrop = try #require(sample.backdrop)
                    expected = try composite(sample.source, onto: backdrop, x: x, y: y, mode: mode, opacity: opacity)
                case .rotated(let turn): expected = sample.source.rotated(turn)
                case let .resampled(w, h, filter): expected = try sample.source.resized(width: w, height: h, filter: filter)
                case .gaussianBlur(let sigma): expected = try sample.source.gaussianBlur(sigma: sigma)
                case .adjusted(.contrast(let amount)): expected = try sample.source.contrast(amount)
                case let .cloned(dx, dy, mask): expected = try sample.source.cloned(offset: (dx: dx, dy: dy), through: mask)
                default:
                    Issue.record("unexpected call for \(op): \(sample.name)")
                    continue
                }
                #expect(got == expected, "\(op) \(sample.name)")
                #expect(try ParityHarness.compare(got, expected, tolerance: .standard).passed)
            }
        }
    }
}
