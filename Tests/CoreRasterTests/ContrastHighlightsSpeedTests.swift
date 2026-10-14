// ContrastHighlightsSpeedTests.swift: contrast and highlights/shadows on a
// 24-megapixel buffer (issues #255, #260). In an optimized build each call
// must finish under the 1 s target; debug builds skip the timing (contrast
// alone takes about 9 s there). Highlights/shadows output is pinned bit for
// bit, so a faster kernel can't change it unnoticed; contrast's bits are
// pinned by ContrastSpeedTests and `contrastInsideZeroToOneIsTheSCurve`.
import CoreRaster
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

private let target: Duration = .seconds(1)

/// A gray ramp across both smoothstep ranges and outside 0...1.
private let rampValues: [Float] = [-0.5, 0, 0.03, 0.09, 0.12, 0.18, 0.3, 0.59, 0.8, 1, 2.5]

private func grayRow(_ values: [Float]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: values.count, height: 1)
    for (x, v) in values.enumerated() {
        try buffer.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    return buffer
}

private func bits(_ buffer: PixelBuffer) throws -> [UInt32] {
    try (0..<buffer.width).map { try buffer.pixel(x: $0, y: 0).r.bitPattern }
}

@Test func highlightsShadowsGiveTheSameBitsAsBefore() throws {
    let row = try grayRow(rampValues)
    #expect(try bits(row.highlightsShadows(highlights: -50, shadows: 50)) == [
        0xBF3504F3, 0x0, 0x3D2D27BE, 0x3DFD0DCB, 0x3E2540B3, 0x3E6B4B70,
        0x3EAA13BA, 0x3EFE049A, 0x3F188383, 0x3F3504F3, 0x3FE24630,
    ])
    #expect(try bits(row.highlightsShadows(highlights: 100, shadows: -100)) == [
        0xBE800000, 0x0, 0x3C778853, 0x3D439421, 0x3D87E2F1, 0x3DE23749,
        0x3E7A8F6E, 0x3F559A51, 0x3FB8A59E, 0x40000000, 0x40A00000,
    ])
}

/// Times `adjust` on a 6000x4000 buffer against the target, best of two
/// runs as in the issue, and checks the corners and the middle against the
/// same adjustment on one pixel.
private func checkTarget(_ name: String, _ adjust: (PixelBuffer) throws -> PixelBuffer) throws {
    let width = 6000, height = 4000
    let fill = RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1)
    let buffer = try PixelBuffer(width: width, height: height, fill: fill)
    var result = buffer
    let clock = ContinuousClock()
    let elapsed = try min(clock.measure { result = try adjust(buffer) },
                          clock.measure { result = try adjust(buffer) })
    print("\(name) on \(width)x\(height): \(elapsed) (target \(target))")
    #expect(elapsed < target, "\(name) took \(elapsed)")
    let small = try adjust(PixelBuffer(width: 1, height: 1, fill: fill)).pixel(x: 0, y: 0)
    for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3)] {
        #expect(try result.pixel(x: x, y: y) == small)
    }
}

/// Serialized, so the two 24 MP runs don't share memory bandwidth.
@Suite(.serialized, .enabled(if: optimized, "24 MP timing needs an optimized build"))
struct ContrastHighlightsTargetTests {
    @Test func contrastOn24MegapixelsMeetsTheTarget() throws {
        try checkTarget("contrast(40)") { try $0.contrast(40) }
    }

    @Test func highlightsShadowsOn24MegapixelsMeetTheTarget() throws {
        try checkTarget("highlightsShadows(-50, 50)") { try $0.highlightsShadows(highlights: -50, shadows: 50) }
    }
}
