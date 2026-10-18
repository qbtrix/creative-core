// AffineOpsTests.swift: affine-composite AC-3's acceptance for `transformed`
// and `flipped`, written first (AC-1) and turned on by AC-3:
// identity and whole-pixel translations are `==` copies, a quarter turn
// equals `rotated(.degrees90)`, a 2x scale keeps edges within 0.5 px, outside
// is exactly clear, bad matrices and sizes throw, and flips mirror exactly.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The largest per-channel difference between two buffers of one size.
func affineMaxDelta(_ lhs: PixelBuffer, _ rhs: PixelBuffer) throws -> Float {
    var worst: Float = 0
    for y in 0..<lhs.height {
        for x in 0..<lhs.width {
            let p = try lhs.pixel(x: x, y: y), q = try rhs.pixel(x: x, y: y)
            worst = max(worst, abs(p.r - q.r), abs(p.g - q.g), abs(p.b - q.b), abs(p.a - q.a))
        }
    }
    return worst
}

@Suite struct AffineOpsTests {
    static let filters: [ResampleFilter] = [.bilinear, .lanczos3]

    @Test
    func translationIsExact() throws {
        // The identity and (0, 0) are plain copies; the rest shift, clear where nothing maps.
        for layer in try AffineFixtures.layers(count: 4, seed: 302) {
            for m in [AffineFixtures.identity] + AffineFixtures.translations {
                let dx = Int(m.tx), dy = Int(m.ty)
                var expected = try PixelBuffer(width: layer.width, height: layer.height)
                for y in 0..<layer.height {
                    for x in 0..<layer.width where (0..<layer.width).contains(x - dx) && (0..<layer.height).contains(y - dy) {
                        try expected.setPixel(x: x, y: y, layer.pixel(x: x - dx, y: y - dy))
                    }
                }
                for filter in Self.filters {
                    let out = try layer.transformed(m, width: layer.width, height: layer.height, filter: filter)
                    #expect(out == expected, "\(filter) (\(dx), \(dy)) on \(layer.width)x\(layer.height)")
                }
            }
        }
    }

    @Test
    func ninetyEqualsRotated() throws {
        for (w, h) in [(9, 6), (12, 12), (7, 11)] {
            let layer = try AffineFixtures.layer(seed: UInt64(303 + w), width: w, height: h, border: 1, block: 3)
            let turn = AffineFixtures.quarterTurn(1, width: w, height: h)
            for filter in Self.filters {
                let out = try layer.transformed(turn, width: h, height: w, filter: filter)
                #expect(try affineMaxDelta(out, layer.rotated(.degrees90)) <= 1e-6, "\(filter) \(w)x\(h)")
            }
        }
    }

    /// Where the red channel of row `y` crosses 0.5, interpolated between pixel
    /// centres, for crossings between centres `range`.
    private func edges(_ buffer: PixelBuffer, row y: Int, in range: Range<Int>) throws -> [Double] {
        var found: [Double] = []
        for x in range.dropLast() {
            let v0 = Double(try buffer.pixel(x: x, y: y).r), v1 = Double(try buffer.pixel(x: x + 1, y: y).r)
            guard (v0 - 0.5) * (v1 - 0.5) < 0 else { continue }
            found.append(Double(x) + 0.5 + (0.5 - v0) / (v1 - v0))
        }
        return found
    }

    @Test
    func scaleKeepsEdges() throws {
        let board = try AffineFixtures.checkerboard(width: 16, height: 16, cell: 4)
        for filter in Self.filters {
            let out = try board.transformed(AffineFixtures.scale(2, 2), width: 32, height: 32, filter: filter)
            // Rows inside a cell; edges in the interior sit at x 8, 16 and 24.
            for y in [2, 5, 11, 13, 19, 21, 27] {
                let found = try edges(out, row: y, in: 2..<30)
                #expect(found.count == 3, "\(filter) row \(y): \(found)")
                for (edge, expected) in zip(found, [8.0, 16, 24]) {
                    #expect(abs(edge - expected) <= 0.5, "\(filter) row \(y): edge \(edge) not near \(expected)")
                }
            }
        }
    }

    @Test
    func outsideIsExactlyClear() throws {
        let layer = try AffineFixtures.layer(seed: 304, width: 20, height: 12, border: 0)
        // Moved wholly off the output: every pixel is clear.
        for filter in Self.filters {
            let off = try layer.transformed(AffineFixtures.translation(100, 100), width: 30, height: 30, filter: filter)
            #expect(off == (try PixelBuffer(width: 30, height: 30)))
        }
        // Turned 30 degrees about its centre into a larger canvas: a pixel whose
        // centre maps more than the Lanczos-3 radius outside the source is clear.
        let (ct, st) = (cos(Double.pi / 6), sin(Double.pi / 6))
        let m = AffineMatrix(a: ct, b: st, c: -st, d: ct, tx: 20 - (ct * 10 - st * 6), ty: 20 - (st * 10 + ct * 6))
        let inverse = try #require(m.inverse)
        for filter in Self.filters {
            let out = try layer.transformed(m, width: 40, height: 40, filter: filter)
            var checked = 0
            for y in 0..<40 {
                for x in 0..<40 {
                    let px = Double(x) + 0.5, py = Double(y) + 0.5
                    let sx = inverse.a * px + inverse.c * py + inverse.tx
                    let sy = inverse.b * px + inverse.d * py + inverse.ty
                    guard sx < -3 || sy < -3 || sx > 23 || sy > 15 else { continue }
                    checked += 1
                    #expect(try out.pixel(x: x, y: y) == .clear, "\(filter) (\(x), \(y))")
                }
            }
            #expect(checked > 0)
        }
    }

    /// A singular or non-finite matrix and a size under 1 or past the cap
    /// throw; then seeded matrices with NaN, infinite, huge and tiny entries
    /// and sizes from below 1 to past the cap throw `RasterError` or return a
    /// buffer of the asked size, never crash.
    @Test
    func fuzz() throws {
        var rng = SplitMix64(seed: 306)
        let layer = try AffineFixtures.layer(seed: 307, width: 9, height: 7)
        let fixed: [(AffineMatrix, Int, Int)] = [(AffineFixtures.singular, 10, 8),
                                                 (AffineMatrix(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0), 10, 8),
                     (AffineFixtures.translation(.infinity, 0), 10, 8), (.identity, 0, 8), (.identity, -1, 4),
                     (.identity, 1 << 20, 1 << 20), (.identity, Int.max, 2)]
        for (m, w, h) in fixed {
            #expect(throws: RasterError.self) { try layer.transformed(m, width: w, height: h, filter: .bilinear) }
        }
        let specials: [Double] = [.nan, .infinity, -.infinity, 1e300, -1e300, 1e-300, 0, 1, -1, 0.5]
        func entry() -> Double {
            Bool.random(using: &rng) ? specials.randomElement(using: &rng) ?? 0 : .random(in: -4...4, using: &rng)
        }
        let sizes = [-3, 0, 1, 5, 12, 1 << 15, 1 << 31]
        for _ in 0..<400 {
            let m = AffineMatrix(a: entry(), b: entry(), c: entry(), d: entry(), tx: entry(), ty: entry())
            let w = sizes.randomElement(using: &rng) ?? 1, h = sizes.randomElement(using: &rng) ?? 1
            let finite = [m.a, m.b, m.c, m.d, m.tx, m.ty].allSatisfy(\.isFinite)
            let sizeOK = (try? PixelBuffer.validatedSize(width: w, height: h)) != nil
            let mustThrow = !finite || !sizeOK || m.inverse == nil
            // Skip big but valid outputs: the property is about throwing, not time.
            if !mustThrow && w * h > 4096 { continue }
            do {
                let out = try layer.transformed(m, width: w, height: h, filter: Self.filters[Int(rng.next() % 2)])
                #expect(!mustThrow, "\(m) \(w)x\(h) returned")
                #expect((out.width, out.height) == (w, h))
            } catch is RasterError {
            }
        }
    }

    @Test
    func flipMirrorsRows() throws {
        let layer = try AffineFixtures.layer(seed: 309, width: 11, height: 7, border: 0, block: 2)
        let h = layer.flipped(.horizontal), v = layer.flipped(.vertical)
        #expect((h.width, h.height, v.width, v.height) == (11, 7, 11, 7))
        #expect(try h.pixel(x: 10, y: 0) == layer.pixel(x: 0, y: 0))
        #expect(h.flipped(.horizontal) == layer && v.flipped(.vertical) == layer)
        for y in 0..<7 {
            for x in 0..<11 {
                #expect(try h.pixel(x: x, y: y) == layer.pixel(x: 10 - x, y: y), "horizontal (\(x), \(y))")
                #expect(try v.pixel(x: x, y: y) == layer.pixel(x: x, y: 6 - y), "vertical (\(x), \(y))")
            }
        }
    }
}

