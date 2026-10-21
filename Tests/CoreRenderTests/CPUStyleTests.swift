// CPUStyleTests.swift: layer-style-engine LE-2 and LE-5, the `.style` render
// family. `styled` is a RenderBackend requirement routed by `.style`: the CPU
// backend checks the surface, leaves it unchanged and draws the stack `==`
// CoreRaster's `styled` for every op and the fill opacity; a backend without a
// `styled` of its own throws `unsupported(.style)`; the fake records the
// stack; and the dispatcher sends it to the CPU when the preferred backend
// lacks `.style`.
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

    @Test func cpuChecksTheSurfaceAndLeavesItUnchanged() throws {
        let cpu = CPUBackend()
        #expect(cpu.supports.contains(.style))
        #expect(RenderOp.notOnMetalYet.contains(.style))
        let input = try layer()
        let s = try cpu.surface(input)
        #expect(throws: RenderError.self) { _ = try cpu.styled(s, LayerStyleStack(entries: [], fillOpacity: .nan)) }
        let out = try cpu.styled(s, stack)
        #expect(out.id != s.id && out.width == s.width && out.height == s.height)
        #expect(try cpu.read(s) == input, "s is left unchanged")
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
        #expect(try d.read(d.styled(s, stack)) == (try layer().styled(stack)))
        #expect(d.lastFallback?.op == .style)
        #expect(d.lastFallback?.reason == RenderDispatcher.reasonUnsupported)
        #expect(!fake.calls.contains(.styled(stack)), "the fake never ran the style")
    }

    /// Every style sample, each `StyleOp` case among them, on the CPU `==` the direct call.
    @Test func everyOpEqualsTheDirectCall() throws {
        let cpu = CPUBackend()
        var kinds: Set<String> = []
        for sample in try ParityHarness.sampleSet(for: .style) {
            guard case .styled(let stack) = sample.call else {
                Issue.record("style/\(sample.name) is not a styled call")
                continue
            }
            let s = try cpu.surface(sample.source)
            #expect(try cpu.read(cpu.styled(s, stack)) == (try sample.source.styled(stack)), "style/\(sample.name)")
            #expect(try cpu.read(s) == sample.source, "style/\(sample.name) changed its input")
            for entry in stack.entries {
                switch entry.op {
                case .dropShadow: kinds.insert("drop-shadow")
                case .innerShadow: kinds.insert("inner-shadow")
                case .outerGlow: kinds.insert("outer-glow")
                case .innerGlow: kinds.insert("inner-glow")
                case let .stroke(_, _, position): kinds.insert("stroke-\(position)")
                case .overlay(.color): kinds.insert("overlay-color")
                case .overlay(.gradient): kinds.insert("overlay-gradient")
                case let .bevel(bevel): kinds.insert("bevel-\(bevel.shape)")
                }
            }
        }
        #expect(kinds.count == 13, "every op, stroke position and bevel shape: \(kinds.sorted())")
    }

    /// The CPU backend passes the stack's fill opacity through: under 1 it fades the layer.
    @Test func fillOpacityKept() throws {
        let cpu = CPUBackend()
        let input = try layer()
        let full = try input.styled(LayerStyleStack(entries: stack.entries))
        for fillOpacity: Float in [0, 0.4, 0.75] {
            let faded = LayerStyleStack(entries: stack.entries, fillOpacity: fillOpacity)
            let out = try cpu.read(cpu.styled(cpu.surface(input), faded))
            #expect(out == (try input.styled(faded)), "fill opacity \(fillOpacity)")
            #expect(out != full, "fill opacity \(fillOpacity) fades the layer")
        }
    }
}
