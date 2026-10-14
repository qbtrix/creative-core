// ContrastSpeedTests.swift: contrast on a 24-megapixel buffer (issue #255).
// Report-only on time: it prints the time against the 1 s target and checks
// the output, but does not fail on time until a budget row exists. The
// tabulated segment form of the curve must give the same values, bit for bit,
// as the Hermite basis form it replaced.
import CoreRaster
import Testing

@Test func contrastOn24MegapixelsReportsItsTime() throws {
    let width = 6000, height = 4000
    let buffer = try PixelBuffer(width: width, height: height, fill: RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1))
    let clock = ContinuousClock()
    var result = buffer
    let elapsed = try clock.measure { result = try buffer.contrast(40) }
    print("contrast on \(width)x\(height): \(elapsed) (target 1 s in release)")
    let small = try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1))
        .contrast(40).pixel(x: 0, y: 0)
    #expect(small != RGBA(r: 0.3, g: 0.4, b: 0.5, a: 1))
    for (x, y) in [(0, 0), (width - 1, height - 1), (width / 2, height / 3)] {
        #expect(try result.pixel(x: x, y: y) == small)
    }
}

/// Values the Hermite basis evaluation gave before the curve was tabulated
/// into per-segment coefficients, one input in each of the curve's segments.
@Test func contrastKeepsTheValuesOfTheHermiteBasisForm() throws {
    let inputs: [Float] = [0.05, 0.13, 0.3, 0.75]
    var row = try PixelBuffer(width: inputs.count, height: 1)
    for (x, v) in inputs.enumerated() {
        try row.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    let expected: [Float: [Float]] = [
        40: [0.037530866, 0.11753086, 0.3289685, 0.8118977],
        -70: [0.07182099, 0.15182099, 0.24930517, 0.64167905],
    ]
    for (amount, values) in expected {
        let mapped = try row.contrast(amount)
        #expect(try (0..<inputs.count).map { try mapped.pixel(x: $0, y: 0).r } == values, "contrast \(amount)")
    }
}

