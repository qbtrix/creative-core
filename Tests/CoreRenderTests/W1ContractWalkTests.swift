// W1ContractWalkTests.swift: engine-contracts EC-9, the render half of KJ-EC.
// One call per W1 RenderBackend method (the masked composite, the three
// `.affine` calls, `applying`, and `adjusted` with each `.color` case) goes
// through a RenderDispatcher whose preferred FakeBackend lists none of the W1
// families. Each must reach the CPU backend (`lastFallback` names its family,
// and the fake only uploads the input), then give the CPU's answer for that
// family on dev: `unsupported(<family>)` from a stub file, or a surface of the
// right size once a feature fills it (`cpuBuilt`).
import CoreColor
import CoreRaster
import CoreRender
import Testing

@Suite struct W1ContractWalkTests {
    /// The W1 families whose `CPUBackend+<Family>.swift` is filled on dev:
    /// Color (tone-pack TP-7) and Affine (affine-composite AC-6).
    /// MaskedComposite and Effect are still stubs; a feature that fills its
    /// file adds its family here.
    static let cpuBuilt: Set<RenderOp> = [.affine, .color]

    /// A fake preferring every family from before W1 and none of the new ones.
    static let oldFamilies = Set(RenderOp.allCases).subtracting(RenderOp.notOnMetalYet)

    let buffer: PixelBuffer
    let mask: Mask
    let shear = AffineMatrix(a: 1, b: 0.25, c: 0, d: 1, tx: 2, ty: -1)

    init() throws {
        var rng = SplitMix64(seed: 429)
        let bytes = (0..<64 * 64 * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
        buffer = try PixelBuffer(rgba8: bytes, width: 64, height: 64)
        mask = try Mask(width: 64, height: 64, fill: 0.5)
    }

    /// One step of the walk: `call` on a fresh dispatcher with the 64 x 64
    /// buffer uploaded (to the fake), checked to reach the CPU for `family`
    /// and give its answer there, a `width` x `height` surface when built.
    private func step(_ family: RenderOp, _ what: String, width: Int = 64, height: Int = 64,
                      _ call: (RenderDispatcher, RenderSurface) throws -> RenderSurface) throws {
        let fake = FakeBackend(supports: Self.oldFamilies)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(buffer)
        #expect(s.backend == "fake")
        if Self.cpuBuilt.contains(family) {
            let out = try call(d, s)
            #expect(out.backend == d.fallback.name, "\(what)")
            let pixels = try d.read(out)
            #expect(pixels.width == width && pixels.height == height, "\(what)")
        } else {
            #expect(throws: RenderError.unsupported(family), "\(what)") { _ = try call(d, s) }
        }
        #expect(d.lastFallback?.op == family, "\(what)")
        #expect(d.lastFallback?.reason == RenderDispatcher.reasonUnsupported, "\(what)")
        // The fake was only asked for the input, never for the op itself.
        #expect(fake.calls == [.surface(width: 64, height: 64), .read(s)], "\(what)")
    }

    /// A CPU backdrop holding the walk's buffer.
    private func backdrop(_ d: RenderDispatcher) throws -> RenderSurface {
        try d.fallback.surface(buffer)
    }

    @Test func walk() throws {
        #expect(Self.oldFamilies.isDisjoint(with: [.maskedComposite, .affine, .effect, .color]))
        try step(.maskedComposite, "masked composite") { d, s in
            var b = try backdrop(d)
            try d.composite(s, onto: &b, x: 0, y: 0, mode: .multiply, opacity: 0.5, mask: mask, maskX: 0, maskY: 0)
            return b
        }
        try step(.affine, "transformed", width: 32, height: 48) { d, s in
            try d.transformed(s, shear, width: 32, height: 48, filter: .bilinear)
        }
        try step(.affine, "flipped") { d, s in try d.flipped(s, .vertical) }
        try step(.affine, "composite through a matrix") { d, s in
            var b = try backdrop(d)
            try d.composite(s, onto: &b, through: shear, mode: .normal, opacity: 0.8, filter: .bilinear)
            return b
        }
        try step(.effect, "effect") { d, s in
            try d.applying(s, .glow(color: RGBA(r: 1, g: 1, b: 0, a: 1), radius: 3, intensity: 0.5, inner: false))
        }
        let colorCases = try W1ContractTests.colorCases()
        #expect(colorCases.count == 11)
        for adjustment in colorCases {
            try step(.color, "\(adjustment)") { d, s in try d.adjusted(s, adjustment) }
        }
    }
}
