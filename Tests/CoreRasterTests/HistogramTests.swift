// HistogramTests.swift: Histogram on PixelBuffer. Known counts on hand-made
// fixtures (black, white, two-tone, gradient), bin edges, clamping and
// clipping counts, unpremultiplied values, transparent pixels, Rec. 709
// luminance weights, bins summing to the opaque pixel count on seeded random
// buffers, and every invalid bin count throws.
import CoreRaster
import Testing

/// An opaque 1-row buffer holding `values` as gray pixels.
private func grayRow(_ values: [Float]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: values.count, height: 1)
    for (x, v) in values.enumerated() {
        try buffer.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    return buffer
}

/// `count` zeros with `value` added at each of `at`.
private func counts(_ count: Int, _ at: [Int: Int]) -> [Int] {
    (0..<count).map { at[$0, default: 0] }
}

@Test func allBlackFillsTheFirstBinAndClipsShadows() throws {
    let h = try Histogram(of: PixelBuffer(width: 3, height: 2, fill: RGBA(r: 0, g: 0, b: 0, a: 1)))
    let expected = counts(256, [0: 6])
    #expect(h.bins == 256)
    #expect(h.red == expected && h.green == expected && h.blue == expected && h.luminance == expected)
    #expect(h.shadowClipped == 6)
    #expect(h.highlightClipped == 0)
    #expect(h.transparent == 0)
}

@Test func allWhiteFillsTheLastBinAndClipsHighlights() throws {
    let h = try Histogram(of: PixelBuffer(width: 2, height: 2, fill: RGBA(r: 1, g: 1, b: 1, a: 1)), bins: 16)
    let expected = counts(16, [15: 4])
    #expect(h.red == expected && h.green == expected && h.blue == expected && h.luminance == expected)
    #expect(h.shadowClipped == 0)
    #expect(h.highlightClipped == 4)
}

@Test func twoToneSplitsBetweenTwoBins() throws {
    let h = try Histogram(of: grayRow([0.15, 0.15, 0.15, 0.65, 0.65]), bins: 10)
    let expected = counts(10, [1: 3, 6: 2])
    #expect(h.red == expected && h.luminance == expected)
    #expect(h.shadowClipped == 0 && h.highlightClipped == 0)
}

@Test func gradientSpreadsEvenlyAcrossBins() throws {
    let h = try Histogram(of: grayRow((0...7).map { Float($0) / 7 }), bins: 4)
    #expect(h.red == [2, 2, 2, 2])
    #expect(h.shadowClipped == 1)
    #expect(h.highlightClipped == 1)
}

@Test func binEdgesBelongToTheUpperBinAndOneToTheLast() throws {
    let h = try Histogram(of: grayRow([0, 0.2499, 0.25, 0.5, 0.75, 0.9999, 1]), bins: 4)
    #expect(h.green == [2, 1, 1, 3])
}

@Test func outOfRangeValuesClampAndCountAsClipped() throws {
    var buffer = try grayRow([-0.5, 1.5, 0.5])
    try buffer.setPixel(x: 2, y: 0, RGBA(r: 0, g: 1, b: 0.5, a: 1))
    let h = try Histogram(of: buffer, bins: 2)
    #expect(h.red == [2, 1])
    #expect(h.green == [1, 2])
    #expect(h.blue == [1, 2])
    #expect(h.shadowClipped == 2)
    #expect(h.highlightClipped == 2)
}

@Test func countsUnpremultipliedValues() throws {
    let straight = RGBA(r: 0.65, g: 0.65, b: 0.65, a: 0.5)
    let h = try Histogram(of: PixelBuffer(width: 1, height: 1, fill: straight.premultiplied()), bins: 10)
    #expect(h.red == counts(10, [6: 1]))
}

@Test func fullyTransparentPixelsAreSkippedAndCounted() throws {
    var buffer = try PixelBuffer(width: 3, height: 1)
    try buffer.setPixel(x: 1, y: 0, RGBA(r: 0.3, g: 0.3, b: 0.3, a: 1))
    let h = try Histogram(of: buffer, bins: 10)
    #expect(h.transparent == 2)
    #expect(h.red == counts(10, [3: 1]))
    #expect(h.luminance.reduce(0, +) == 1)
    #expect(h.shadowClipped == 0)
}

@Test func luminanceUsesRec709Weights() throws {
    #expect(Histogram.luminanceWeights == (r: 0.2126, g: 0.7152, b: 0.0722))
    var buffer = try PixelBuffer(width: 3, height: 1)
    try buffer.setPixel(x: 0, y: 0, RGBA(r: 1, g: 0, b: 0, a: 1))
    try buffer.setPixel(x: 1, y: 0, RGBA(r: 0, g: 1, b: 0, a: 1))
    try buffer.setPixel(x: 2, y: 0, RGBA(r: 0, g: 0, b: 1, a: 1))
    let h = try Histogram(of: buffer, bins: 4096)
    // 0.2126, 0.7152 and 0.0722 times 4096, rounded down.
    #expect(h.luminance == counts(4096, [870: 1, 2929: 1, 295: 1]))
}

@Test func everyChannelSumsToTheNonTransparentPixelCount() throws {
    var rng = SplitMix64(seed: 118)
    for _ in 0..<20 {
        var buffer = try PixelBuffer(width: 5, height: 4)
        for y in 0..<4 {
            for x in 0..<5 where Bool.random(using: &rng) {
                try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
            }
        }
        let bins = Int.random(in: Histogram.binRange, using: &rng)
        let h = try Histogram(of: buffer, bins: bins)
        let visible = 20 - h.transparent
        for channel in [h.red, h.green, h.blue, h.luminance] {
            #expect(channel.count == bins)
            #expect(channel.reduce(0, +) == visible)
        }
    }
}

@Test func invalidBinCountsThrow() throws {
    let buffer = try PixelBuffer(width: 1, height: 1)
    for bins in [Int.min, -1, 0, 1, 4097, Int.max] {
        #expect(throws: RasterError.self) { try Histogram(of: buffer, bins: bins) }
    }
    #expect(try Histogram(of: buffer, bins: 2).bins == 2)
    #expect(try Histogram(of: buffer, bins: 4096).bins == 4096)
}
