// RB-2: the contract types and the recording fake. A fake must run only the
// ops it lists and refuse the rest with `.unsupported`, or the dispatcher's
// routing tests (RB-5) would prove nothing.
import CoreRaster
import CoreRender
import Testing

@Test func fakeRunsASupportedOpAndRecordsIt() throws {
    let fake = FakeBackend(supports: [.composite])
    var backdrop = try fake.surface(try PixelBuffer(width: 4, height: 3))
    let source = try fake.surface(try PixelBuffer(width: 2, height: 2))
    try fake.composite(source, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1)
    #expect(fake.log.calls == [.composite])
}

@Test func fakeRefusesAnUnsupportedOpAndStillRecordsTheAttempt() throws {
    let fake = FakeBackend(supports: [.composite])
    let surface = try fake.surface(try PixelBuffer(width: 4, height: 4))
    #expect(throws: RenderError.unsupported(.blur)) {
        try fake.gaussianBlur(surface, sigma: 2)
    }
    #expect(fake.log.calls == [.blur])
}

@Test func fakeSurfaceCarriesItsSizeAndBackendName() throws {
    let fake = FakeBackend(name: "fake-gpu", supports: [])
    let surface = try fake.surface(try PixelBuffer(width: 5, height: 7))
    #expect(surface.width == 5)
    #expect(surface.height == 7)
    #expect(surface.backend == "fake-gpu")
}

@Test func fakeRotationSwapsWidthAndHeight() throws {
    let fake = FakeBackend(supports: [.transform])
    let surface = try fake.surface(try PixelBuffer(width: 6, height: 2))
    let turned = try fake.rotated(surface, .degrees90)
    #expect(turned.width == 2)
    #expect(turned.height == 6)
}

@Test func unhealthyFakeReportsItself() {
    let fake = FakeBackend(supports: [], healthy: false)
    #expect(fake.isHealthy == false)
}

@Test func renderOpHasNineFamilies() {
    #expect(RenderOp.allCases.count == 9)
}

@Test func renderErrorCasesCompareByValue() {
    #expect(RenderError.unsupported(.blur) == .unsupported(.blur))
    #expect(RenderError.unsupported(.blur) != .unsupported(.adjust))
    #expect(RenderError.raster("bad") != .surfaceMismatch)
}
