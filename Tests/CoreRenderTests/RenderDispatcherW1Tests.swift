// RenderDispatcherW1Tests.swift: engine-contracts EC-4's acceptance. Each W1
// method routes by its own family: with a fake preferring every old family,
// each reaches the CPU (its input read from the fake and uploaded) and records
// `(<family>, "unsupported")`; `adjusted` routes by `ToneAdjustment.family`;
// the masked composite is never routed by its blend mode; and the two W1
// composites move a backdrop the way `composite` does. The CPU's masked
// composite is built (masks-mattes MM-5), so its fallbacks land pixels.
import CoreColor
import CoreRaster
import CoreRender
import Testing

/// A `width` x `height` buffer of seeded sRGB bytes.
private func seededBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    let bytes = (0..<width * height * 4).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
    return try PixelBuffer(rgba8: bytes, width: width, height: height)
}

/// Every family from before W1.
private let oldFamilies = Set(RenderOp.allCases).subtracting(RenderOp.notOnMetalYet)

private func fallback(_ d: RenderDispatcher) -> String? {
    d.lastFallback.map { "\($0.op.rawValue) \($0.reason)" }
}

/// A fake that runs the two W1 composites (checking both surfaces, leaving
/// `b` alone) and forwards everything else to a `FakeBackend`.
private struct CompositingFake: RenderBackend {
    let inner: FakeBackend
    var name: String { inner.name }
    var supports: Set<RenderOp> { inner.supports }
    var isHealthy: Bool { inner.isHealthy }

    func surface(_ buffer: PixelBuffer) throws -> RenderSurface { try inner.surface(buffer) }
    func read(_ surface: RenderSurface) throws -> PixelBuffer { try inner.read(surface) }
    func release(_ surface: RenderSurface) { inner.release(surface) }
    func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        try inner.display(s, colorSpace: colorSpace)
    }
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int,
                   mode: BlendMode, opacity: Float) throws {
        try inner.composite(s, onto: &b, x: x, y: y, mode: mode, opacity: opacity)
    }
    func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        try inner.cropped(s, x: x, y: y, width: width, height: height)
    }
    func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface { try inner.rotated(s, turn) }
    func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        try inner.resampled(s, width: width, height: height, filter: filter)
    }
    func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface { try inner.gaussianBlur(s, sigma: sigma) }
    func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        try inner.unsharpMask(s, amount: amount, sigma: sigma, threshold: threshold)
    }
    func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        try inner.adjusted(s, adjustment)
    }
    func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        try inner.cloned(s, offset: offset, through: mask)
    }
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode,
                   opacity: Float, mask: Mask, maskX: Int, maskY: Int) throws {
        _ = try inner.read(s)
        _ = try inner.read(b)
    }
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                   opacity: Float, filter: ResampleFilter) throws {
        _ = try inner.read(s)
        _ = try inner.read(b)
    }
}

@Suite struct RenderDispatcherW1Tests {
    let mask: Mask
    let shear = AffineMatrix(a: 1, b: 0.25, c: 0, d: 1, tx: 2, ty: -1)

    init() throws {
        mask = try Mask(width: 4, height: 3, fill: 0.5)
    }

    /// `backdrop` after CoreRaster's masked composite of `source` with `mode`
    /// at (`x`, `y`), opacity 1 unless given, the mask at (0, 0) unless given.
    private func direct(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int = 0, y: Int = 0, mode: BlendMode,
                        opacity: Float = 1, maskX: Int = 0, maskY: Int = 0) throws -> PixelBuffer {
        var out = backdrop
        try out.composite(source, x: x, y: y, mode: mode, opacity: opacity, mask: mask, maskX: maskX, maskY: maskY)
        return out
    }

    /// With a fake preferring every old family, `s` made on the fake and a
    /// CPU backdrop `b`, the masked composite falls back to the CPU: the
    /// fallback is recorded, `s` is read from the fake for the upload, and `b`
    /// keeps its handle and takes the direct composite's pixels.
    @Test func eachNewMethodReachesTheCPU() throws {
        let fake = FakeBackend(supports: oldFamilies)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let (source, backdrop) = (try seededBuffer(width: 4, height: 3, seed: 1), try seededBuffer(width: 6, height: 5, seed: 2))
        let s = try d.surface(source)
        var b = try d.fallback.surface(backdrop)
        let handle = b
        #expect(s.backend == "fake")
        try d.composite(s, onto: &b, x: 1, y: 0, mode: .multiply, opacity: 0.5, mask: mask, maskX: 0, maskY: 1)
        #expect(fallback(d) == "maskedComposite \(RenderDispatcher.reasonUnsupported)")
        #expect(fake.calls.contains(.read(s)))
        #expect(b == handle)
        #expect(try d.read(b) == direct(source, onto: backdrop, x: 1, mode: .multiply, opacity: 0.5, maskY: 1))
    }

    @Test func colorCasesFallBack() throws {
        let fake = FakeBackend(supports: oldFamilies)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let s = try d.surface(seededBuffer(width: 5, height: 4, seed: 13))
        #expect(try d.adjusted(s, .contrast(0.2)).backend == "fake")
        #expect(d.lastFallback == nil)
        #expect(fake.calls.contains(.op(.adjust)))
        for color: ToneAdjustment in [.vibrance(0.3), .invert, .posterize(levels: 4), .threshold(0.5)] {
            #expect(try d.adjusted(s, color).backend == d.fallback.name)  // built by tone-pack TP-7
            #expect(fallback(d) == "color \(RenderDispatcher.reasonUnsupported)")
        }
        #expect(fake.calls.filter { $0 == .op(.adjust) }.count == 1)
        #expect(fake.calls.filter { $0 == .read(s) }.count == 4)
        // A preferred backend that lists `.color` gets the colour cases.
        let colorFake = FakeBackend(supports: oldFamilies.union([.color]))
        let e = RenderDispatcher(preferred: colorFake, fallback: CPUBackend())
        #expect(try e.adjusted(e.surface(seededBuffer(width: 5, height: 4, seed: 14)), .vibrance(0.3)).backend == "fake")
        #expect(e.lastFallback == nil)
    }

    @Test(arguments: [BlendMode.normal, .multiply, .hue])
    func maskedCompositeIsItsOwnFamily(mode: BlendMode) throws {
        let fake = FakeBackend(supports: oldFamilies)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let (source, backdrop) = (try seededBuffer(width: 4, height: 3, seed: 15), try seededBuffer(width: 6, height: 5, seed: 16))
        let s = try d.fallback.surface(source)
        var b = try d.fallback.surface(backdrop)
        try d.composite(s, onto: &b, x: 0, y: 0, mode: mode, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        #expect(fallback(d) == "maskedComposite \(RenderDispatcher.reasonUnsupported)")
        #expect(fake.calls.isEmpty)
        #expect(try d.read(b) == direct(source, onto: backdrop, mode: mode))
    }

    @Test func aFakeBackdropIsUploadedForTheMaskedComposite() throws {
        let fake = FakeBackend(supports: oldFamilies)
        let d = RenderDispatcher(preferred: fake, fallback: CPUBackend())
        let (source, backdrop) = (try seededBuffer(width: 4, height: 3, seed: 18), try seededBuffer(width: 6, height: 5, seed: 17))
        var b = try fake.surface(backdrop)
        let original = b
        try d.composite(d.fallback.surface(source), onto: &b,
                        x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        #expect(fake.calls.contains(.read(original)))
        // The backdrop moved to the CPU: the caller's handle is the CPU copy, the fake's released.
        #expect(b.backend == d.fallback.name)
        #expect(fake.calls.contains(.release(original)))
        #expect(try d.read(b) == direct(source, onto: backdrop, mode: .normal))
    }

    @Test func aMovedBackdropReplacesTheCallersHandle() throws {
        let inner = FakeBackend(supports: oldFamilies.union([.maskedComposite, .affine]))
        let d = RenderDispatcher(preferred: CompositingFake(inner: inner), fallback: CPUBackend())
        let backdrop = try seededBuffer(width: 6, height: 5, seed: 19)
        let s = try d.surface(seededBuffer(width: 4, height: 3, seed: 20))
        var b = try d.fallback.surface(backdrop)
        var original = b
        try d.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        #expect(b.backend == "fake")
        #expect(try d.read(b) == backdrop)
        #expect(throws: RenderError.surfaceMismatch) { try d.fallback.read(original) }
        b = try d.fallback.surface(backdrop)
        original = b
        try d.composite(s, onto: &b, through: shear, mode: .normal, opacity: 1, filter: .bilinear)
        #expect(b.backend == "fake")
        #expect(throws: RenderError.surfaceMismatch) { try d.fallback.read(original) }
        #expect(d.lastFallback == nil)
    }
}
