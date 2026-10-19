// FloodFillTests.swift: fill-tools FT-3's acceptance, written first (FT-1) and
// turned on with `floodMask` (FT-3). `FillCheck` is shared with ColorRangeTests.
import CoreColor
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum FillCheck {
    /// The packet's colour distance: Euclidean OKLab distance of the straight
    /// colours, alpha difference as a fourth axis. Pixels are premultiplied linear.
    static func distance(_ p: RGBA, _ q: RGBA) throws -> Double {
        let (sp, sq) = (p.unpremultiplied(), q.unpremultiplied())
        func lab(_ s: RGBA) throws -> Color3 { try Color3(Double(s.r), Double(s.g), Double(s.b)).converted(from: .linearSRGB, to: .oklab) }
        let (lp, lq) = (try lab(sp), try lab(sq))
        let (d0, d1, d2, da) = (lp.c0 - lq.c0, lp.c1 - lq.c1, lp.c2 - lq.c2, Double(sp.a - sq.a))
        return (d0 * d0 + d1 * d1 + d2 * d2 + da * da).squareRoot()
    }

    /// Every pixel of `rect`, row by row.
    static func pixels(_ rect: FillRect) -> [(x: Int, y: Int)] {
        (rect.y..<(rect.y + rect.height)).flatMap { y in (rect.x..<(rect.x + rect.width)).map { (x: $0, y: y) } }
    }

    /// The ring around `rect` without its four corners: the pixels that share an edge with it.
    static func edgeRing(_ rect: FillRect) -> [(x: Int, y: Int)] {
        let outer = FillRect(x: rect.x - 1, y: rect.y - 1, width: rect.width + 2, height: rect.height + 2)
        let (columns, rows) = (rect.x..<(rect.x + rect.width), rect.y..<(rect.y + rect.height))
        return pixels(outer).filter { rect.ringContains(x: $0.x, y: $0.y) && (columns.contains($0.x) || rows.contains($0.y)) }
    }
}

@Suite struct FloodFillTests {
    private func cover(_ mask: Mask, _ p: (x: Int, y: Int)) throws -> Float { try mask.coverage(x: p.x, y: p.y) }

    @Test
    func regionCoversExactlyItsInterior() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1))
        #expect(mask.width == scene.buffer.width && mask.height == scene.buffer.height)
        #expect(mask == (try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1))))  // deterministic
        for y in 0..<mask.height {
            for x in 0..<mask.width where !scene.regionB.ringContains(x: x, y: y) {
                let want: Float = scene.regionB.contains(x: x, y: y) ? 1 : 0
                #expect(try mask.coverage(x: x, y: y) == want, "(\(x), \(y))")
            }
        }
    }

    /// The B ring is a half-and-half mix of A and B, about 0.197 from B in
    /// OKLab, so the soft edge `1 - (d - t) / t` is one half at t = d / 1.5.
    @Test
    func borderHalfCovered() throws {
        let scene = try FillScene()
        let d = try FillCheck.distance(FillScene.border(FillScene.colorB), FillScene.colorB)
        let t = Float(d / 1.5)
        let soft = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(t))
        let hard = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(t), antiAlias: false)
        let want = 1 - (d - Double(t)) / Double(t)
        #expect(abs(want - 0.5) < 1e-6)
        for p in FillCheck.edgeRing(scene.regionB) {
            #expect(abs(Double(try cover(soft, p)) - want) < 1e-3, "(\(p.x), \(p.y))")
            #expect(try cover(hard, p) == 0, "(\(p.x), \(p.y))")
        }
        for p in FillCheck.pixels(scene.regionB) { #expect(try cover(soft, p) == 1) }
        #expect(try cover(soft, (x: scene.regionB.x - 2, y: scene.seedB.y)) == 0)
    }

    @Test
    func exactStopsAtFirstAntiAliasedPixel() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.floodMask(from: scene.seedB, tolerance: .exact, antiAlias: false)
        for p in FillCheck.pixels(scene.regionB) { #expect(try cover(mask, p) == 1) }
        for p in FillCheck.edgeRing(scene.regionB) { #expect(try cover(mask, p) == 0, "(\(p.x), \(p.y))") }
        #expect(mask.area == Double(scene.regionB.width * scene.regionB.height))
    }

    /// `within(0)` takes a distance of exactly 0: `d <= t`, never `d < t`.
    @Test
    func toleranceIsInclusive() throws {
        let flat = try FillFixtures.singleColor(FillScene.colorC, width: 5, height: 3)
        let all = try flat.floodMask(from: (x: 2, y: 1), tolerance: .within(0), antiAlias: false)
        #expect(all.area == 15)
        let scene = try FillScene()
        let region = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0), antiAlias: false)
        #expect(region == (try scene.buffer.floodMask(from: scene.seedB, tolerance: .exact, antiAlias: false)))
        #expect(region.area == Double(scene.regionB.width * scene.regionB.height))
    }

    @Test
    func globalIncludesDisconnectedTwin() throws {
        let scene = try FillScene()
        let local = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1), antiAlias: false)
        let global = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1), contiguous: false,
                                                antiAlias: false)
        for p in FillCheck.pixels(scene.twinB) {
            #expect(try cover(local, p) == 0)
            #expect(try cover(global, p) == 1)
        }
        #expect(global.area == 2 * local.area)
    }

    @Test
    func fourConnectedStopsAtDiagonal() throws {
        let scene = try FillScene()
        let (d0, d1) = scene.diagonalPair
        let seed = (x: d0.x, y: d0.y)
        let four = try scene.buffer.floodMask(from: seed, tolerance: .exact, connectivity: .four, antiAlias: false)
        let eight = try scene.buffer.floodMask(from: seed, tolerance: .exact, connectivity: .eight, antiAlias: false)
        for p in FillCheck.pixels(d0) {
            #expect(try cover(four, p) == 1)
            #expect(try cover(eight, p) == 1)
        }
        for p in FillCheck.pixels(d1) {
            #expect(try cover(four, p) == 0, "4-connected leaked through the corner at (\(p.x), \(p.y))")
            #expect(try cover(eight, p) == 1)
        }
        #expect(four.area == Double(d0.width * d0.height))
        #expect(eight.area == 2 * four.area)
    }

    @Test
    func badSeedOrToleranceThrows() throws {
        let scene = try FillScene()
        for seed in [(x: 64, y: 0), (x: 0, y: 48), (x: -1, y: 5), (x: 3, y: -1), (x: Int.max, y: Int.min)] {
            #expect(throws: RasterError.self) { try scene.buffer.floodMask(from: seed, tolerance: .within(0.1)) }
        }
        for t: Float in [-0.01, 1.01, .nan, .infinity] {
            #expect(throws: RasterError.self) { try scene.buffer.floodMask(from: scene.seedA, tolerance: .within(t)) }
        }
    }

    /// Seeded seeds and tolerances, in and out of range: a fill throws
    /// `RasterError` or gives a buffer-sized mask with coverage in 0...1.
    @Test
    func fuzzedArgumentsThrowOrStayInRange() throws {
        let scene = try FillScene(width: 32, height: 24)
        var rng = SplitMix64(seed: 0xF7_03)
        for _ in 0..<200 {
            let seed = (x: Int.random(in: -3...35, using: &rng), y: Int.random(in: -3...27, using: &rng))
            let tolerance: FillTolerance = Bool.random(using: &rng) ? .exact : .within(.random(in: -0.2...1.2, using: &rng))
            do {
                let mask = try scene.buffer.floodMask(from: seed, tolerance: tolerance, contiguous: .random(using: &rng),
                                                      connectivity: Bool.random(using: &rng) ? .four : .eight,
                                                      antiAlias: .random(using: &rng))
                #expect(mask.width == 32 && mask.height == 24 && (0...768).contains(mask.area))
            } catch is RasterError {
                continue
            }
        }
    }

    /// 100 MP of one colour: the fill takes every pixel with peak memory past
    /// the input and the 4-byte-per-pixel mask of at most 2 bytes per pixel.
    /// The buffer is built inside the body, so skipping the case costs nothing.
    @Test
    func worstCaseMemory() throws {
        let image = try FillFixtures.singleColor()
        let pixels = FillFixtures.largeSide * FillFixtures.largeSide
        let before = peakResidentBytes()
        let mask = try image.floodMask(from: (x: 0, y: 0), tolerance: .exact, antiAlias: false)
        let extra = peakResidentBytes() - before
        #expect(mask.area == Double(pixels))
        #expect(extra <= 6 * pixels, "peak grew \(extra) bytes for \(pixels) pixels")
    }

    /// The process's peak resident size in bytes (`ru_maxrss` is KiB on Linux, bytes on Darwin).
    private func peakResidentBytes() -> Int {
        var usage = rusage()
        #if canImport(Darwin)
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return Int(usage.ru_maxrss)
        #else
        guard getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage) == 0 else { return 0 }
        return Int(usage.ru_maxrss) * 1024
        #endif
    }
}
