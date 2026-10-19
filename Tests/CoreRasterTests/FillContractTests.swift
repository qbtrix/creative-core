// FillContractTests.swift: the fill-tools contract (FT-0). Every declared
// entry point throws `RasterError` for input its documented ranges reject,
// so these cases hold for the stubs and keep holding once FT-3 to FT-6 fill
// in the bodies. The value types are Hashable and Sendable, and a stop keeps
// its fields.
import CoreRaster
import Testing

@Suite struct FillContractTests {
    private func buffer() throws -> PixelBuffer {
        try PixelBuffer(width: 4, height: 3, fill: RGBA(r: 0.5, g: 0.25, b: 0.125, a: 1))
    }

    @Test func floodMaskThrowsRasterErrorForSeedOutside() throws {
        let image = try buffer()
        #expect(throws: RasterError.self) {
            try image.floodMask(from: (x: 4, y: 0), tolerance: .exact)
        }
        #expect(throws: RasterError.self) {
            try image.floodMask(from: (x: -1, y: 1), tolerance: .within(0.1), contiguous: false,
                                connectivity: .eight, antiAlias: false)
        }
    }

    @Test func sampledColorThrowsRasterErrorForRadiusThree() throws {
        let image = try buffer()
        #expect(throws: RasterError.self) {
            try image.sampledColor(at: (x: 1, y: 1), radius: 3)
        }
    }

    @Test func colorRangeMaskThrowsRasterErrorForFuzzinessOutside() throws {
        let image = try buffer()
        #expect(throws: RasterError.self) {
            try image.colorRangeMask(around: RGBA(r: 0.5, g: 0.25, b: 0.125, a: 1), fuzziness: 2)
        }
    }

    @Test func gradientThrowsRasterErrorForOneStop() {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        #expect(throws: RasterError.self) {
            try PixelBuffer.gradient(width: 8, height: 8, shape: .linear, from: Mask.Point(x: 0, y: 0),
                                     to: Mask.Point(x: 8, y: 0), stops: [RasterGradientStop(offset: 0, color: red)])
        }
        #expect(throws: RasterError.self) {
            try PixelBuffer.gradient(width: 8, height: 8, shape: .radial, from: Mask.Point(x: 0, y: 0),
                                     to: Mask.Point(x: 8, y: 0), stops: [], space: .linear, dither: false)
        }
    }

    @Test func connectivityAndSpaceAreHashableAndSendable() {
        func sendable<T: Sendable>(_ value: T) -> T { value }
        #expect(Set([Connectivity.four, .eight, .four].map(sendable)).count == 2)
        #expect(Set([GradientSpace.linear, .perceptual, .linear].map(sendable)).count == 2)
        #expect(Connectivity.four != Connectivity.eight)
        #expect(GradientSpace.linear != GradientSpace.perceptual)
    }

    @Test func stopRoundTripsItsFields() {
        let color = RGBA(r: 0.2, g: 0.4, b: 0.6, a: 0.8)
        var stop = RasterGradientStop(offset: 0.25, color: color)
        #expect(stop.offset == 0.25)
        #expect(stop.color == color)
        let copy = stop
        stop.offset = 0.75
        stop.color = .clear
        #expect(stop.offset == 0.75)
        #expect(stop.color == .clear)
        #expect(copy == RasterGradientStop(offset: 0.25, color: color))
        #expect(copy != stop)
        #expect(Set([copy, stop, copy]).count == 2)
    }
}
