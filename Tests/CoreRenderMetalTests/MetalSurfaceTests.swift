// MetalSurfaceTests.swift: MetalBackend's surfaces on a real device (MB-1): the Float16 round trip,
// residentBytes, empty supports, unsupported ops, surface mismatches. Device-gated; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
import CoreRenderMetal
import Testing

/// SplitMix64, a private copy: test targets cannot share files.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct MetalSurfaceTests {
    /// Float16 keeps 11 significant bits, so a value in [0, 1] is within 2^-11.
    private static let tolerance: Float = 1e-3

    private static func backend() throws -> MetalBackend {
        guard let device = MetalBackend.defaultDevice else { throw RenderError.deviceLost("no default device") }
        return try MetalBackend(device: device, cacheURL: nil)
    }

    /// A seeded premultiplied buffer: alpha in [0, 1], every colour at most alpha.
    private static func randomBuffer(width: Int, height: Int, rng: inout SplitMix64) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let a = Float.random(in: 0...1, using: &rng)
                try buffer.setPixel(x: x, y: y, RGBA(
                    r: Float.random(in: 0...a, using: &rng), g: Float.random(in: 0...a, using: &rng),
                    b: Float.random(in: 0...a, using: &rng), a: a))
            }
        }
        return buffer
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func roundTripsSeededBuffersWithinFloat16() throws {
        let backend = try Self.backend()
        var rng = SplitMix64(seed: 1)
        for _ in 0..<20 {
            let width = Int.random(in: 1...600, using: &rng)
            let height = Int.random(in: 1...600, using: &rng)
            let buffer = try Self.randomBuffer(width: width, height: height, rng: &rng)
            let surface = try backend.surface(buffer)
            #expect(surface.width == width && surface.height == height && surface.backend == backend.name)
            let back = try backend.read(surface)
            #expect(back.width == width && back.height == height)
            var worst: Float = 0
            for y in 0..<height {
                for x in 0..<width {
                    let sent = try buffer.pixel(x: x, y: y)
                    let got = try back.pixel(x: x, y: y)
                    worst = max(worst, abs(sent.r - got.r), abs(sent.g - got.g),
                                abs(sent.b - got.b), abs(sent.a - got.a))
                }
            }
            #expect(worst <= Self.tolerance, "\(width)x\(height): worst delta \(worst)")
            backend.release(surface)
        }
        #expect(backend.residentBytes == 0)
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func residentBytesSumTheTileTexturesAndDropOnRelease() throws {
        let backend = try Self.backend()
        var rng = SplitMix64(seed: 2)
        let surface = try backend.surface(Self.randomBuffer(width: 600, height: 600, rng: &rng))
        let tiling = try SurfaceTiling(width: 600, height: 600)
        let expected = try (0..<tiling.tileCount).map { try tiling.rect($0) }.reduce(0) { $0 + $1.width * $1.height * 8 }
        #expect(tiling.tileCount == 9, "600 is two full tiles and an 88 px remainder each way")
        #expect(expected == 600 * 600 * 8, "the clipped tiles cover the buffer exactly")
        #expect(backend.residentBytes == expected)
        backend.release(surface)
        #expect(backend.residentBytes == 0)
        backend.release(surface)
        #expect(backend.residentBytes == 0, "a second release is a no-op")
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func freshBackendSupportsNothingAndIsHealthy() throws {
        let backend = try Self.backend()
        #expect(backend.supports.isEmpty && backend.isHealthy && backend.residentBytes == 0)
        #expect(backend.capabilities == MetalCapabilities())
        #expect(backend.name.hasPrefix("Metal ("))
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func everyOpIsUnsupported() throws {
        let backend = try Self.backend()
        let surface = try backend.surface(PixelBuffer(width: 4, height: 4))
        #expect(throws: RenderError.unsupported(.blur)) { try backend.gaussianBlur(surface, sigma: 1) }
        #expect(throws: RenderError.unsupported(.blur)) {
            try backend.unsharpMask(surface, amount: 1, sigma: 1, threshold: 0)
        }
        #expect(throws: RenderError.unsupported(.transform)) {
            try backend.cropped(surface, x: 0, y: 0, width: 2, height: 2)
        }
    }

    @Test(.enabled(if: MetalBackend.defaultDevice != nil))
    func releasedOrForeignSurfaceIsAMismatch() throws {
        let backend = try Self.backend()
        let surface = try backend.surface(PixelBuffer(width: 3, height: 2))
        let foreign = RenderSurface(id: surface.id, width: 3, height: 2, backend: "CPU")
        #expect(throws: RenderError.surfaceMismatch) { try backend.read(foreign) }
        #expect(try backend.read(surface).width == 3, "the same id under this backend's name still reads")
        backend.release(surface)
        #expect(throws: RenderError.surfaceMismatch) { try backend.read(surface) }
    }
}
#endif
