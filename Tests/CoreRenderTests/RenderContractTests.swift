// RenderContractTests.swift: the RenderBackend contract types. The op list
// and its raw values, RenderError equality, RenderSurface's init and hashing,
// ToneAdjustment equality, and a null backend conforming to the protocol from
// another module, so its signatures are proven usable as written.
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
/// nothing but the "not on this backend" defaults. W1ContractTests uses it too.
struct NullBackend: RenderBackend {
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
