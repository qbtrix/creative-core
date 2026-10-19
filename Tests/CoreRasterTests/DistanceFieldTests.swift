// DistanceFieldTests.swift: effects-engine FX-5's `DistanceField` acceptance,
// written first (FX-1), on since FX-5 built it: exact Euclidean distance
// on a 64 x 64 grid, alpha equal to `level` is inside, inside and outside are
// complements, `inside` counts the transparent ring past the buffer's edge,
// an empty shape is infinitely far, a bad level throws and stray lookups
// read as transparent.
import CoreRaster
import Testing

@Suite struct DistanceFieldTests {
    /// A transparent `size` x `size` buffer with one pixel of alpha `a`.
    func single(size: Int = 64, x: Int, y: Int, a: Float = 1) throws -> PixelBuffer {
        var b = try PixelBuffer(width: size, height: size)
        try b.setPixel(x: x, y: y, RGBA(r: a, g: a, b: a, a: a))
        return b
    }

    @Test func exactEuclidean() throws {
        for (px, py) in [(20, 37), (0, 0), (63, 5)] {
            let field = try DistanceField(alpha: single(x: px, y: py))
            #expect(field.width == 64 && field.height == 64)
            for y in 0..<64 {
                for x in 0..<64 {
                    let d2 = (x - px) * (x - px) + (y - py) * (y - py)
                    let want = Float(d2).squareRoot()
                    #expect(abs(field.outside(x: x, y: y) - want) <= 1e-4 * max(1, want), "(\(x), \(y)) from (\(px), \(py))")
                }
            }
            #expect(field.inside(x: px, y: py) == 1)
            #expect(field.inside(x: (px + 9) % 64, y: py) == 0)
        }
    }

    @Test func levelIsInclusive() throws {
        let half = try single(size: 8, x: 4, y: 4, a: 0.5)
        let atLevel = try DistanceField(alpha: half, level: 0.5)
        #expect(atLevel.outside(x: 4, y: 4) == 0 && atLevel.outside(x: 4, y: 7) == 3 && atLevel.inside(x: 4, y: 4) == 1)
        #expect(try DistanceField(alpha: half, level: 0.25).outside(x: 4, y: 4) == 0)
        let under = try single(size: 8, x: 4, y: 4, a: 0.49)
        let below = try DistanceField(alpha: under, level: 0.5)
        #expect(below.inside(x: 4, y: 4) == 0 && below.outside(x: 4, y: 4) > 0)
    }

    @Test func insideAndOutsideAreComplements() throws {
        let field = try DistanceField(alpha: EffectFixtures.disc(size: 64, radius: 16))
        // Pixel (x, y)'s centre is (x + 0.5, y + 0.5); the disc is centred on (32, 32).
        for y in 0..<64 {
            for x in 0..<64 {
                let inside = field.inside(x: x, y: y), outside = field.outside(x: x, y: y)
                #expect(min(inside, outside) == 0 && max(inside, outside) > 0)
                let r = ((Double(x) - 31.5) * (Double(x) - 31.5) + (Double(y) - 31.5) * (Double(y) - 31.5)).squareRoot()
                #expect(abs(Double(max(inside, outside)) - abs(r - 16)) <= 1.5, "(\(x), \(y))")
            }
        }
    }

    /// Past the buffer's edge reads as transparent, so a fully opaque buffer's
    /// `inside` counts the ring of pixels just past the edge.
    @Test func insideCountsBorderRing() throws {
        var opaque = try PixelBuffer(width: 8, height: 8)
        for y in 0..<8 { for x in 0..<8 { try opaque.setPixel(x: x, y: y, RGBA(r: 1, g: 1, b: 1, a: 1)) } }
        let field = try DistanceField(alpha: opaque)
        #expect(field.inside(x: 0, y: 3) == 1 && field.inside(x: 3, y: 3) == 4 && field.inside(x: 7, y: 7) == 1)
        #expect(field.outside(x: 3, y: 3) == 0)
    }

    @Test func badLevelThrowsAndLookupsNeverCrash() throws {
        let b = try single(size: 8, x: 2, y: 2)
        for bad: Float in [.nan, .infinity, -.infinity] {
            #expect(throws: RasterError.self) { try DistanceField(alpha: b, level: bad) }
        }
        let field = try DistanceField(alpha: b)
        // Off the buffer is transparent: infinitely far from the shape, outside it.
        for (x, y) in [(-1, 0), (0, -1), (8, 0), (0, 8), (Int.min, Int.max)] {
            #expect(field.outside(x: x, y: y) == .infinity && field.inside(x: x, y: y) == 0, "(\(x), \(y))")
        }
    }

    /// A shape with no pixels: every pixel is infinitely far from it and none is inside it.
    @Test func emptyShapeIsInfinitelyFar() throws {
        let field = try DistanceField(alpha: PixelBuffer(width: 8, height: 5))
        for y in 0..<5 {
            for x in 0..<8 { #expect(field.outside(x: x, y: y) == .infinity && field.inside(x: x, y: y) == 0, "(\(x), \(y))") }
        }
    }
}
