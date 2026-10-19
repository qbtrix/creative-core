// CPUMaskedCompositeTests.swift: masks-mattes MM-5's acceptance. The CPU
// backend's masked composite `==` CoreRaster's in-place masked composite for
// 50 seeded layer, mask and offset sets (non-square, unequal offsets, so
// swapped arguments show), in place on `b`; a released surface throws
// `surfaceMismatch` with `b` unchanged; composites onto one backdrop from many
// tasks apply one at a time, none lost. The goldens are CPUGoldenTests'.
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes, alpha included.
private func maskedLayer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    return try PixelBuffer(rgba8: (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) },
                           width: width, height: height)
}

/// A `width` x `height` mask of seeded coverage, with whole rows of 0 and of 1
/// so the skip and full-row paths run too.
private func seededMask(width: Int, height: Int, seed: UInt64) throws -> Mask {
    var rng = SplitMix64(seed: seed)
    var coverage = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        let kind = Int.random(in: 0..<4, using: &rng)
        for x in 0..<width {
            let a: Float = kind == 0 ? 0 : kind == 1 ? 1 : .random(in: 0...1, using: &rng)
            try coverage.setPixel(x: x, y: y, RGBA(r: 0, g: 0, b: 0, a: a))
        }
    }
    return try Mask(from: coverage, .alpha)
}

@Suite struct CPUMaskedCompositeTests {
    let cpu = CPUBackend()

    @Test
    func equalsDirect() throws {
        var rng = SplitMix64(seed: 0x4D35)
        let modes = BlendMode.allCases
        for i in 0..<50 {
            let seed = UInt64(i) * 4
            let layer = try maskedLayer(width: .random(in: 1...9, using: &rng), height: .random(in: 1...7, using: &rng), seed: seed)
            let backdrop = try maskedLayer(width: 13, height: 8, seed: seed + 1)
            let mask = try seededMask(width: .random(in: 1...11, using: &rng), height: .random(in: 1...6, using: &rng), seed: seed + 2)
            let (x, y) = (Int.random(in: -6...12, using: &rng), Int.random(in: -5...7, using: &rng))
            let (maskX, maskY) = (Int.random(in: -6...10, using: &rng), Int.random(in: -5...6, using: &rng))
            let mode = modes[i % modes.count]
            let opacity: Float = i % 5 == 0 ? 1 : .random(in: 0...1, using: &rng)
            var want = backdrop
            try want.composite(layer, x: x, y: y, mode: mode, opacity: opacity, mask: mask, maskX: maskX, maskY: maskY)
            let s = try cpu.surface(layer)
            var b = try cpu.surface(backdrop)
            let before = b
            try cpu.composite(s, onto: &b, x: x, y: y, mode: mode, opacity: opacity, mask: mask, maskX: maskX, maskY: maskY)
            #expect(b == before, "in place: #\(i)")
            #expect(try cpu.read(b) == want, "#\(i) \(mode) at (\(x), \(y)), mask at (\(maskX), \(maskY))")
            #expect(try cpu.read(s) == layer)
            cpu.release(s)
            cpu.release(b)
        }
    }

    /// A released source or backdrop throws `surfaceMismatch` and the live
    /// backdrop keeps its pixels; a bad opacity throws `RenderError.raster`.
    @Test
    func releasedSurfaceThrowsMismatch() throws {
        let backdrop = try maskedLayer(width: 6, height: 5, seed: 71)
        let mask = try Mask(width: 6, height: 5, fill: 0.5)
        let live = try cpu.surface(try maskedLayer(width: 4, height: 3, seed: 72))
        let released = try cpu.surface(try maskedLayer(width: 4, height: 3, seed: 73))
        cpu.release(released)
        var b = try cpu.surface(backdrop)
        defer { cpu.release(live); cpu.release(b) }
        #expect(throws: RenderError.surfaceMismatch) {
            try cpu.composite(released, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        }
        var gone = try cpu.surface(backdrop)
        cpu.release(gone)
        #expect(throws: RenderError.surfaceMismatch) {
            try cpu.composite(live, onto: &gone, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        }
        #expect(throws: RenderError.self) {
            try cpu.composite(live, onto: &b, x: 0, y: 0, mode: .normal, opacity: .nan, mask: mask, maskX: 0, maskY: 0)
        }
        #expect(try cpu.read(b) == backdrop)
    }

    /// Sixteen tasks composite onto one backdrop, each through a mask on its
    /// own band of rows, four times over: every composite lands, so the result
    /// is the one-at-a-time result (the bands are disjoint, so order is free).
    @Test
    func concurrentCompositesApplyInTurn() async throws {
        let (side, tasks, rounds) = (128, 16, 4)
        let band = side / tasks
        let backdrop = try maskedLayer(width: side, height: side, seed: 81)
        let layer = try maskedLayer(width: side, height: side, seed: 82)
        let mask = try Mask(width: side, height: band, fill: 0.5)
        var want = backdrop
        for t in 0..<tasks {
            for _ in 0..<rounds {
                try want.composite(layer, x: 0, y: 0, mode: .screen, opacity: 0.9, mask: mask, maskX: 0, maskY: t * band)
            }
        }
        let cpu = cpu, s = try cpu.surface(layer), b = try cpu.surface(backdrop)
        defer { cpu.release(s); cpu.release(b) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for t in 0..<tasks {
                group.addTask {
                    var target = b
                    for _ in 0..<rounds {
                        try cpu.composite(s, onto: &target, x: 0, y: 0, mode: .screen, opacity: 0.9,
                                          mask: mask, maskX: 0, maskY: t * band)
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(try cpu.read(b) == want)
    }
}
