// AffineStubTests.swift: the affine-composite contract stubs (AC-0) as they
// stand before their bodies land: `composite(_:through:...)` throws
// "not built" and `AffineMatrix.bounds` is nil. AC-5 replaces this suite with
// the real checks (AC-3's are in AffineOpsTests, AC-4's in CanvasSizeTests).
import CoreRaster
import Testing

@Suite struct AffineStubTests {
    private static let notBuilt = RasterError.invalid("not built")

    private func layer() throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: 3, height: 2)
        try buffer.setPixel(x: 0, y: 0, RGBA(r: 0.5, g: 0.25, b: 0, a: 1))
        return buffer
    }

    @Test func compositeThroughThrowsNotBuiltAndLeavesBackdrop() throws {
        let source = try layer()
        let before = try PixelBuffer(width: 4, height: 4, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
        var backdrop = before
        #expect(throws: Self.notBuilt) {
            try backdrop.composite(source, through: .identity, mode: .normal, opacity: 1, filter: .bilinear)
        }
        #expect(backdrop == before)
    }

    @Test func boundsIsNil() {
        #expect(AffineMatrix.identity.bounds(of: 3, 2) == nil)
    }
}
