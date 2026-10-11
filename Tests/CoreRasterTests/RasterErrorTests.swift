// RasterErrorTests.swift: CoreRaster's test target. Buffer and compositing
// tests land here.
import CoreRaster
import Testing

@Test func rasterErrorsCompareByMessage() {
    #expect(RasterError.invalid("a") == RasterError.invalid("a"))
    #expect(RasterError.invalid("a") != RasterError.invalid("b"))
}
