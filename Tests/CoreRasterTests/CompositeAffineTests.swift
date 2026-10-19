// CompositeAffineTests.swift: affine-composite AC-5's acceptance for
// `composite(_:through:...)` and `AffineMatrix.bounds`: through-composite
// equals transform-then-composite within 1/255 (`==` for whole-pixel moves)
// for every BlendMode, only the corner bounds widened by the filter's reach
// are written, layers mapped off the backdrop change nothing, and bad input
// throws with the backdrop unchanged.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@Suite struct CompositeAffineTests {
    /// A seeded 48 x 40 backdrop of opaque and half-alpha blocks, no border.
    private func backdrop(seed: UInt64) throws -> PixelBuffer {
        try AffineFixtures.layer(seed: seed, width: 48, height: 40, border: 0, block: 5)
    }

    /// `backdrop` with `layer` transformed through `m` to its size, then composited at (0, 0).
    private func reference(_ backdrop: PixelBuffer, _ layer: PixelBuffer, _ m: AffineMatrix, mode: BlendMode,
                           opacity: Float, filter: ResampleFilter) throws -> PixelBuffer {
        let copy = try layer.transformed(m, width: backdrop.width, height: backdrop.height, filter: filter)
        var out = backdrop
        try out.composite(copy, x: 0, y: 0, mode: mode, opacity: opacity)
        return out
    }

    /// Seeded layers with a transparent border and with hard edges at their
    /// sides (border 0), whose kernel reaches past the corner bounds.
    @Test(arguments: [2, 0])
    func equalsTransformThenComposite(border: Int) throws {
        var rng = SplitMix64(seed: 501)
        let layers = try AffineFixtures.layers(count: 50, seed: 502, border: border)
        let matrices = AffineFixtures.matrices(count: 50, seed: 503)
        for (i, (layer, m)) in zip(layers, matrices).enumerated() {
            let base = try backdrop(seed: UInt64(600 + i))
            let filter: ResampleFilter = i.isMultiple(of: 2) ? .bilinear : .lanczos3
            for mode in BlendMode.allCases {
                let opacity = Float.random(in: 0.3...1, using: &rng)
                var got = base
                try got.composite(layer, through: m, mode: mode, opacity: opacity, filter: filter)
                let want = try reference(base, layer, m, mode: mode, opacity: opacity, filter: filter)
                #expect(try affineMaxDelta(got, want) <= 1 / 255, "#\(i) \(mode) \(filter)")
            }
        }
    }

    /// A hard-edged layer scaled 2 at a fractional offset, and anisotropic,
    /// transposed, sheared (two with |b| != |c|, so each axis's pad reads
    /// different entries) and near-quarter-turn upscales: bilinear and
    /// lanczos3 cover pixels just outside the corner bounds along each
    /// axis, and the through-composite must cover them too.
    @Test
    func hardEdgeKernelReachPastCorners() throws {
        let layer = try AffineFixtures.layer(seed: 520, width: 10, height: 10, border: 0)
        let base = try PixelBuffer(width: 60, height: 60, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
        let matrices = [
            AffineMatrix(a: 2, b: 0, c: 0, d: 2, tx: 5.3, ty: 5.3),
            AffineMatrix(a: 3, b: 0, c: 0, d: 0.3, tx: 4.37, ty: 9.61),
            AffineMatrix(a: 0.3, b: 0, c: 0, d: 3, tx: 9.61, ty: 4.37),
            AffineMatrix(a: 0.2, b: 2.5, c: -2.5, d: 0.2, tx: 30.4, ty: 3.3),
            AffineMatrix(a: 2.5, b: 0.1, c: 1.8, d: 0.4, tx: 2.3, ty: 7.7),
            AffineMatrix(a: 0.3, b: 0.05, c: 3, d: 0.4, tx: 20.3, ty: 30.7),
            AffineMatrix(a: 0.4, b: 3, c: 0.05, d: 0.3, tx: 30.7, ty: 20.3),
        ]
        for m in matrices {
            for filter in [ResampleFilter.bilinear, .lanczos3] {
                var got = base
                try got.composite(layer, through: m, mode: .normal, opacity: 1, filter: filter)
                let want = try reference(base, layer, m, mode: .normal, opacity: 1, filter: filter)
                #expect(try affineMaxDelta(got, want) <= 1 / 255, "\(m) \(filter)")
            }
        }
    }

    @Test
    func wholePixelTranslationsAreExact() throws {
        let layer = try AffineFixtures.layer(seed: 504, width: 21, height: 15)
        let base = try backdrop(seed: 505)
        for m in AffineFixtures.translations {
            for mode in BlendMode.allCases {
                for filter in [ResampleFilter.bilinear, .lanczos3] {
                    var got = base
                    try got.composite(layer, through: m, mode: mode, opacity: 0.75, filter: filter)
                    let want = try reference(base, layer, m, mode: mode, opacity: 0.75, filter: filter)
                    #expect(got == want, "(\(m.tx), \(m.ty)) \(mode) \(filter)")
                }
            }
        }
    }

    @Test
    func rotatedBoundsCoverCorners() throws {
        let t = Double.pi / 6
        let turned = AffineMatrix(a: 0.5 * cos(t), b: 0.5 * sin(t), c: -0.5 * sin(t), d: 0.5 * cos(t), tx: 30, ty: 4)
        let cases = [(turned, 30, 20)] + AffineFixtures.matrices(count: 50, seed: 506).map { ($0, 17, 9) }
        for (m, w, h) in cases {
            let box = try #require(m.bounds(of: w, h))
            let corners = [(0.0, 0.0), (Double(w), 0), (0, Double(h)), (Double(w), Double(h))]
            let xs = corners.map { m.a * $0.0 + m.c * $0.1 + m.tx }, ys = corners.map { m.b * $0.0 + m.d * $0.1 + m.ty }
            for (x, y) in zip(xs, ys) {
                #expect(Double(box.x) <= x && x <= Double(box.x + box.width), "\(m): x \(x) outside \(box)")
                #expect(Double(box.y) <= y && y <= Double(box.y + box.height), "\(m): y \(y) outside \(box)")
            }
            #expect(Double(box.x) == floor(xs.min() ?? 0) && Double(box.x + box.width) == ceil(xs.max() ?? 0), "\(m)")
            #expect(Double(box.y) == floor(ys.min() ?? 0) && Double(box.y + box.height) == ceil(ys.max() ?? 0), "\(m)")
        }
        #expect(AffineMatrix(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0).bounds(of: 4, 4) == nil)
        #expect(AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: .infinity, ty: 0).bounds(of: 4, 4) == nil)
    }

    /// The packet's box: the corner bounds widened on every side by the
    /// filter's reach (radius times stretch source pixels, stretch the
    /// inverse's column length clamped to 1...source size, mapped forward
    /// through the linear part and rounded up, plus one), clipped to the
    /// backdrop, as half-open (x0, y0, x1, y1).
    private func reachBox(_ m: AffineMatrix, _ w: Int, _ h: Int, radius: Double,
                          backdrop: PixelBuffer) throws -> [Int] {
        let corners = try #require(m.bounds(of: w, h)), inv = try #require(m.inverse)
        let sx = min(max((inv.a * inv.a + inv.c * inv.c).squareRoot(), 1), Double(w))
        let sy = min(max((inv.b * inv.b + inv.d * inv.d).squareRoot(), 1), Double(h))
        let rx = radius * sx, ry = radius * sy
        let px = Int((abs(m.a) * rx + abs(m.c) * ry).rounded(.up)) + 1
        let py = Int((abs(m.b) * rx + abs(m.d) * ry).rounded(.up)) + 1
        return [max(corners.x - px, 0), max(corners.y - py, 0),
                min(corners.x + corners.width + px, backdrop.width), min(corners.y + corners.height + py, backdrop.height)]
    }

    /// The half-open box (x0, y0, x1, y1) of pixels whose component bit
    /// patterns differ between `a` and `b`, or nil when none do.
    private func writtenBox(_ a: PixelBuffer, _ b: PixelBuffer) throws -> [Int]? {
        var box: [Int]?
        for y in 0..<a.height {
            for x in 0..<a.width {
                let p = try a.pixel(x: x, y: y), q = try b.pixel(x: x, y: y)
                let same = [p.r, p.g, p.b, p.a].map(\.bitPattern) == [q.r, q.g, q.b, q.a].map(\.bitPattern)
                guard !same else { continue }
                box = box.map { [min($0[0], x), min($0[1], y), max($0[2], x + 1), max($0[3], y + 1)] } ?? [x, y, x + 1, y + 1]
            }
        }
        return box
    }

    /// The walk's shape at test size (scaled 0.5, turned 30 degrees, moved)
    /// and anisotropic, sheared and rotated upscales. The backdrop is all
    /// -0.0, which any blend visit rewrites to +0.0 (a transparent source
    /// gives b * 1 + 0), so comparing bit patterns sees every written pixel:
    /// the written box is exactly the packet's box, and no pixel outside it
    /// is written.
    @Test
    func rowsOutsideBoundsAreUntouched() throws {
        let t = Double.pi / 6
        let walk = AffineMatrix(a: 0.5 * cos(t), b: 0.5 * sin(t), c: -0.5 * sin(t), d: 0.5 * cos(t), tx: 70, ty: 60)
        let cases: [(AffineMatrix, Int, Int)] = [
            (walk, 30, 20),
            (AffineMatrix(a: 3, b: 0, c: 0, d: 0.3, tx: 60.37, ty: 70.61), 10, 10),
            (AffineMatrix(a: 0.3, b: 0, c: 0, d: 3, tx: 70.61, ty: 60.37), 10, 10),
            (AffineMatrix(a: 0.2, b: 2.5, c: -2.5, d: 0.2, tx: 90.4, ty: 60.3), 10, 10),
            (AffineMatrix(a: 2.5, b: 0.1, c: 1.8, d: 0.4, tx: 50.3, ty: 70.7), 10, 10),
        ]
        let zero = Float(sign: .minus, exponent: 0, significand: 0)
        let base = try PixelBuffer(width: 160, height: 160, fill: RGBA(r: zero, g: zero, b: zero, a: zero))
        for (i, (m, w, h)) in cases.enumerated() {
            let layer = try AffineFixtures.layer(seed: 507 + UInt64(i), width: w, height: h, border: 0)
            for (filter, radius) in [(ResampleFilter.bilinear, 1.0), (.lanczos3, 3.0)] {
                let want = try reachBox(m, w, h, radius: radius, backdrop: base)
                #expect(want[0] > 0 && want[1] > 0 && want[2] < base.width && want[3] < base.height, "\(m) \(filter) \(want)")
                for mode in [BlendMode.normal, .multiply] {
                    var got = base
                    try got.composite(layer, through: m, mode: mode, opacity: 1, filter: filter)
                    #expect(try writtenBox(got, base) == want, "\(m) \(filter) \(mode)")
                }
            }
        }
    }

    @Test
    func offBackdropChangesNothing() throws {
        let layer = try AffineFixtures.layer(seed: 509, width: 16, height: 12, border: 0)
        let base = try backdrop(seed: 510)
        let away = [AffineFixtures.translation(1000, 0), AffineFixtures.translation(-200, -200),
                    AffineMatrix(a: 0.5, b: 0.5, c: -0.5, d: 0.5, tx: 0, ty: 500)]
        for m in away {
            for mode in BlendMode.allCases {
                var got = base
                try got.composite(layer, through: m, mode: mode, opacity: 1, filter: .lanczos3)
                #expect(got == base, "\(m) \(mode)")
            }
        }
    }

    /// Non-finite or singular matrices and opacities outside 0...1 throw
    /// RasterError and leave the backdrop `==` to a copy taken before, even
    /// when the matrix would map the layer off the backdrop.
    @Test func badInputThrowsAndLeavesBackdrop() throws {
        let layer = try AffineFixtures.layer(seed: 511, width: 16, height: 12, border: 0)
        let before = try backdrop(seed: 512)
        let move = AffineFixtures.translation(3.5, 2.25)
        let cases: [(AffineMatrix, Float)] = [
            (AffineMatrix(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0), 1),
            (AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: .infinity, ty: 0), 1),
            (AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -.infinity), 0.5),
            (AffineFixtures.singular, 1), (AffineMatrix(a: 0, b: 0, c: 0, d: 0, tx: 5, ty: 5), 1),
            (move, 1.5), (move, -0.1), (move, .nan), (move, .infinity),
            (AffineFixtures.translation(1000, 0), 2),
            (AffineMatrix(a: 1, b: 2, c: 2, d: 4, tx: 1000, ty: 0), 1),
        ]
        for (m, opacity) in cases {
            for filter in [ResampleFilter.bilinear, .lanczos3] {
                var got = before
                #expect(throws: RasterError.self, "\(m) \(opacity)") {
                    try got.composite(layer, through: m, mode: .multiply, opacity: opacity, filter: filter)
                }
                #expect(got == before, "\(m) \(opacity) \(filter)")
            }
        }
    }

    /// A finite, invertible matrix whose corners overflow to infinity throws
    /// a message about the corners, not about invertibility.
    @Test func overflowingCornersSayWhy() throws {
        let layer = try PixelBuffer(width: 2, height: 2, fill: RGBA(r: 1, g: 0, b: 0, a: 1))
        let before = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: 0, g: 0, b: 1, a: 1))
        let m = AffineMatrix(a: 1e308, b: 0, c: 0, d: 1e-308, tx: 0, ty: 0)
        #expect(m.inverse != nil)
        var got = before
        let error = #expect(throws: RasterError.self) {
            try got.composite(layer, through: m, mode: .normal, opacity: 1, filter: .bilinear)
        }
        guard case .invalid(let message) = try #require(error) else { return }
        #expect(message.contains("corners") && message.contains("finite range"), "\(message)")
        #expect(!message.contains("finite and invertible"), "\(message)")
        #expect(got == before)
    }

    /// Edges past ±2^52 are clamped before they become Int: a huge finite
    /// matrix gives a box without trapping and composites to nothing.
    @Test func hugeFiniteMatrixIsClampedAndOffBackdrop() throws {
        let far = try #require(AffineFixtures.translation(1e300, -1e300).bounds(of: 4, 4))
        #expect(far.x == 1 << 52 && far.y == -(1 << 52))
        let big = try #require(AffineFixtures.scale(1e300, 1e300).bounds(of: 4, 4))
        #expect((big.x, big.y, big.width, big.height) == (0, 0, 1 << 52, 1 << 52))
        let layer = try AffineFixtures.layer(seed: 521, width: 4, height: 4, border: 0)
        let base = try backdrop(seed: 522)
        for m in [AffineFixtures.translation(1e300, 0), AffineFixtures.translation(-1e300, -1e300)] {
            var got = base
            try got.composite(layer, through: m, mode: .normal, opacity: 1, filter: .lanczos3)
            #expect(got == base, "\(m)")
        }
    }
}
