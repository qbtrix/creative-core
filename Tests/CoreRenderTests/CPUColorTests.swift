// CPUColorTests.swift: tone-pack TP-7's acceptance, written first (TP-1 of
// docs/blueprints/core/features/tone-pack.md). Each `.color` case on the CPU
// backend equals its CoreRaster call, the LUT is applied once, and a
// dispatcher over a fake with `.adjust` only sends colour to the CPU and
// `contrast` to the fake.
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

/// A 2³ warm look: red lifted, blue lowered, so applying it twice differs from once.
private func warmLUT() throws -> ColorLUT {
    try ColorLUT(size: 2, table: (0..<8).map { (i: Int) -> SIMD3<Float> in
        let r = Float(i % 2), g = Float(i / 2 % 2), b = Float(i / 4)
        return SIMD3(0.08 + 0.92 * r, 0.03 + 0.95 * g, 0.9 * b)
    })
}

@Suite struct CPUColorTests {
    /// Every `.color` case with the direct CoreRaster call it must equal.
    static func cases() throws -> [(ToneAdjustment, (PixelBuffer) throws -> PixelBuffer)] {
        let lut = try warmLUT()
        let stops = [GradientMapStop(offset: 0, color: RGBA(r: 0.1, g: 0, b: 0.3, a: 1)),
                     GradientMapStop(offset: 1, color: RGBA(r: 1, g: 0.9, b: 0.6, a: 1))]
        let mix = ChannelMatrix(red: [0.8, 0.2, 0, 0], green: [0, 1, 0, 0.05], blue: [0.1, 0, 0.9, 0], monochrome: false)
        let balance = ToneBalance(shadows: [10, 0, -10], midtones: .zero, highlights: [0, 0, 15], preserveLuminosity: true)
        let hsl = HSLAdjustment(blues: HSLShift(saturation: -20))
        return [
            (.vibrance(30), { try $0.vibrance(30) }),
            (.hueSaturation(hue: 20, saturation: -15, lightness: 10), {
                try $0.hueSaturation(hue: 20, saturation: -15, lightness: 10)
            }),
            (.hsl(hsl), { try $0.hsl(hsl) }),
            (.blackAndWhite(GrayMix()), { try $0.blackAndWhite(GrayMix()) }),
            (.channelMixer(mix), { try $0.channelMixer(mix) }),
            (.colorBalance(balance), { try $0.colorBalance(balance) }),
            (.gradientMap(stops), { try $0.gradientMap(stops) }),
            (.lut(lut), { try $0.applying(lut) }),
            (.posterize(levels: 4), { try $0.posterized(levels: 4) }),
            (.threshold(0.5), { try $0.thresholded(0.5) }),
            (.invert, { $0.inverted() }),
        ]
    }

    @Test func everyCaseEqualsDirect() throws {
        let cpu = CPUBackend()
        let input = try seededBuffer(width: 12, height: 9, seed: 0xE1)
        let s = try cpu.surface(input)
        let all = try Self.cases()
        #expect(all.count == 11)
        for (adjustment, direct) in all {
            #expect(adjustment.family == .color, "\(adjustment)")
            #expect(try cpu.read(cpu.adjusted(s, adjustment)) == direct(input), "\(adjustment)")
        }
        #expect(try cpu.read(s) == input)
    }

    @Test func lutOnce() throws {
        let cpu = CPUBackend()
        let input = try seededBuffer(width: 8, height: 8, seed: 0xE2)
        let lut = try warmLUT()
        let out = try cpu.read(cpu.adjusted(cpu.surface(input), .lut(lut)))
        #expect(out == (try input.applying(lut)))
        #expect(out != (try input.applying(lut).applying(lut)))
    }

    @Test func dispatcherSendsColorToCPU() throws {
        let fake = FakeBackend(supports: [.adjust])
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let input = try seededBuffer(width: 6, height: 5, seed: 0xE3)
        let s = try d.surface(input)
        #expect(s.backend == "fake")
        let vivid = try d.adjusted(s, .vibrance(30))
        #expect(vivid.backend == d.fallback.name)
        #expect(try d.read(vivid) == input.vibrance(30))
        #expect(try d.adjusted(s, .contrast(20)).backend == "fake")
        #expect(fake.calls.filter { $0 == .op(.adjust) }.count == 1)
    }
}
