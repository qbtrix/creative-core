// AffineFixtures.swift: seeded inputs for the affine-composite suites
// (AffineOpsTests, CanvasSizeTests, CompositeAffineTests, CPUAffineTests).
// Layers have a transparent border (or none) and hard-edged blocks of premultiplied
// color inside, so resampling seams and outside-is-clear both show; matrices
// cover the identity, whole-pixel translations, quarter turns about a centre,
// scales, skews, a near-singular and a singular map. Same seed, same values,
// on every platform (SplitMix64 from Support.swift).
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum AffineFixtures {
    /// A `width` x `height` layer: a `border`-pixel transparent frame around
    /// `block` x `block` tiles, each one seeded color, opaque or half alpha.
    static func layer(seed: UInt64, width: Int, height: Int, border: Int = 2, block: Int = 4) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var buffer = try PixelBuffer(width: width, height: height)
        let cols = (width + block - 1) / block, rows = (height + block - 1) / block
        let tiles = (0..<(cols * rows)).map { _ in
            RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                 b: .random(in: 0...1, using: &rng), a: Bool.random(using: &rng) ? 1 : 0.5).premultiplied()
        }
        for y in border..<max(border, height - border) {
            for x in border..<max(border, width - border) {
                try buffer.setPixel(x: x, y: y, tiles[(y / block) * cols + x / block])
            }
        }
        return buffer
    }

    /// `count` seeded layers, sizes from 6 x 6 to 40 x 40, each with its own
    /// seed and a `border`-pixel transparent frame (0 for hard edges at the sides).
    static func layers(count: Int, seed: UInt64, border: Int = 2) throws -> [PixelBuffer] {
        var rng = SplitMix64(seed: seed)
        return try (0..<count).map { _ in
            try layer(seed: rng.next(), width: .random(in: 6...40, using: &rng), height: .random(in: 6...40, using: &rng),
                      border: border)
        }
    }

    /// An opaque black and white checkerboard of `cell`-pixel squares, white at (0, 0).
    static func checkerboard(width: Int, height: Int, cell: Int) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height, fill: RGBA(r: 0, g: 0, b: 0, a: 1))
        for y in 0..<height {
            for x in 0..<width where (x / cell + y / cell).isMultiple(of: 2) {
                try buffer.setPixel(x: x, y: y, RGBA(r: 1, g: 1, b: 1, a: 1))
            }
        }
        return buffer
    }

    static let identity = AffineMatrix.identity

    static func translation(_ tx: Double, _ ty: Double) -> AffineMatrix {
        AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: tx, ty: ty)
    }

    /// Whole-pixel translations, (7, −3) among them.
    static let translations = [translation(7, -3), translation(0, 0), translation(-5, 4), translation(12, 9)]

    static func scale(_ sx: Double, _ sy: Double) -> AffineMatrix {
        AffineMatrix(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0)
    }

    /// x' = x + kx·y, y' = ky·x + y.
    static func skew(_ kx: Double, _ ky: Double) -> AffineMatrix {
        AffineMatrix(a: 1, b: ky, c: kx, d: 1, tx: 0, ty: 0)
    }

    /// `quarters` clockwise quarter turns of a `width` x `height` image about
    /// its centre, moved so that centre lands on the centre of the turned
    /// buffer (height x width for an odd count), as `rotated(degrees:filter:)`
    /// places it. Entries are exact integers.
    static func quarterTurn(_ quarters: Int, width: Int, height: Int) -> AffineMatrix {
        let k = ((quarters % 4) + 4) % 4
        let (c0, s0): (Double, Double) = [(1, 0), (0, 1), (-1, 0), (0, -1)][k]
        let (outW, outH) = k.isMultiple(of: 2) ? (width, height) : (height, width)
        let cx = Double(width) / 2, cy = Double(height) / 2
        return AffineMatrix(a: c0, b: s0, c: -s0, d: c0,
                            tx: Double(outW) / 2 - (c0 * cx - s0 * cy),
                            ty: Double(outH) / 2 - (s0 * cx + c0 * cy))
    }

    /// Determinant 1e-12: invertible, but barely.
    static let nearSingular = AffineMatrix(a: 1, b: 1, c: 1, d: 1 + 1e-12, tx: 0, ty: 0)

    /// Determinant 0: the second column is twice the first.
    static let singular = AffineMatrix(a: 1, b: 2, c: 2, d: 4, tx: 3, ty: 1)

    /// `count` seeded invertible maps: a rotation, a scale in 0.25...3 per
    /// axis, a skew up to 0.5 and a translation within ±20.
    static func matrices(count: Int, seed: UInt64) -> [AffineMatrix] {
        var rng = SplitMix64(seed: seed)
        return (0..<count).map { _ in
            let t = Double.random(in: 0..<(2 * .pi), using: &rng)
            let sx = Double.random(in: 0.25...3, using: &rng), sy = Double.random(in: 0.25...3, using: &rng)
            let k = Double.random(in: -0.5...0.5, using: &rng)
            let (ct, st) = (cos(t), sin(t))
            return AffineMatrix(a: ct * sx, b: st * sx, c: (ct * k - st) * sy, d: (st * k + ct) * sy,
                                tx: .random(in: -20...20, using: &rng), ty: .random(in: -20...20, using: &rng))
        }
    }
}

@Test func affineFixturesBuildDeterministically() throws {
    let layer = try AffineFixtures.layer(seed: 7, width: 20, height: 12)
    #expect((layer.width, layer.height) == (20, 12))
    #expect(try layer.pixel(x: 0, y: 0) == .clear)
    #expect(try layer.pixel(x: 19, y: 11) == .clear)
    #expect(try layer.pixel(x: 2, y: 2).a > 0)
    #expect(try AffineFixtures.layer(seed: 7, width: 20, height: 12) == layer)
    #expect(try AffineFixtures.layer(seed: 8, width: 20, height: 12) != layer)
    #expect(try AffineFixtures.layers(count: 5, seed: 3) == AffineFixtures.layers(count: 5, seed: 3))
    #expect(AffineFixtures.matrices(count: 5, seed: 3) == AffineFixtures.matrices(count: 5, seed: 3))
    #expect(AffineFixtures.matrices(count: 50, seed: 3).allSatisfy { $0.inverse != nil })
    let board = try AffineFixtures.checkerboard(width: 8, height: 4, cell: 2)
    #expect(try board.pixel(x: 0, y: 0).r == 1 && board.pixel(x: 2, y: 0).r == 0)
    #expect(AffineFixtures.translations.contains(AffineFixtures.translation(7, -3)))
    // A quarter turn of 6 x 4 maps (0, 0) to (4, 0) and the centre to the 4 x 6 centre.
    let turn = AffineFixtures.quarterTurn(1, width: 6, height: 4)
    #expect((turn.tx, turn.ty) == (4, 0))
    #expect((turn.a * 3 + turn.c * 2 + turn.tx, turn.b * 3 + turn.d * 2 + turn.ty) == (2, 3))
    #expect(AffineFixtures.quarterTurn(4, width: 6, height: 4) == .identity)
    #expect(AffineFixtures.nearSingular.inverse != nil)
    #expect(AffineFixtures.singular.inverse == nil)
}
