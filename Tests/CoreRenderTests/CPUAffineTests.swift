// CPUAffineTests.swift: affine-composite AC-6's acceptance, written first
// (AC-1) and turned on by AC-6, which fills `CPUBackend+Affine.swift`: each
// `.affine` call on the CPU `==` the CoreRaster op it wraps (non-square sizes
// and both axes, so swapped arguments show), a dispatcher over a fake
// without `.affine` routes all three to the CPU, and a bad opacity or a
// singular matrix throws `RenderError.raster` with `b` unchanged.
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes, alpha included.
private func affineLayer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    return try PixelBuffer(rgba8: (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) },
                           width: width, height: height)
}

/// The message of the `RasterError.invalid` that `body` throws, or "" when it
/// returns or throws anything else.
private func rasterMessage(_ body: () throws -> Void) -> String {
    do { try body() } catch let RasterError.invalid(message) { return message } catch {}
    return ""
}

@Suite struct CPUAffineTests {
    let cpu = CPUBackend()
    static let matrices = [AffineMatrix.identity, AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 3, ty: -2),
                           AffineMatrix(a: 0.8660254, b: 0.5, c: -0.5, d: 0.8660254, tx: 6, ty: 1),
                           AffineMatrix(a: 1.7, b: 0, c: 0.4, d: 0.6, tx: -2, ty: 3),
                           AffineMatrix(a: 0.4, b: -0.3, c: 0.3, d: 0.4, tx: 1, ty: 5)]

    /// `op` on a CPU surface of `buffer`: checks it made a new surface of its
    /// pixels' size and left the input alone, releases both, returns the pixels.
    private func run(_ buffer: PixelBuffer, _ op: (RenderSurface) throws -> RenderSurface) throws -> PixelBuffer {
        let s = try cpu.surface(buffer)
        defer { cpu.release(s) }
        let out = try op(s)
        defer { cpu.release(out) }
        let pixels = try cpu.read(out)
        #expect(out.id != s.id && out.backend == cpu.name)
        #expect((out.width, out.height) == (pixels.width, pixels.height))
        #expect(try cpu.read(s) == buffer)
        return pixels
    }

    @Test
    func equalsDirect() throws {
        let buffer = try affineLayer(width: 11, height: 7, seed: 61)
        for (i, m) in Self.matrices.enumerated() {
            for filter in [ResampleFilter.bilinear, .lanczos3] {
                let got = try run(buffer) { try cpu.transformed($0, m, width: 13, height: 9, filter: filter) }
                #expect(got == (try buffer.transformed(m, width: 13, height: 9, filter: filter)), "#\(i) \(filter)")
            }
        }
    }

    @Test
    func flipAxisKept() throws {
        let buffer = try affineLayer(width: 9, height: 6, seed: 62)
        for axis in [FlipAxis.horizontal, .vertical] {
            #expect(try run(buffer) { try cpu.flipped($0, axis) } == buffer.flipped(axis), "\(axis)")
        }
        #expect(buffer.flipped(.horizontal) != buffer.flipped(.vertical))
    }

    @Test
    func compositeThroughEqualsDirect() throws {
        let layer = try affineLayer(width: 10, height: 8, seed: 63)
        let backdrop = try affineLayer(width: 16, height: 12, seed: 64)
        for (i, m) in Self.matrices.enumerated() {
            for mode in [BlendMode.normal, .multiply, .screen, .hue] {
                var want = backdrop
                try want.composite(layer, through: m, mode: mode, opacity: 0.7, filter: .bilinear)
                let s = try cpu.surface(layer)
                var b = try cpu.surface(backdrop)
                try cpu.composite(s, onto: &b, through: m, mode: mode, opacity: 0.7, filter: .bilinear)
                #expect(try cpu.read(b) == want, "#\(i) \(mode)")
                #expect(try cpu.read(s) == layer)
                cpu.release(s)
                cpu.release(b)
            }
        }
    }

    /// A bad opacity or a singular matrix: CoreRaster's `RasterError.invalid`
    /// comes back as `RenderError.raster` with the same message, the composite
    /// leaves `b`'s pixels as they were, and neither input surface changes.
    @Test
    func badInputThrowsRasterAndLeavesBackdrop() throws {
        let layer = try affineLayer(width: 6, height: 5, seed: 67)
        let backdrop = try affineLayer(width: 9, height: 7, seed: 68)
        let singular = AffineMatrix(a: 1, b: 2, c: 2, d: 4, tx: 3, ty: 1)
        #expect(singular.inverse == nil)
        let m = Self.matrices[2]
        let s = try cpu.surface(layer)
        var b = try cpu.surface(backdrop)
        defer { cpu.release(s); cpu.release(b) }
        let composites: [(String, AffineMatrix, Float)] = [
            ("opacity 1.5", m, 1.5), ("opacity nan", m, .nan), ("opacity -0.1", m, -0.1), ("singular", singular, 0.7),
        ]
        for (name, matrix, opacity) in composites {
            var direct = backdrop
            let message = rasterMessage { try direct.composite(layer, through: matrix, mode: .normal, opacity: opacity, filter: .bilinear) }
            #expect(!message.isEmpty, "\(name) throws in CoreRaster")
            #expect(throws: RenderError.raster(message), "\(name)") {
                try cpu.composite(s, onto: &b, through: matrix, mode: .normal, opacity: opacity, filter: .bilinear)
            }
            #expect(try cpu.read(b) == backdrop, "\(name) leaves b")
        }
        let message = rasterMessage { _ = try layer.transformed(singular, width: 6, height: 5, filter: .bilinear) }
        #expect(!message.isEmpty, "transformed singular throws in CoreRaster")
        #expect(throws: RenderError.raster(message)) { try cpu.transformed(s, singular, width: 6, height: 5, filter: .bilinear) }
        #expect(try cpu.read(s) == layer)
    }

    @Test
    func dispatcherRoutesAffineToCPU() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases).subtracting([.affine]))
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let layer = try affineLayer(width: 8, height: 6, seed: 65)
        let backdrop = try affineLayer(width: 12, height: 10, seed: 66)
        let m = Self.matrices[2]
        let s = try d.surface(layer)
        #expect(s.backend == "fake")
        let moved = try d.transformed(s, m, width: 9, height: 7, filter: .lanczos3)
        #expect(moved.backend == d.fallback.name)
        #expect(try d.read(moved) == layer.transformed(m, width: 9, height: 7, filter: .lanczos3))
        #expect(d.lastFallback?.op == .affine && d.lastFallback?.reason == RenderDispatcher.reasonUnsupported)
        let mirrored = try d.flipped(s, .vertical)
        #expect(mirrored.backend == d.fallback.name)
        #expect(try d.read(mirrored) == layer.flipped(.vertical))
        var b = try d.surface(backdrop)
        try d.composite(s, onto: &b, through: m, mode: .screen, opacity: 0.6, filter: .bilinear)
        var want = backdrop
        try want.composite(layer, through: m, mode: .screen, opacity: 0.6, filter: .bilinear)
        #expect(b.backend == d.fallback.name)
        #expect(try d.read(b) == want)
        #expect(d.lastFallback?.op == .affine)
    }
}
