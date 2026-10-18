// CompositeAffineTests.swift: affine-composite AC-5's acceptance, written first
// (AC-1), disabled by name until AC-5 lands `composite(_:through:...)` and
// `AffineMatrix.bounds`: through-composite equals transform-then-composite
// within 1/255 (`==` for whole-pixel moves) for every BlendMode, rows outside
// the bounds and layers mapped off the backdrop change nothing.
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

    @Test(.disabled("waits on AC-5"))
    func equalsTransformThenComposite() throws {
        var rng = SplitMix64(seed: 501)
        let layers = try AffineFixtures.layers(count: 50, seed: 502)
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

    @Test(.disabled("waits on AC-5"))
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

    @Test(.disabled("waits on AC-5"))
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
            #expect(Double(box.x) >= floor(xs.min() ?? 0) - 1 && Double(box.x + box.width) <= ceil(xs.max() ?? 0) + 1)
            #expect(Double(box.y) >= floor(ys.min() ?? 0) - 1 && Double(box.y + box.height) <= ceil(ys.max() ?? 0) + 1)
        }
        #expect(AffineMatrix(a: .nan, b: 0, c: 0, d: 1, tx: 0, ty: 0).bounds(of: 4, 4) == nil)
        #expect(AffineMatrix(a: 1, b: 0, c: 0, d: 1, tx: .infinity, ty: 0).bounds(of: 4, 4) == nil)
    }

    /// The walk's shape at test size: scaled 0.5, turned 30 degrees, moved.
    /// Bilinear at 0.5 reaches a quarter output pixel past the corners, so a
    /// row wholly outside the bounds has no sample that touches the layer.
    @Test(.disabled("waits on AC-5"))
    func rowsOutsideBoundsAreUntouched() throws {
        let layer = try AffineFixtures.layer(seed: 507, width: 30, height: 20, border: 0)
        let t = Double.pi / 6
        let m = AffineMatrix(a: 0.5 * cos(t), b: 0.5 * sin(t), c: -0.5 * sin(t), d: 0.5 * cos(t), tx: 20, ty: 12)
        let box = try #require(m.bounds(of: layer.width, layer.height))
        let base = try backdrop(seed: 508)
        for mode in [BlendMode.normal, .multiply, .difference, .luminosity] {
            var got = base
            try got.composite(layer, through: m, mode: mode, opacity: 1, filter: .bilinear)
            var changedInside = false
            for y in 0..<base.height {
                let inside = y >= box.y && y < box.y + box.height
                for x in 0..<base.width {
                    guard try got.pixel(x: x, y: y) != base.pixel(x: x, y: y) else { continue }
                    #expect(inside, "\(mode): row \(y) changed outside \(box)")
                    changedInside = changedInside || inside
                }
            }
            #expect(changedInside, "\(mode): nothing changed")
        }
    }

    @Test(.disabled("waits on AC-5"))
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
}
