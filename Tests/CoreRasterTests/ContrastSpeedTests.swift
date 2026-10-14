// ContrastSpeedTests.swift: contrast on a 24-megapixel buffer (issue #255).
// It prints the time in every build. A release build, where the 1 s target
// applies, takes the best of three runs (the first 24 MP call in a process
// pays for fresh memory) and fails over 1 s. The output matches contrast on
// one pixel.
import CoreRaster
import Testing

@Test func contrastOn24MegapixelsMeetsItsTarget() throws {
    let width = 6000, height = 4000
    let fill = RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1)
    let buffer = try PixelBuffer(width: width, height: height, fill: fill)
    #if DEBUG
    let runs = 1
    #else
    let runs = 3
    #endif
    let clock = ContinuousClock()
    var result = buffer
    var best = Duration.seconds(Int64.max)
    for _ in 0..<runs {
        best = min(best, try clock.measure { result = try buffer.contrast(40) })
    }
    print("contrast on \(width)x\(height): \(best) (target 1 s in release)")
    #if !DEBUG
    #expect(best < .seconds(1))
    #endif
    let small = try PixelBuffer(width: 1, height: 1, fill: fill).contrast(40).pixel(x: 0, y: 0)
    for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3)] {
        #expect(try result.pixel(x: x, y: y) == small)
    }
}
