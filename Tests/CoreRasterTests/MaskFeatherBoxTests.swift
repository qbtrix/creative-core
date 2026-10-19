// MaskFeatherBoxTests.swift: the feather against the exact Gaussian of sigma
// = radius / 3 (`gaussianBlur` on the mask as alpha), on seeded random masks
// and hard shapes over radii on both sides of the box switch (radius 6): no
// pixel differs by more than 0.025 (0.0171 here; 0.0229 the worst of a sweep
// of radii 6 to 30 by 0.5), and the extended boxes' variance is sigma².
@testable import CoreRaster
import Testing

@Suite struct MaskFeatherBoxTests {
    /// The exact Gaussian feather: the mask as alpha, blurred, read back.
    static func exact(_ mask: Mask, radius: Double) throws -> Mask {
        var buffer = try PixelBuffer(width: mask.width, height: mask.height)
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let v = try mask.coverage(x: x, y: y)
                try buffer.setPixel(x: x, y: y, RGBA(r: v, g: v, b: v, a: v))
            }
        }
        return try Mask(from: buffer.gaussianBlur(sigma: radius / 3), .alpha)
    }

    @Test func boxFeatherStaysNearTheGaussian() throws {
        var rng = SplitMix64(seed: 0xB0C5)
        var masks = [try MaskFixtures.square(), try MaskFixtures.ring(), try MaskFixtures.ellipse()]
        for _ in 0..<4 { masks.append(MaskFixtures.random(width: 41, height: 29, &rng)) }
        var worst: Float = 0
        for mask in masks {
            for radius in [1.0, 6, 6.5, 9, 20, .random(in: 1...30, using: &rng)] {
                let box = try MaskFixtures.all(mask.feathered(radius: radius))
                let gauss = try MaskFixtures.all(Self.exact(mask, radius: radius))
                worst = max(worst, zip(box, gauss).map { abs($0 - $1) }.max() ?? 0)
            }
        }
        print("feather box vs Gaussian: max difference \(worst)")
        #expect(worst <= 0.025)
    }

    /// The feather's extended boxes sum to variance sigma² exactly, with end
    /// weights in 0..<1.
    @Test func extendedBoxMatchesTheVariance() {
        for sigma in [2.01, 2.5, 3.3, 6.7, 25, 400] {
            let box = PixelBuffer.extendedBox(sigma: sigma, passes: Mask.featherPasses)
            let r = Double(box.radius), weights = 2 * r + 1 + 2 * box.alpha
            let variance = (r * (r + 1) * (2 * r + 1) / 3 + 2 * box.alpha * (r + 1) * (r + 1)) / weights
            #expect(box.radius >= 1 && (0..<1).contains(box.alpha), "sigma \(sigma): \(box)")
            #expect(abs(Double(Mask.featherPasses) * variance - sigma * sigma) <= 1e-9 * sigma * sigma, "sigma \(sigma): \(box)")
        }
    }
}
