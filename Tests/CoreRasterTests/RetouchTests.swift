// RetouchTests.swift: PixelBuffer.cloned(offset:through:), clone's part of
// issue #232's acceptance test: zero coverage returns the input, a full
// rectangle copies the shifted pixels exactly, sources off the edge leave
// pixels as they are, overlap reads the input (no smear), soft coverage mixes,
// and a wrong-size mask throws.
import CoreRaster
import Testing

private func randomBuffer(_ w: Int, _ h: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w {
            try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied())
        }
    }
    return buffer
}

/// A one-row buffer of opaque grays with the given red-green-blue values.
private func row(_ values: [Float]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: values.count, height: 1)
    for (x, v) in values.enumerated() {
        try buffer.setPixel(x: x, y: 0, RGBA(r: v, g: v, b: v, a: 1))
    }
    return buffer
}

@Test func zeroCoverageReturnsTheInput() throws {
    let input = try randomBuffer(7, 5, seed: 1)
    let mask = try Mask(width: 7, height: 5)
    #expect(try input.cloned(offset: (dx: 2, dy: 1), through: mask) == input)
}

@Test func fullRectangleClonesTheShiftedPixelsExactly() throws {
    let input = try randomBuffer(8, 6, seed: 2)
    let mask = try Mask.rectangle(width: 8, height: 6, x: 1, y: 1, w: 3, h: 2)
    let out = try input.cloned(offset: (dx: 3, dy: 2), through: mask)
    for y in 0..<6 {
        for x in 0..<8 {
            let inside = (1...3).contains(x) && (1...2).contains(y)
            let expected = inside ? try input.pixel(x: x + 3, y: y + 2) : try input.pixel(x: x, y: y)
            #expect(try out.pixel(x: x, y: y) == expected, "pixel (\(x), \(y))")
        }
    }
}

@Test func sourceOffTheEdgeLeavesThosePixelsUnchanged() throws {
    let input = try row([0.1, 0.2, 0.3, 0.4, 0.5])
    let full = try Mask(width: 5, height: 1, fill: 1)
    #expect(try input.cloned(offset: (dx: 3, dy: 0), through: full) == row([0.4, 0.5, 0.3, 0.4, 0.5]))
    #expect(try input.cloned(offset: (dx: -2, dy: 0), through: full) == row([0.1, 0.2, 0.1, 0.2, 0.3]))
    #expect(try input.cloned(offset: (dx: 0, dy: 1), through: full) == input)
}

@Test func overlappingSourceReadsTheInputSoNothingSmears() throws {
    let input = try row([0.1, 0.2, 0.3, 0.4])
    let full = try Mask(width: 4, height: 1, fill: 1)
    #expect(try input.cloned(offset: (dx: -1, dy: 0), through: full) == row([0.1, 0.1, 0.2, 0.3]))
}

@Test func softCoverageMixesSourceAndDestination() throws {
    let input = try row([0.8, 0.0])
    let quarter = try Mask(width: 2, height: 1, fill: 0.25)
    let out = try input.cloned(offset: (dx: -1, dy: 0), through: quarter)
    // Pixel 1 takes a quarter of pixel 0: 0.25 * 0.8 + 0.75 * 0 = 0.2.
    #expect(try out.pixel(x: 1, y: 0) == RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
    #expect(try out.pixel(x: 0, y: 0) == input.pixel(x: 0, y: 0))
}

@Test func maskOfTheWrongSizeThrows() throws {
    let input = try randomBuffer(4, 3, seed: 3)
    #expect(throws: RasterError.self) {
        try input.cloned(offset: (dx: 1, dy: 0), through: try Mask(width: 5, height: 4, fill: 1))
    }
}

@Test func extremeOffsetsReturnTheInputWithoutOverflow() throws {
    let input = try randomBuffer(4, 3, seed: 4)
    let full = try Mask(width: 4, height: 3, fill: 1)
    for offset in [(Int.max, 0), (Int.min, 0), (0, Int.max), (0, Int.min), (4, 0), (0, -3)] {
        #expect(try input.cloned(offset: (dx: offset.0, dy: offset.1), through: full) == input)
    }
}
