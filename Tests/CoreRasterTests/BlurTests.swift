// BlurTests.swift: Gaussian blur and unsharp mask on PixelBuffer. Constant
// images stay constant, an impulse spreads symmetrically and keeps its sum,
// sigma 0 and amount 0 are exact no-ops, and invalid parameters throw.
import CoreRaster
import Testing

private func randomBuffer(width: Int, height: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) }
    }
    return buffer
}

@Test func blurLeavesAConstantImageConstant() throws {
    var rng = SplitMix64(seed: 117)
    for _ in 0..<30 {
        let fill = randomPixel(&rng)
        let w = Int.random(in: 1...12, using: &rng)
        let h = Int.random(in: 1...12, using: &rng)
        let image = try PixelBuffer(width: w, height: h, fill: fill)
        // Up to the largest sigma allowed: radius ceil(3 sigma) <= 2 * larger side.
        let out = try image.gaussianBlur(sigma: .random(in: 0.1...Double(2 * max(w, h)) / 3, using: &rng))
        for y in 0..<h {
            for x in 0..<w {
                let p = try out.pixel(x: x, y: y)
                #expect(abs(p.r - fill.r) <= 1e-6 && abs(p.g - fill.g) <= 1e-6)
                #expect(abs(p.b - fill.b) <= 1e-6 && abs(p.a - fill.a) <= 1e-6)
            }
        }
    }
}

@Test func blurSpreadsAnImpulseSymmetricallyAndKeepsItsSum() throws {
    // sigma 1.5 gives radius 5; the 15x15 image keeps the kernel off the edges.
    var image = try PixelBuffer(width: 15, height: 15)
    try image.setPixel(x: 7, y: 7, RGBA(r: 1, g: 2, b: 3, a: 1))
    let out = try image.gaussianBlur(sigma: 1.5)
    var sum: Double = 0
    for y in 0..<15 {
        for x in 0..<15 {
            let p = try out.pixel(x: x, y: y).r
            sum += Double(p)
            // Mirrored pixels sum the same products in reverse order.
            let mirrors = try [out.pixel(x: 14 - x, y: y), out.pixel(x: x, y: 14 - y), out.pixel(x: y, y: x)]
            #expect(mirrors.allSatisfy { abs($0.r - p) <= 1e-7 })
        }
    }
    #expect(abs(sum - 1) <= 1e-5)
    let center = try out.pixel(x: 7, y: 7)
    let row = try (0..<15).map { try out.pixel(x: $0, y: 7).r }
    #expect(center.r > row[8] && row[8] > row[9])
    #expect(center.r < 0.1 && abs(center.g - 2 * center.r) <= 1e-6)
    // Radius 5: the response reaches column 2 and stops before column 1.
    #expect(row[2] > 0 && row[1] == 0)
}

@Test func sigmaZeroAndAmountZeroReturnTheInputExactly() throws {
    var rng = SplitMix64(seed: 1170)
    for _ in 0..<20 {
        let image = try randomBuffer(width: .random(in: 1...9, using: &rng),
                                     height: .random(in: 1...9, using: &rng), &rng)
        #expect(try image.gaussianBlur(sigma: 0) == image)
        #expect(try image.unsharpMask(amount: 0, sigma: 1.2, threshold: 0) == image)
        #expect(try image.unsharpMask(amount: 2, sigma: 0, threshold: 0) == image)
    }
}

@Test func unsharpMaskSteepensAnEdgeAboveTheThreshold() throws {
    var step = try PixelBuffer(width: 8, height: 1)
    for x in 4..<8 { try step.setPixel(x: x, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1)) }
    let blurred = try step.gaussianBlur(sigma: 1)
    let sharp = try step.unsharpMask(amount: 1, sigma: 1, threshold: 0)
    let b3 = try blurred.pixel(x: 3, y: 0).r
    let s3 = try sharp.pixel(x: 3, y: 0).r
    // 0 + 1 * (0 - b3): the dark side of the edge dips below 0, the light side rises over 1.
    #expect(b3 > 0 && abs(s3 + b3) <= 1e-6)
    #expect(try sharp.pixel(x: 4, y: 0).r > 1)
    #expect(try step.unsharpMask(amount: 1, sigma: 1, threshold: 0.9) == step)
}

@Test func invalidBlurAndSharpenParametersThrow() throws {
    let image = try PixelBuffer(width: 4, height: 3)
    for sigma in [-1, -0.001, .nan, .infinity, -.infinity, 2.7, 1e300] {
        #expect(throws: RasterError.self) { try image.gaussianBlur(sigma: sigma) }
        #expect(throws: RasterError.self) { try image.unsharpMask(amount: 1, sigma: sigma, threshold: 0) }
    }
    #expect(try image.gaussianBlur(sigma: 2.6).width == 4)
    for amount in [Double.nan, .infinity] {
        #expect(throws: RasterError.self) { try image.unsharpMask(amount: amount, sigma: 1, threshold: 0) }
    }
    for threshold in [-1, Double.nan, .infinity] {
        #expect(throws: RasterError.self) { try image.unsharpMask(amount: 1, sigma: 1, threshold: threshold) }
    }
    let big = Float.greatestFiniteMagnitude
    var edge = try PixelBuffer(width: 4, height: 1, fill: RGBA(r: big, g: 0, b: 0, a: 1))
    try edge.setPixel(x: 0, y: 0, RGBA(r: -big, g: 0, b: 0, a: 1))
    #expect(throws: RasterError.self) { try edge.unsharpMask(amount: 10, sigma: 1, threshold: 0) }
}
