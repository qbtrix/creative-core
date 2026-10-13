// WhiteBalanceSpeedTests.swift: white balance on a 24-megapixel buffer
// (issue #248). Report-only: it prints the time against the 1 s target and
// checks the output, but does not fail on time until a budget row exists.
import CoreRaster
import Testing

@Test func whiteBalanceOn24MegapixelsReportsItsTime() throws {
    let width = 6000, height = 4000
    let buffer = try PixelBuffer(width: width, height: height, fill: RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1))
    let clock = ContinuousClock()
    var result = buffer
    let elapsed = try clock.measure { result = try buffer.whiteBalance(temperature: 30, tint: 10) }
    print("whiteBalance on \(width)x\(height): \(elapsed) (target 1 s in release)")
    let small = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1))
        .whiteBalance(temperature: 30, tint: 10).pixel(x: 0, y: 0)
    for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3)] {
        #expect(try result.pixel(x: x, y: y) == small)
    }
}

/// The one-pass loop maps every pixel of a multi-row buffer, each at its own
/// place: the same as white balance on that pixel alone.
@Test func whiteBalanceMapsEveryPixelInPlace() throws {
    var rng = SplitMix64(seed: 248)
    var buffer = try PixelBuffer(width: 7, height: 5)
    for y in 0..<5 {
        for x in 0..<7 {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    let result = try buffer.whiteBalance(temperature: -40, tint: 25)
    for y in 0..<5 {
        for x in 0..<7 {
            let alone = try PixelBuffer(width: 1, height: 1, fill: buffer.pixel(x: x, y: y))
            #expect(try result.pixel(x: x, y: y) == alone.whiteBalance(temperature: -40, tint: 25).pixel(x: 0, y: 0))
        }
    }
}
