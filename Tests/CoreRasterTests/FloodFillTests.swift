// FloodFillTests.swift: fill-tools FT-3's acceptance, written first (FT-1) and
// turned on with `floodMask` (FT-3). `FillCheck` is shared with ColorRangeTests.
import CoreColor
@testable import CoreRaster
import Foundation
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

    /// The packet's FT-3 claim: at tolerance 0.1 the fill covers B's interior
    /// and half-covers its border. The B ring sits 0.15 from B in OKLab, so
    /// the soft edge `1 - (d - t) / t` is one half at t = 0.1.
    @Test
    func borderHalfCovered() throws {
        let scene = try FillScene()
        let d = try FillCheck.distance(FillScene.border(FillScene.colorB), FillScene.colorB)
        #expect(abs(d - 0.15) < 1e-4, "ring distance \(d)")
        let soft = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1))
        let hard = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1), antiAlias: false)
        for p in FillCheck.edgeRing(scene.regionB) {
            #expect(abs(Double(try cover(soft, p)) - 0.5) < 1e-3, "(\(p.x), \(p.y))")
            #expect(try cover(hard, p) == 0, "(\(p.x), \(p.y))")
        }
        for p in FillCheck.pixels(scene.regionB) { #expect(try cover(soft, p) == 1) }
        #expect(try cover(soft, (x: scene.regionB.x - 2, y: scene.seedB.y)) == 0)
    }

    /// A rejected neighbour more than 2t away gets 0, not a negative coverage:
    /// the B ring is 0.15 from B, past 2 x 0.05.
    @Test
    func softEdgeClampsAtZero() throws {
        let scene = try FillScene()
        let mask = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.05))
        for p in FillCheck.edgeRing(scene.regionB) { #expect(try cover(mask, p) == 0, "(\(p.x), \(p.y))") }
        #expect(mask.area == Double(scene.regionB.width * scene.regionB.height))
    }

    /// The soft edge follows the connectivity: a ring corner touches B only
    /// diagonally, so `.four` leaves it at 0 and `.eight` half-covers it.
    @Test
    func softEdgeFollowsConnectivity() throws {
        let scene = try FillScene()
        let b = scene.regionB
        let corners = [(x: b.x - 1, y: b.y - 1), (x: b.x + b.width, y: b.y - 1),
                       (x: b.x - 1, y: b.y + b.height), (x: b.x + b.width, y: b.y + b.height)]
        let four = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1), connectivity: .four)
        let eight = try scene.buffer.floodMask(from: scene.seedB, tolerance: .within(0.1), connectivity: .eight)
        for p in corners {
            #expect(try cover(four, p) == 0, "(\(p.x), \(p.y))")
            #expect(abs(try cover(eight, p) - 0.5) < 1e-3, "(\(p.x), \(p.y))")
        }
    }

    /// Anti-aliasing needs a tolerance: `.exact` and `.within(0)` stay hard.
    @Test
    func exactIgnoresAntiAlias() throws {
        let scene = try FillScene()
        for tolerance: FillTolerance in [.exact, .within(0)] {
            let soft = try scene.buffer.floodMask(from: scene.seedB, tolerance: tolerance, antiAlias: true)
            #expect(soft == (try scene.buffer.floodMask(from: scene.seedB, tolerance: tolerance, antiAlias: false)))
        }
    }

    /// Alpha is a fourth axis and colours are compared straight: B at alpha
    /// 0.8 is 0.2 from B at alpha 1, never darker for being premultiplied.
    @Test
    func alphaIsFourthAxis() throws {
        let image = try FillFixtures.alphaPair()
        let near = try image.floodMask(from: (x: 0, y: 0), tolerance: .within(0.1), antiAlias: false)
        #expect(near.area == 2)
        let far = try image.floodMask(from: (x: 0, y: 0), tolerance: .within(0.25), antiAlias: false)
        #expect(far.area == 4)
    }

    /// A pixel with no OKLab value throws an error that says where it is.
    @Test
    func nanPixelNamesLocation() throws {
        var storage = [Float](repeating: 0.5, count: 6 * 4 * 4)
        storage[4 * (2 * 6 + 3)] = .nan
        let image = PixelBuffer(checkedWidth: 6, height: 4, storage: storage)
        do {
            _ = try image.floodMask(from: (x: 2, y: 2), tolerance: .within(0.1))
            Issue.record("a NaN pixel next to the seed did not throw")
        } catch let RasterError.invalid(message) {
            #expect(message.contains("(3, 2)"), "\(message)")
        }
        #expect(throws: RasterError.self) { try image.colorRangeMask(around: FillScene.colorA, fuzziness: 0.2) }
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
                for y in 0..<24 {
                    for x in 0..<32 { #expect((0...1).contains(try mask.coverage(x: x, y: y)), "(\(x), \(y))") }
                }
            } catch is RasterError {
                continue
            }
        }
    }

    /// 100 MP of one colour: the fill takes every pixel with peak memory past
    /// the input and the 4-byte-per-pixel mask of at most 2 bytes per pixel.
    /// The buffer is built inside the body, so skipping the case costs nothing.
    /// The peak is process-wide and other suites run alongside, so the
    /// high-water mark restarts before each fill and the smallest of up to
    /// three fills counts: another suite's allocation is transient. Linux only:
    /// Darwin's `ru_maxrss` is a lifetime peak that cannot be restarted, so an
    /// earlier suite's higher peak would hide the fill's growth there. A
    /// missing measurement fails rather than passes.
    @Test(.enabled(if: PeakResident.canRestart, "the resident peak restarts on Linux only"))
    func worstCaseMemory() throws {
        let image = try FillFixtures.singleColor()
        let pixels = FillFixtures.largeSide * FillFixtures.largeSide
        var extra = Int.max
        for _ in 0..<3 where extra > 6 * pixels {
            let before = try #require(PeakResident.restart(), "could not restart the resident peak")
            #expect(before > 0)
            let mask = try image.floodMask(from: (x: 0, y: 0), tolerance: .exact, antiAlias: false)
            let after = PeakResident.bytes()
            #expect(after >= before)
            extra = min(extra, after - before)
            #expect(mask.area == Double(pixels))
        }
        #expect(extra <= 6 * pixels, "peak grew \(extra) bytes for \(pixels) pixels")
    }
}

/// The process's resident high-water mark in bytes.
private enum PeakResident {
    /// Whether the platform can restart the high-water mark (Linux).
    static var canRestart: Bool {
        #if os(Linux)
        true
        #else
        false
        #endif
    }

    /// Restarts the high-water mark at what is resident now and returns the
    /// mark to measure from, or nil when it cannot restart or read it.
    static func restart() -> Int? {
        #if os(Linux)
        let fd = open("/proc/self/clear_refs", O_WRONLY)
        guard fd >= 0 else { return nil }
        let wrote = write(fd, "5", 1)
        close(fd)
        guard wrote == 1 else { return nil }
        let mark = bytes()
        return mark > 0 ? mark : nil
        #else
        return nil
        #endif
    }

    /// Linux's `VmHWM` (KiB in /proc/self/status), or 0 when it cannot be read.
    static func bytes() -> Int {
        #if os(Linux)
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8),
              let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmHWM:") }),
              let kb = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).dropFirst().first.flatMap({ Int($0) })
        else { return 0 }
        return kb * 1024
        #else
        return 0
        #endif
    }
}
