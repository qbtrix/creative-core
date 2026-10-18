// CPUBackendW1StubTests.swift: engine-contracts EC-z. The CPU backend's W1
// stubs (masked composite, transformed, flipped, composite through a matrix,
// applying) and a `.color` adjustment check their surfaces before anything
// else: a released `s` throws `surfaceMismatch`, not `unsupported`, and each
// composite throws `surfaceMismatch` for a backdrop another backend made even
// when `s` is live. Features that fill the stubs inherit this ordering.
import CoreRaster
import CoreRender
import Testing

@Suite struct CPUBackendW1StubTests {
    @Test func stubsCheckSurfacesFirst() throws {
        let cpu = CPUBackend()
        let mask = try Mask(width: 2, height: 2)
        let released = try cpu.surface(try PixelBuffer(width: 2, height: 2))
        cpu.release(released)
        var backdrop = try cpu.surface(try PixelBuffer(width: 2, height: 2))
        let calls: [(name: String, call: () throws -> Void)] = [
            ("masked composite", { try cpu.composite(released, onto: &backdrop, x: 0, y: 0, mode: .normal, opacity: 1,
                                                      mask: mask, maskX: 0, maskY: 0) }),
            ("transformed", { _ = try cpu.transformed(released, .identity, width: 2, height: 2, filter: .bilinear) }),
            ("flipped", { _ = try cpu.flipped(released, .horizontal) }),
            ("composite through", { try cpu.composite(released, onto: &backdrop, through: .identity, mode: .normal,
                                                       opacity: 1, filter: .bilinear) }),
            ("applying", { _ = try cpu.applying(released, .boxBlur(radius: 1)) }),
            ("color adjustment", { _ = try cpu.adjusted(released, .invert) }),
        ]
        for (name, call) in calls {
            #expect(throws: RenderError.surfaceMismatch, "\(name) with a released source") { try call() }
        }

        let live = try cpu.surface(try PixelBuffer(width: 2, height: 2))
        let fake = FakeBackend(supports: Set(RenderOp.allCases))
        var foreign = try fake.surface(try PixelBuffer(width: 2, height: 2))
        let before = foreign
        #expect(throws: RenderError.surfaceMismatch, "masked composite onto a foreign backdrop") {
            try cpu.composite(live, onto: &foreign, x: 0, y: 0, mode: .normal, opacity: 1, mask: mask, maskX: 0, maskY: 0)
        }
        #expect(throws: RenderError.surfaceMismatch, "composite through onto a foreign backdrop") {
            try cpu.composite(live, onto: &foreign, through: .identity, mode: .normal, opacity: 1, filter: .bilinear)
        }
        #expect(foreign == before)
    }
}
