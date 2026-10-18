// RenderContractTests.swift: the RenderBackend contract types. The op list
// and its raw values, RenderError equality, RenderSurface's init and hashing,
// ToneAdjustment equality, and a null backend conforming to the protocol from
// another module, so its signatures are proven usable as written.
// W1ContractTests: the W1 widening. The four CPU-first families and
// `RenderOp.notOnMetalYet`, the family of every tone case (the six original
// ones `.adjust`, the W1 colour ones `.color`), and the "not on this backend"
// defaults: the null backend, written before W1, throws `unsupported(<family>)`
// from each new method. The fake-call case waits on EC-3.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster
import CoreRender
import Testing

/// Supports nothing and throws `.unsupported` for every op: the smallest
/// conformance, compiled against the protocol from outside CoreRender. It
/// implements only the methods from before W1, so for the W1 methods it has
/// nothing but the "not on this backend" defaults.
private struct NullBackend: RenderBackend {
    let name = "null"
    let supports: Set<RenderOp> = []
    let isHealthy = true

    func surface(_ buffer: PixelBuffer) throws -> RenderSurface { throw RenderError.surfaceMismatch }
    func read(_ surface: RenderSurface) throws -> PixelBuffer { throw RenderError.surfaceMismatch }
    func release(_ surface: RenderSurface) {}
    func display(_ s: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] { throw RenderError.unsupported(.display) }
    func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float) throws {
        throw RenderError.unsupported(.composite)
    }
    func cropped(_ s: RenderSurface, x: Int, y: Int, width: Int, height: Int) throws -> RenderSurface {
        throw RenderError.unsupported(.transform)
    }
    func rotated(_ s: RenderSurface, _ turn: QuarterTurn) throws -> RenderSurface { throw RenderError.unsupported(.transform) }
    func resampled(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        throw RenderError.unsupported(.resample)
    }
    func gaussianBlur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface { throw RenderError.unsupported(.blur) }
    func unsharpMask(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double) throws -> RenderSurface {
        throw RenderError.unsupported(.blur)
    }
    func adjusted(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface { throw RenderError.unsupported(.adjust) }
    func cloned(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        throw RenderError.unsupported(.retouch)
    }
}

@Suite struct RenderContractTests {
    @Test func opsAreTheThirteenFamiliesNamedByTheirRawValues() {
        #expect(RenderOp.allCases.count == 13)
        #expect(RenderOp.allCases.map(\.rawValue) == [
            "display", "composite", "blendSeparable", "blendNonSeparable",
            "transform", "resample", "blur", "adjust", "retouch",
            "maskedComposite", "affine", "effect", "color",
        ])
        for op in RenderOp.allCases {
            #expect(op.rawValue == "\(op)")
            #expect(RenderOp(rawValue: op.rawValue) == op)
        }
    }

    @Test func errorsCompareByCaseAndPayload() {
        #expect(RenderError.unsupported(.blur) == .unsupported(.blur))
        #expect(RenderError.unsupported(.blur) != .unsupported(.display))
        #expect(RenderError.raster("a") != .raster("b"))
        #expect(RenderError.deviceLost("gone") == .deviceLost("gone"))
        #expect(RenderError.surfaceMismatch != .raster(""))
    }

    @Test func surfaceKeepsItsFieldsAndHashesByThem() {
        let id = UUID()
        let surface = RenderSurface(id: id, width: 640, height: 480, backend: "cpu")
        #expect(surface.id == id)
        #expect(surface.width == 640)
        #expect(surface.height == 480)
        #expect(surface.backend == "cpu")
        let twin = RenderSurface(id: id, width: 640, height: 480, backend: "cpu")
        #expect(surface == twin)
        #expect(Set([surface, twin]).count == 1)
        #expect(surface != RenderSurface(id: id, width: 640, height: 480, backend: "metal"))
        #expect(surface != RenderSurface(id: UUID(), width: 640, height: 480, backend: "cpu"))
    }

    @Test func adjustmentsCompareByCaseAndParameters() {
        #expect(ToneAdjustment.exposure(stops: 1) == .exposure(stops: 1))
        #expect(ToneAdjustment.exposure(stops: 1) != .exposure(stops: 2))
        #expect(ToneAdjustment.contrast(10) != .exposure(stops: 10))
        let points = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 0.5)]
        #expect(ToneAdjustment.curves(points: points) == .curves(points: points, encoding: .linear))
        #expect(ToneAdjustment.curves(points: points) != .curves(points: points, encoding: .sRGB))
        let levels = ToneAdjustment.levels(inBlack: 0, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1)
        #expect(levels == .levels(inBlack: 0, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1, encoding: .linear))
        #expect(levels != .levels(inBlack: 0, inWhite: 1, gamma: 2.2, outBlack: 0, outWhite: 1))
        #expect(ToneAdjustment.whiteBalance(temperature: 5, tint: -5) != .whiteBalance(temperature: -5, tint: 5))
        #expect(ToneAdjustment.highlightsShadows(highlights: 1, shadows: 2) != .highlightsShadows(highlights: 2, shadows: 1))
    }

    @Test func aBackendThatSupportsNothingThrowsUnsupported() {
        let backend = NullBackend()
        let surface = RenderSurface(id: UUID(), width: 1, height: 1, backend: backend.name)
        #expect(backend.supports.isEmpty)
        #expect(throws: RenderError.unsupported(.blur)) {
            try backend.gaussianBlur(surface, sigma: 1)
        }
        #expect(throws: RenderError.unsupported(.retouch)) {
            try backend.cloned(surface, offset: (dx: 1, dy: 0), through: try Mask(width: 1, height: 1))
        }
        var backdrop = surface
        #expect(throws: RenderError.unsupported(.composite)) {
            try backend.composite(surface, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1)
        }
        #expect(backdrop == surface, "a refused composite leaves the backdrop alone")
    }
}

@Suite struct W1ContractTests {
    /// The six tone cases from before W1, one per original CoreRaster adjustment.
    static let adjustCases: [ToneAdjustment] = [
        .exposure(stops: 1),
        .levels(inBlack: 0, inWhite: 1, gamma: 1, outBlack: 0, outWhite: 1),
        .curves(points: [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]),
        .whiteBalance(temperature: 10, tint: -10),
        .contrast(20),
        .highlightsShadows(highlights: 10, shadows: -10),
    ]

    /// One value of each W1 colour case.
    static func colorCases() throws -> [ToneAdjustment] {
        let white = RGBA(r: 1, g: 1, b: 1, a: 1)
        let lut = try ColorLUT(size: 2, table: (0..<8).map { SIMD3<Float>(repeating: Float($0) / 7) })
        return [
            .vibrance(25),
            .hueSaturation(hue: 10, saturation: -20, lightness: 5),
            .hsl(HSLAdjustment(reds: HSLRange(hue: 10))),
            .blackAndWhite(GrayMix(reds: 40, yellows: 60, greens: 40, cyans: 60, blues: 20, magentas: 80)),
            .channelMixer(ChannelMatrix(red: [1, 0, 0, 0], green: [0, 1, 0, 0], blue: [0, 0, 1, 0], monochrome: false)),
            .colorBalance(ToneBalance(shadows: [0.1, 0, 0], midtones: .zero, highlights: [0, 0, 0.1],
                                      preserveLuminosity: true)),
            .gradientMap([GradientMapStop(offset: 0, color: RGBA(r: 0, g: 0, b: 0, a: 1)),
                          GradientMapStop(offset: 1, color: white)]),
            .lut(lut),
            .posterize(levels: 4),
            .threshold(0.5),
            .invert,
        ]
    }

    @Test func thirteenFamilies() {
        #expect(RenderOp.allCases.count == 13)
        #expect(RenderOp.allCases.suffix(4) == [.maskedComposite, .affine, .effect, .color])
    }

    @Test func notOnMetalYetIsExactlyTheFour() {
        #expect(RenderOp.notOnMetalYet == [.maskedComposite, .affine, .effect, .color])
        #expect(RenderOp.notOnMetalYet.isSubset(of: Set(RenderOp.allCases)))
        #expect(RenderOp.notOnMetalYet.isDisjoint(with: Set(RenderOp.allCases.prefix(9))),
                "every family from before W1 may run on Metal")
    }

    @Test func adjustCasesAreAdjust() {
        for adjustment in Self.adjustCases { #expect(adjustment.family == .adjust, "\(adjustment)") }
    }

    @Test func colorCasesAreColor() throws {
        let cases = try Self.colorCases()
        #expect(cases.count == 11)
        for adjustment in cases { #expect(adjustment.family == .color, "\(adjustment)") }
        #expect(ToneAdjustment.invert == .invert)
        #expect(ToneAdjustment.posterize(levels: 4) != .posterize(levels: 5))
        #expect(ToneAdjustment.threshold(0.5) != .vibrance(0.5))
    }

    /// Each new method, called on `backend` with `s` (and a copy of it as the
    /// backdrop), paired with the family its default names.
    static func newCalls(_ backend: any RenderBackend, _ s: RenderSurface)
        throws -> [(family: RenderOp, call: () throws -> Void)] {
        let mask = try Mask(width: 1, height: 1)
        let quarter = AffineMatrix(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        return [
            (.maskedComposite, {
                var b = s
                try backend.composite(s, onto: &b, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
            }),
            (.affine, { _ = try backend.transformed(s, quarter, width: 1, height: 1, filter: .bilinear) }),
            (.affine, { _ = try backend.flipped(s, .horizontal) }),
            (.affine, {
                var b = s
                try backend.composite(s, onto: &b, through: quarter, mode: .multiply, opacity: 0.5, filter: .bilinear)
            }),
            (.effect, { _ = try backend.applying(s, .boxBlur(radius: 2)) }),
        ]
    }

    @Test func defaultsNameTheirFamily() throws {
        let backend = NullBackend()
        let surface = RenderSurface(id: UUID(), width: 1, height: 1, backend: backend.name)
        let calls = try Self.newCalls(backend, surface)
        #expect(calls.map(\.family) == [.maskedComposite, .affine, .affine, .affine, .effect])
        for (family, call) in calls {
            #expect(throws: RenderError.unsupported(family)) { try call() }
        }
    }

    @Test func refusedCompositesLeaveTheBackdropAlone() throws {
        let backend = NullBackend()
        let surface = RenderSurface(id: UUID(), width: 1, height: 1, backend: backend.name)
        var backdrop = surface
        #expect(throws: RenderError.unsupported(.maskedComposite)) {
            try backend.composite(surface, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1,
                                  mask: try Mask(width: 1, height: 1), maskX: 0, maskY: 0)
        }
        #expect(throws: RenderError.unsupported(.affine)) {
            try backend.composite(surface, onto: &backdrop, through: .identity, mode: .normal, opacity: 1, filter: .lanczos3)
        }
        #expect(backdrop == surface)
    }

    @Test(.disabled("waits on EC-3: FakeBackend records the W1 calls and honours supports for them"))
    func fakeGatesTheNewCallsBySupports() throws {
        let buffer = try PixelBuffer(width: 2, height: 2)
        let none = FakeBackend(supports: [])
        let refused = try Self.newCalls(none, try none.surface(buffer))
        for (family, call) in refused { #expect(throws: RenderError.unsupported(family)) { try call() } }
        let all = FakeBackend(supports: Set(RenderOp.allCases))
        let accepted = try Self.newCalls(all, try all.surface(buffer))
        for (family, call) in accepted { #expect(throws: Never.self, "\(family)") { try call() } }
        #expect(all.calls.count >= 1 + accepted.count, "each new call is recorded")
    }
}
