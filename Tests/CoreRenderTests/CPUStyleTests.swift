// CPUStyleTests.swift: layer-style-engine LE-2, the `.style` render family.
// `styled` is a RenderBackend requirement routed by `.style`: the CPU stub
// checks the surface, then throws `unsupported(.style)`; a backend without a
// `styled` of its own throws the same; the fake records the stack; and the
// dispatcher sends it to the CPU when the preferred backend lacks `.style`.
// The pixel test waits on LE-5, which fills CPUBackend+Style.swift.
import CoreColor
import CoreRaster
import CoreRender
import Testing

@Suite struct CPUStyleTests {
    let stack = LayerStyleStack(entries: [
        StyleEntry(op: .dropShadow(color: RGBA(r: 0, g: 0, b: 0, a: 0.6), dx: 2, dy: 3, spread: 0, blur: 2)),
        StyleEntry(op: .overlay(.color(RGBA(r: 0.2, g: 0.4, b: 0.8, a: 1))), mode: .multiply, opacity: 0.5),
    ], fillOpacity: 0.75)

    func layer() throws -> PixelBuffer {
        var rng = SplitMix64(seed: 0x57_11E)
        let bytes = (0..<16 * 12 * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        return try PixelBuffer(rgba8: bytes, width: 16, height: 12)
    }

    @Test func cpuStubChecksTheSurfaceThenThrowsUnsupported() throws {
        let cpu = CPUBackend()
        #expect(cpu.supports.contains(.style))
        #expect(RenderOp.notOnMetalYet.contains(.style))
        let input = try layer()
        let s = try cpu.surface(input)
        #expect(throws: RenderError.unsupported(.style)) { _ = try cpu.styled(s, stack) }
        let after = try cpu.read(s)
        #expect(after == input, "s is left unchanged")
        cpu.release(s)
        #expect(throws: RenderError.surfaceMismatch) { _ = try cpu.styled(s, stack) }
    }

    @Test func fakeRecordsTheStackAndHonoursSupports() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases))
        let input = try layer()
        let s = try fake.surface(input)
        let out = try fake.styled(s, stack)
        let pixels = try fake.read(out)
        #expect(out.id != s.id && pixels == input, "a new surface with the pixels unchanged")
        #expect(fake.calls.contains(.styled(stack)))
        let without = FakeBackend(supports: Set(RenderOp.allCases).subtracting([.style]))
        let t = try without.surface(input)
        #expect(throws: RenderError.unsupported(.style)) { _ = try without.styled(t, stack) }
    }

    @Test func dispatcherRoutesStyledByStyleToTheCPU() throws {
        let fake = FakeBackend(supports: Set(RenderOp.allCases).subtracting([.style]))
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(try layer())
        #expect(d.backend(for: .style).name == "cpu")
        #expect(throws: RenderError.unsupported(.style)) { _ = try d.styled(s, stack) }
        #expect(d.lastFallback?.op == .style)
        #expect(d.lastFallback?.reason == RenderDispatcher.reasonUnsupported)
        #expect(!fake.calls.contains(.styled(stack)), "the fake never ran the style")
    }

    @Test(.disabled("waits on LE-5")) func cpuEqualsTheDirectCall() throws {
        let cpu = CPUBackend()
        let input = try layer()
        let out = try cpu.read(cpu.styled(cpu.surface(input), stack))
        let direct = try input.styled(stack)
        #expect(out == direct)
    }
}
