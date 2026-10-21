// W1ContractTests.swift: the W1 widening. The four CPU-first families and
// `RenderOp.notOnMetalYet`, the family of every tone case (the six original
// ones `.adjust`, the W1 colour ones `.color`), the "not on this backend"
// defaults (the null backend from RenderContractTests.swift, written before
// W1, throws `unsupported(<family>)` from each new method, `styled` included),
// and FakeBackend
// recording the W1 calls and gating them by `supports`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CoreColor
import CoreRaster
import CoreRender
import Testing

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
            .hsl(HSLAdjustment(reds: HSLShift(hue: 10))),
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

    @Test func fourteenFamilies() {
        #expect(RenderOp.allCases.count == 14)
        #expect(RenderOp.allCases.suffix(5) == [.maskedComposite, .affine, .effect, .color, .style])
    }

    @Test func notOnMetalYetIsExactlyTheFive() {
        #expect(RenderOp.notOnMetalYet == [.maskedComposite, .affine, .effect, .color, .style])
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
            (.style, { _ = try backend.styled(s, LayerStyleStack(entries: [])) }),
        ]
    }

    @Test func defaultsNameTheirFamily() throws {
        let backend = NullBackend()
        let surface = RenderSurface(id: UUID(), width: 1, height: 1, backend: backend.name)
        let calls = try Self.newCalls(backend, surface)
        #expect(calls.map(\.family) == [.maskedComposite, .affine, .affine, .affine, .effect, .style])
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

    @Test func fakeGatesTheNewCallsBySupports() throws {
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
