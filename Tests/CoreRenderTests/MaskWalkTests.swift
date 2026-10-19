// MaskWalkTests.swift: KJ-MM's raster half (MM-9; the vector half is
// FlareCoreTests' MaskWalkTests, so the filter `MaskWalkTests.walk` runs both).
// A 512 x 512 photo layer and an ellipse mask (radii 200 x 150 about the
// centre) feathered 12 px: the feather keeps the area within 1% and widens
// the covered bounds by the kernel's reach (ceil(12) on every side); its 0.5
// contour is one closed counter-clockwise outline, no step longer than a
// cell's diagonal, every point within 1 px of the ellipse; composited at
// opacity 0.8 onto white through a `RenderDispatcher` on the CPU backend, it
// equals CoreRaster's direct call byte for byte, is the unmasked composite
// where the mask is full and white where it is empty.
import CoreRaster
import CoreRender
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

@Suite struct MaskWalkTests {
    static let side = 512, center = 256.0, radiusX = 200.0, radiusY = 150.0

    @Test func walk() throws {
        // 1. The feathered ellipse: area kept, bounds widened by 12 on each side
        // of the hard mask's (56, 106, 400, 300).
        let hard = try Mask.ellipse(width: Self.side, height: Self.side, centerX: Self.center, centerY: Self.center,
                                    radiusX: Self.radiusX, radiusY: Self.radiusY)
        let mask = try hard.feathered(radius: 12)
        #expect(abs(mask.area - hard.area) <= 0.01 * hard.area, "area \(mask.area) vs \(hard.area)")
        #expect(hard.coveredBounds.map { [$0.x, $0.y, $0.width, $0.height] } == [56, 106, 400, 300])
        #expect(mask.coveredBounds.map { [$0.x, $0.y, $0.width, $0.height] } == [44, 94, 424, 324])

        // 2. Its contour: one closed outline, outer counter-clockwise, no gap.
        let rings = try mask.contours()
        #expect(rings.count == 1)
        let ring = try #require(rings.first)
        var area = 0.0
        for (i, p) in ring.enumerated() {
            let q = ring[(i + 1) % ring.count]
            area += p.x * q.y - q.x * p.y
            #expect(hypot(q.x - p.x, q.y - p.y) <= 2.0.squareRoot(), "gap after point \(i)")
            let r = hypot((p.x - Self.center) / Self.radiusX, (p.y - Self.center) / Self.radiusY)
            #expect(abs(r - 1) * Self.radiusY <= 1, "point \(i) at (\(p.x), \(p.y)) off the ellipse")
        }
        #expect(area > 0 && ring.count > 1000)

        // 3. Through the dispatcher on the CPU backend, equal to the direct call.
        let photo = try AffineWalkTests.photo(width: Self.side, height: Self.side, block: 16, seed: 0x4B4D)
        let white = try PixelBuffer(width: Self.side, height: Self.side, fill: AffineWalkTests.white)
        let dispatcher = RenderDispatcher(preferred: nil, fallback: CPUBackend())
        let s = try dispatcher.surface(photo)
        var b = try dispatcher.surface(white)
        defer { dispatcher.release(s); dispatcher.release(b) }
        try dispatcher.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 0.8, mask: mask, maskX: 0, maskY: 0)
        let got = try dispatcher.read(b)
        var direct = white
        try direct.composite(photo, x: 0, y: 0, mode: .normal, opacity: 0.8, mask: mask, maskX: 0, maskY: 0)
        #expect(AffineWalkTests.same(got, direct))
        #expect(try dispatcher.read(s) == photo)

        // 4. Full coverage is the unmasked composite; no coverage leaves white.
        var plain = white
        try plain.composite(photo, x: 0, y: 0, mode: .normal, opacity: 0.8)
        #expect(try mask.coverage(x: 256, y: 256) == 1 && mask.coverage(x: 0, y: 0) == 0)
        #expect(try got.pixel(x: 256, y: 256) == plain.pixel(x: 256, y: 256))
        #expect(try got.pixel(x: 256, y: 256) != white.pixel(x: 256, y: 256))
        #expect(try got.pixel(x: 0, y: 0) == white.pixel(x: 0, y: 0))
        #expect(try got.pixel(x: 43, y: 256) == white.pixel(x: 43, y: 256))
        #expect(try got.pixel(x: 56, y: 256) != plain.pixel(x: 56, y: 256))
    }
}
