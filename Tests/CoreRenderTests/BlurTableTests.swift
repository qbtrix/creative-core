// BlurTableTests.swift: the Metal blur kernel's Gaussian (MB-11) has 2 ceil(3 sigma) + 1 symmetric weights that
// sum to 1, sigma 0 is the identity, an invalid sigma throws the CPU backend's exact error, and a line through
// the table (clamp-to-edge) gives CoreRaster's `gaussianBlur` of a one-pixel-high buffer.
import CoreRaster
import CoreRender
import Testing

@Suite struct BlurTableTests {
    private static let sigmas = [0, 0.3, 0.5, 1, 3, 7.25, 20]

    @Test func weightsAreSymmetricNormalisedAndSizedByThreeSigma() throws {
        for sigma in Self.sigmas {
            let table = try BlurTable(sigma: sigma, width: 64, height: 1)
            let radius = Int((3 * sigma).rounded(.up))
            #expect(table.radius == radius && table.weights.count == 2 * radius + 1, "sigma \(sigma)")
            #expect(abs(table.weights.reduce(0, +) - 1) < 1e-5, "sigma \(sigma) sums to 1")
            #expect(table.weights == table.weights.reversed(), "sigma \(sigma) is symmetric")
            #expect(table.weights.allSatisfy { $0 > 0 } && table.isIdentity == (sigma == 0))
        }
        #expect(try BlurTable(sigma: 0, width: 3, height: 3).weights == [1])
        #expect(try BlurTable(sigma: 0, width: 3, height: 3).apply([0.25, 0.5, 1]) == [0.25, 0.5, 1])
        #expect(try BlurTable(sigma: 1, width: 3, height: 3).apply([]).isEmpty)
    }

    /// Every sigma CoreRaster rejects throws the same `RenderError` from the table as from the CPU backend.
    @Test func invalidSigmaThrowsTheCPUBackendsError() throws {
        let cpu = CPUBackend()
        let surface = try cpu.surface(try PixelBuffer(width: 5, height: 3))
        for sigma in [-1, -0.0001, .nan, .infinity, -.infinity, 3.4, 3.3, 1e300] {
            do {
                _ = try cpu.gaussianBlur(surface, sigma: sigma)
                #expect(throws: Never.self) { try BlurTable(sigma: sigma, width: 5, height: 3) }
            } catch let expected as RenderError {
                #expect(throws: expected) { try BlurTable(sigma: sigma, width: 5, height: 3) }
            }
        }
        #expect(throws: (any Error).self) { try BlurTable(sigma: 3.4, width: 5, height: 3) }
    }

    /// CoreRaster's blur of a one-pixel impulse is its kernel, so every table weight equals it exactly: the
    /// table's copy of CoreRaster's private `gaussianKernel` (count, radius rounding, normalisation) cannot drift.
    @Test func weightsEqualCoreRastersBlurOfAnImpulse() throws {
        for sigma in Self.sigmas + [0.1, 1.0 / 3, 2.0 / 3, 4.5] {
            let radius = Int((3 * sigma).rounded(.up))
            let length = 2 * radius + 3
            var impulse = try PixelBuffer(width: length, height: 1)
            try impulse.setPixel(x: length / 2, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
            let blurred = try impulse.gaussianBlur(sigma: sigma)
            let reds = try (0..<length).map { try blurred.pixel(x: $0, y: 0).r }
            let table = try BlurTable(sigma: sigma, width: length, height: 1)
            #expect([0] + table.weights + [0] == reds, "sigma \(sigma)")
        }
    }

    /// One row through the table equals CoreRaster's blur of a one-pixel-high buffer (the vertical pass there
    /// clamps every tap to row 0 and leaves it unchanged), borders included.
    @Test func matchesCoreRasterOnALine() throws {
        var rng = ParityRandom(seed: 0xB1A5)
        for sigma in Self.sigmas {
            for length in [1, 2, 9, 61] where (3 * sigma).rounded(.up) <= Double(2 * length) {
                var buffer = try PixelBuffer(width: length, height: 1)
                for x in 0..<length {
                    let a = Float.random(in: 0...1, using: &rng)
                    try buffer.setPixel(x: x, y: 0, RGBA(r: Float.random(in: 0...a, using: &rng), g: a / 2, b: 0, a: a))
                }
                let want = try buffer.gaussianBlur(sigma: sigma)
                let table = try BlurTable(sigma: sigma, width: length, height: 1)
                let pixels = try (0..<length).map { try buffer.pixel(x: $0, y: 0) }
                let reds = table.apply(pixels.map(\.r)), alphas = table.apply(pixels.map(\.a))
                for i in 0..<length {
                    let p = try want.pixel(x: i, y: 0)
                    #expect(abs(reds[i] - p.r) < 1e-5 && abs(alphas[i] - p.a) < 1e-5, "sigma \(sigma) length \(length) pixel \(i)")
                }
            }
        }
    }
}
