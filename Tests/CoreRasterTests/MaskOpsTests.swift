// MaskOpsTests.swift: the MM-3 acceptance row. Feathering keeps area and
// range and reads half at a hard edge; contours trace closed outlines (outer
// counter-clockwise, holes clockwise) near the analytic shape, resolve a
// saddle by its cell mean; covered bounds are exact. Plus a seeded fuzz of
// NaN, infinite and huge feather radii.
import CoreRaster
import Testing

@Suite struct MaskOpsTests {
    @Test func radiusZeroReturnsSelf() throws {
        #expect(try MaskFixtures.square().feathered(radius: 0) == MaskFixtures.square())
    }

    @Test func featherKeepsArea() throws {
        #expect(abs(try MaskFixtures.square().feathered(radius: 6).area - 4096) <= 4096 * 0.01)
    }

    /// Sigma 2: the pixel centred 0.5 px inside reads Φ(0.25) ≈ 0.599, the one outside 1 − that.
    @Test func edgeIsHalfAtTheEdge() throws {
        let feathered = try MaskFixtures.square().feathered(radius: 6)
        let inside = try feathered.coverage(x: 16, y: 48), outside = try feathered.coverage(x: 15, y: 48)
        #expect(abs(inside - 0.5987) < 0.005)
        #expect(abs(outside - 0.4013) < 0.005)
        #expect(abs((inside + outside) / 2 - 0.5) < 0.001)
    }

    @Test func featherStaysInRange() throws {
        var rng = SplitMix64(seed: 0x3A5C)
        for _ in 0..<20 {
            let mask = MaskFixtures.random(width: 17, height: 11, &rng)
            let values = try MaskFixtures.all(mask.feathered(radius: .random(in: 0.5...30, using: &rng)))
            #expect(values.allSatisfy { (0...1).contains($0) })
        }
        let full = try Mask(width: 9, height: 5, fill: 1)
        #expect(try full.feathered(radius: 4) == full)
    }

    /// The vertical pass uses the column length: a tall mask feathers like its transpose.
    @Test func tallMaskFeathersLikeItsTranspose() throws {
        var rng = SplitMix64(seed: 0x7A11)
        let w = 7, h = 19
        let tall = MaskFixtures.random(width: w, height: h, &rng)
        let tallValues = try MaskFixtures.all(tall)
        let wide = MaskFixtures.values(width: h, height: w, (0..<(w * h)).map { i in tallValues[(i % h) * w + i / h] })
        let a = try tall.feathered(radius: 9), b = try wide.feathered(radius: 9)
        for y in 0..<h {
            for x in 0..<w {
                #expect(abs(try a.coverage(x: x, y: y) - b.coverage(x: y, y: x)) < 1e-6)
            }
        }
    }

    @Test func badRadiusThrows() throws {
        let square = try MaskFixtures.square()
        for radius in [Double.nan, .infinity, -.infinity, -1, 1e300] {
            #expect(throws: RasterError.self) { try square.feathered(radius: radius) }
        }
    }

    @Test func ringHasTwoClosedOutlinesOnItsCircles() throws {
        let outlines = try MaskFixtures.ring().contours()
        #expect(outlines.count == 2)
        let c = MaskFixtures.ringCenter
        let outer = outlines.filter { MaskFixtures.signedArea($0) > 0 }
        let inner = outlines.filter { MaskFixtures.signedArea($0) < 0 }
        #expect(outer.count == 1 && inner.count == 1)
        for (rings, radius) in [(outer, MaskFixtures.ringOuter), (inner, MaskFixtures.ringInner)] {
            for ring in rings {
                #expect(ring.count > 20)
                for p in ring {
                    let d = ((p.x - c) * (p.x - c) + (p.y - c) * (p.y - c)).squareRoot()
                    #expect(abs(d - radius) <= 0.5)
                }
                expectClosed(ring)
            }
        }
    }

    @Test func ellipseIsOneCounterClockwiseOutline() throws {
        let outlines = try MaskFixtures.ellipse().contours()
        #expect(outlines.count == 1)
        for ring in outlines {
            #expect(abs(MaskFixtures.signedArea(ring) - Double.pi * 18 * 10) < Double.pi * 18 * 10 * 0.02)
            expectClosed(ring)
        }
    }

    /// A saddle joins the pair its mean sides with: mean 0.55 joins the high diagonal, 0.45 splits it.
    @Test func saddleFollowsMean() {
        #expect(MaskFixtures.saddle(diagonal: 0.9, anti: 0.2).contours().count == 1)
        #expect(MaskFixtures.saddle(diagonal: 0.6, anti: 0.3).contours().count == 2)
        #expect(MaskFixtures.saddle(diagonal: 0.2, anti: 0.9).contours().count == 1)
        #expect(MaskFixtures.saddle(diagonal: 0.3, anti: 0.6).contours().count == 2)
    }

    @Test func emptyMaskHasNoContoursAndNoBounds() throws {
        let empty = try Mask(width: 8, height: 8)
        #expect(empty.contours().isEmpty && empty.coveredBounds == nil)
    }

    @Test func boundsAreExact() throws {
        let block = try Mask.rectangle(width: 20, height: 16, x: 3, y: 7, w: 10, h: 4)
        let bounds = try #require(block.coveredBounds)
        #expect(bounds.x == 3 && bounds.y == 7 && bounds.width == 10 && bounds.height == 4)
    }

    /// 200 seeded masks and NaN, infinite, huge or ordinary radii: feather throws or stays in 0...1.
    @Test func fuzz() throws {
        var rng = SplitMix64(seed: 0xFEA7)
        let odd: [Double] = [.nan, .infinity, -.infinity, -0.5, 1e9, .greatestFiniteMagnitude, 0]
        for i in 0..<200 {
            let mask = MaskFixtures.random(width: Int.random(in: 1...12, using: &rng),
                                           height: Int.random(in: 1...12, using: &rng), &rng)
            let radius = i % 2 == 0 ? odd[Int(rng.next() % UInt64(odd.count))] : .random(in: 0...40, using: &rng)
            if let out = try? mask.feathered(radius: radius) {
                #expect(try MaskFixtures.all(out).allSatisfy { (0...1).contains($0) })
            }
            for ring in mask.contours(level: .random(in: -0.5...1.5, using: &rng)) {
                expectClosed(ring)
            }
        }
    }

    /// A radius whose sigma squared underflows keeps the mask, every value in 0...1 (no NaN weights).
    @Test func underflowingRadiusKeepsTheMask() throws {
        let full = try Mask(width: 8, height: 8, fill: 1)
        var rng = SplitMix64(seed: 0x71E7)
        let random = MaskFixtures.random(width: 9, height: 6, &rng)
        for mask in [full, random] {
            let out = try mask.feathered(radius: 1e-200)
            #expect(try MaskFixtures.all(out).allSatisfy { (0...1).contains($0) })
            #expect(out == mask)
        }
    }

    /// Between samples 0 and 0.75 the 0.5 crossing sits 2/3 of the way, not at the midpoint.
    @Test func crossingInterpolatesTheLevel() throws {
        let rings = MaskFixtures.values(width: 2, height: 1, [0, 0.75]).contours(level: 0.5)
        let ring = try #require(rings.first)
        #expect(rings.count == 1)
        #expect(ring.contains { abs($0.x - (0.5 + 2.0 / 3)) < 1e-6 && abs($0.y - 0.5) < 1e-9 })
        #expect(ring.contains { abs($0.x - 1.5) < 1e-9 && abs($0.y - (-0.5 + 2.0 / 3)) < 1e-6 })
    }

    /// A checkerboard just past the 4,000,000-segment cap (`Mask.maxContourSegments`) throws instead of building billions of links.
    @Test func checkerboardOverTheSegmentCapThrows() throws {
        // Every inner cell is a saddle with 2 segments: 2 x 1421² ≈ 4.04 million.
        let n = 1420
        let board = MaskFixtures.values(width: n, height: n, (0..<(n * n)).map { i in Float((i % n + i / n) % 2) })
        #expect(2 * (n + 1) * (n + 1) > 4_000_000)
        #expect(throws: RasterError.self) { _ = try board.contours() }
    }

    /// Consecutive points, last to first included, sit in neighbouring cells: no gap.
    private func expectClosed(_ ring: [Mask.Point]) {
        #expect(ring.count >= 3)
        guard var previous = ring.last else { return }
        for p in ring {
            let step = ((p.x - previous.x) * (p.x - previous.x) + (p.y - previous.y) * (p.y - previous.y)).squareRoot()
            #expect(step <= 2.0.squareRoot() + 1e-9)
            previous = p
        }
    }
}
