// WhiteBalanceLoopAdversarialTests.swift: the one-pass adjustment loop (issue
// #248, PR #253) against the per-pixel `pixel` / `setPixel` path it replaced,
// on boundary shapes and extreme values: single rows and columns, huge,
// subnormal and negative components, near-zero alpha, and the first
// non-finite pixel's coordinates in the error.
import CoreRaster
import Testing

/// White balance the way it was computed before the one-pass loop: each pixel
/// through `pixel(x:y:)`, its own gains, and `setPixel`.
private func referenceWhiteBalance(_ buffer: PixelBuffer, temperature: Float, tint: Float) throws -> PixelBuffer {
    var result = buffer
    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            let one = try PixelBuffer(width: 1, height: 1, fill: buffer.pixel(x: x, y: y))
            try result.setPixel(x: x, y: y, one.whiteBalance(temperature: temperature, tint: tint).pixel(x: 0, y: 0))
        }
    }
    return result
}

private func extremePixel(_ rng: inout SplitMix64) -> RGBA {
    let values: [Float] = [0, -0.0, 1, -1, .leastNonzeroMagnitude, .leastNormalMagnitude,
                           1e-30, 1e30, -1e30, .greatestFiniteMagnitude / 4, 0.5, 2]
    let alphas: [Float] = [0, 1, 0.5, .leastNonzeroMagnitude, .leastNormalMagnitude, 1e-20]
    func pick(_ list: [Float]) -> Float { list[Int(rng.next() % UInt64(list.count))] }
    return RGBA(r: pick(values), g: pick(values), b: pick(values), a: pick(alphas))
}

@Test(arguments: [(1, 9), (9, 1), (3, 4), (17, 2)])
func whiteBalanceMatchesThePerPixelPathOnEveryShape(width: Int, height: Int) throws {
    var rng = SplitMix64(seed: 253)
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    for (t, n) in [(Float(100), Float(-100)), (-100, 100), (0.5, 0), (0, -0.25)] {
        #expect(try buffer.whiteBalance(temperature: t, tint: n) == referenceWhiteBalance(buffer, temperature: t, tint: n))
    }
}

/// Extreme stored values: the loop either matches the per-pixel path bit for
/// bit or throws exactly when that path throws.
@Test func whiteBalanceOnExtremeValuesMatchesThePerPixelPathOrThrowsLikeIt() throws {
    var rng = SplitMix64(seed: 2530)
    for _ in 0..<300 {
        var buffer = try PixelBuffer(width: 3, height: 2)
        for y in 0..<2 {
            for x in 0..<3 {
                try buffer.setPixel(x: x, y: y, extremePixel(&rng))
            }
        }
        let t = Float.random(in: -100...100, using: &rng), n = Float.random(in: -100...100, using: &rng)
        let reference = Result { try referenceWhiteBalance(buffer, temperature: t, tint: n) }
        let fast = Result { try buffer.whiteBalance(temperature: t, tint: n) }
        switch (reference, fast) {
        case let (.success(a), .success(b)): #expect(a == b)
        case (.failure, .failure): break
        default: Issue.record("per-pixel \(reference) but one-pass \(fast) for \(buffer) at \(t), \(n)")
        }
    }
}

/// An overflow in a later row is reported at that pixel's own coordinates.
@Test func whiteBalanceOverflowNamesTheFirstFailingPixel() throws {
    var buffer = try PixelBuffer(width: 4, height: 3, fill: RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
    let huge = RGBA(r: .greatestFiniteMagnitude, g: 0, b: 0, a: 1)
    try buffer.setPixel(x: 3, y: 2, huge)
    try buffer.setPixel(x: 1, y: 2, huge)
    #expect {
        try buffer.whiteBalance(temperature: 100, tint: 0)
    } throws: { error in
        guard case let .invalid(message) = error as? RasterError else { return false }
        return message.contains("at (1, 2)")
    }
}
