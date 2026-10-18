// CPUEffectTests.swift: effects-engine FX-7's acceptance, written first (FX-1),
// disabled until FX-7 fills both `applying`s: every `LayerEffect` case on the
// CPU backend `==` CoreRaster's, a stroke keeps its position, and a dispatcher
// over a fake without `.effect` sends every case to the CPU.
import CoreRaster
import CoreRender
import Testing

@Suite struct CPUEffectTests {
    let tint = RGBA(r: 0.1, g: 0.2, b: 0.6, a: 0.8)

    /// Every case, both sides of each flag and every stroke position.
    var everyCase: [LayerEffect] {
        let plain: [LayerEffect] = [.boxBlur(radius: 2), .motionBlur(degrees: 30, distance: 5),
                                    .denoise(strength: 0.7, detail: 0.3), .clarity(amount: 40, radius: 6), .clarity(amount: -40, radius: 6)]
        let light: [LayerEffect] = [false, true].flatMap { inner -> [LayerEffect] in
            [.glow(color: tint, radius: 3, intensity: 0.8, inner: inner), .shadow(color: tint, dx: 2, dy: -3, blur: 2, inner: inner)]
        }
        return plain + light + [StrokePosition.outside, .inside, .center].map { .stroke(color: tint, width: 2, position: $0) }
    }

    /// A 24 x 20 layer: seeded colours in an opaque ellipse, transparent outside.
    func layer(seed: UInt64 = 0xEFFC_9) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed)
        var bytes: [UInt8] = []
        for i in 0..<24 * 20 {
            let dx = (Double(i % 24) - 11.5) / 8, dy = (Double(i / 24) - 9.5) / 6, opaque = dx * dx + dy * dy <= 1
            for _ in 0..<3 { bytes.append(opaque ? UInt8(truncatingIfNeeded: rng.next()) : 0) }
            bytes.append(opaque ? 255 : 0)
        }
        return try PixelBuffer(rgba8: bytes, width: 24, height: 20)
    }

    @Test(.disabled("waits on FX-7")) func everyCaseEqualsDirect() throws {
        let cpu = CPUBackend()
        let input = try layer()
        for effect in everyCase {
            let s = try cpu.surface(input)
            let out = try cpu.read(cpu.applying(s, effect))
            #expect(out == (try input.applying(effect)), "\(effect)")
            #expect(out.width == input.width && out.height == input.height)
            #expect(try cpu.read(s) == input, "\(effect) changed its input")
        }
    }

    @Test(.disabled("waits on FX-7")) func strokeKeepsPosition() throws {
        let cpu = CPUBackend()
        let input = try layer(seed: 0x57_80CE)
        var results: [PixelBuffer] = []
        for position: StrokePosition in [.outside, .inside, .center] {
            let effect = LayerEffect.stroke(color: tint, width: 3, position: position)
            let out = try cpu.read(cpu.applying(cpu.surface(input), effect))
            #expect(out == (try input.stroked(color: tint, width: 3, position: position)), "\(position)")
            results.append(out)
        }
        #expect(results.count == 3 && results[0] != results[1] && results[1] != results[2] && results[0] != results[2])
    }

    @Test(.disabled("waits on FX-7")) func dispatcherFallsBackToCPU() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases).subtracting([.effect]))
        let dispatcher = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let input = try layer()
        for effect in everyCase {
            let out = try dispatcher.read(dispatcher.applying(dispatcher.surface(input), effect))
            #expect(out == (try input.applying(effect)), "\(effect)")
            #expect(dispatcher.lastFallback?.op == .effect)
            #expect(dispatcher.lastFallback?.reason == RenderDispatcher.reasonUnsupported)
        }
        #expect(!fake.calls.contains { if case .applying = $0 { true } else { false } })
    }
}
