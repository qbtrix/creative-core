// MaskCompositeTests.swift: the MM-4 acceptance row. A masked composite
// scales each pixel's opacity by the mask's coverage at its offset: a full
// mask is the unmasked composite, an empty one leaves the backdrop untouched,
// a half mask is half opacity; offsets clip off every edge. A mask read from
// a buffer takes its alpha or its luma times alpha, and `inverted` flips it.
@testable import CoreRaster
import Testing

@Suite struct MaskCompositeTests {
    @Test func fullMaskEqualsUnmasked() throws {
        let (source, backdrop) = try Self.pair()
        let full = try Mask(width: 12, height: 10, fill: 1)
        for mode in BlendMode.allCases {
            var masked = backdrop
            try masked.composite(source, x: 2, y: -1, mode: mode, opacity: 0.8, mask: full, maskX: 0, maskY: 0)
            #expect(try masked == composite(source, onto: backdrop, x: 2, y: -1, mode: mode, opacity: 0.8))
        }
    }

    /// An empty mask, or one wholly off the backdrop, writes no row: the
    /// backdrop's storage is not even copied.
    @Test func emptyMaskLeavesBackdrop() throws {
        let (source, backdrop) = try Self.pair()
        let empty = try Mask(width: 12, height: 10), block = try Mask(width: 3, height: 2, fill: 1)
        let placed: [(Mask, Int, Int)] = [(empty, 0, 0), (block, 12, 0), (block, 0, -2), (block, -3, 4), (block, Int.min, Int.max)]
        for (mask, mx, my) in placed {
            var masked = backdrop
            try masked.composite(source, x: 0, y: 0, mode: .multiply, opacity: 1, mask: mask, maskX: mx, maskY: my)
            #expect(masked.sharesStorage(with: backdrop))
        }
    }

    @Test func halfMaskIsHalfOpacity() throws {
        let (source, backdrop) = try Self.pair()
        let half = try Mask(width: 12, height: 10, fill: 0.5)
        for mode in BlendMode.allCases {
            var masked = backdrop
            try masked.composite(source, x: 1, y: 2, mode: mode, opacity: 1, mask: half, maskX: 0, maskY: 0)
            #expect(try masked == composite(source, onto: backdrop, x: 1, y: 2, mode: mode, opacity: 0.5))
        }
    }

    /// A 3 x 2 mask of mixed coverage at offsets inside and off every edge:
    /// each pixel under it is the unmasked composite at opacity coverage, every
    /// other pixel is the backdrop.
    @Test func maskOffsetMoves() throws {
        var rng = SplitMix64(seed: 0x0FF5)
        let source = try Self.buffer(12, 10, &rng), backdrop = try Self.buffer(12, 10, &rng)
        let mask = MaskFixtures.values(width: 3, height: 2, [1, 0.25, 0.5, 0, 0.75, 1])
        for (mx, my) in [(4, 5), (-2, 3), (10, 3), (3, -1), (3, 9), (-1, -1), (11, 9)] {
            var masked = backdrop
            try masked.composite(source, x: 0, y: 0, mode: .screen, opacity: 0.9, mask: mask, maskX: mx, maskY: my)
            for py in 0..<10 {
                for px in 0..<12 {
                    let inside = (mx..<(mx + 3)).contains(px) && (my..<(my + 2)).contains(py)
                    let c = inside ? try mask.coverage(x: px - mx, y: py - my) : 0
                    let expected = try composite(source, onto: backdrop, mode: .screen, opacity: c * 0.9).pixel(x: px, y: py)
                    #expect(try masked.pixel(x: px, y: py) == expected)
                }
            }
        }
    }

    @Test func badOpacityThrows() throws {
        let (source, backdrop) = try Self.pair()
        var masked = backdrop
        #expect(throws: RasterError.self) {
            try masked.composite(source, x: 0, y: 0, mode: .normal, opacity: .nan,
                                 mask: Mask(width: 1, height: 1), maskX: 0, maskY: 0)
        }
    }

    /// Opaque white, opaque black, transparent, and white at half alpha.
    @Test func transparentIsZero() throws {
        let luma = try MaskFixtures.all(Mask(from: Self.swatches(), .luminance))
        for (value, expected) in zip(luma, [Float(1), 0, 0, 0.5]) { #expect(abs(value - expected) < 1e-6) }
    }

    @Test func alphaReadsAlpha() throws {
        #expect(try MaskFixtures.all(Mask(from: Self.swatches(), .alpha)) == [1, 1, 0, 0.5])
    }

    @Test func invertedFlips() throws {
        #expect(try MaskFixtures.all(Mask(from: Self.swatches(), .alpha, inverted: true)) == [0, 0, 1, 0.5])
        let luma = try MaskFixtures.all(Mask(from: Self.swatches(), .luminance, inverted: true))
        for (value, expected) in zip(luma, [Float(0), 1, 1, 0.5]) { #expect(abs(value - expected) < 1e-6) }
    }

    /// Out-of-range components still give coverage in 0...1.
    @Test func coverageStaysInRange() throws {
        var rng = SplitMix64(seed: 0x3A77)
        let buffer = try Self.buffer(16, 9, &rng)
        for source in [MatteSource.alpha, .luminance] {
            #expect(try MaskFixtures.all(Mask(from: buffer, source)).allSatisfy { (0...1).contains($0) })
        }
    }

    /// A 9 x 7 seeded source and a 12 x 10 seeded backdrop.
    private static func pair() throws -> (PixelBuffer, PixelBuffer) {
        var rng = SplitMix64(seed: 0x3A5C)
        return (try buffer(9, 7, &rng), try buffer(12, 10, &rng))
    }

    private static func buffer(_ w: Int, _ h: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: w, height: h)
        for y in 0..<h { for x in 0..<w { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) } }
        return buffer
    }

    private static func swatches() throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: 4, height: 1)
        let pixels = [RGBA(r: 1, g: 1, b: 1, a: 1), RGBA(r: 0, g: 0, b: 0, a: 1), .clear, RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)]
        for (x, p) in pixels.enumerated() { try buffer.setPixel(x: x, y: 0, p) }
        return buffer
    }
}
