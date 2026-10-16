// DisplayBytesFastPathTests.swift: issue #311 (RT-2). `rgba8` and
// `init(rgba8:)` run over CoreColor's DisplayTransfer tables in one pass; each
// test checks them against the per-pixel loops they replaced (kept here as the
// reference, through `Color3.converted`): every byte value per channel in
// sRGB and Display P3 at alpha 0, 1, 128 and 255, seeded random buffers and
// the tiny alphas whose unpremultiply overflows Float, a region encode against
// `cropped` then `rgba8` tile by tile, and every bad rect or space throws.
import CoreColor
import CoreRaster
import Testing

/// `rgba8(colorSpace:)` the way it ran before RT-2: `Color3.converted` per pixel.
private func referenceRGBA8(_ buffer: PixelBuffer, _ space: ColorSpace) throws -> [UInt8] {
    let finite = { (v: Float) in Double(min(max(v, -.greatestFiniteMagnitude), .greatestFiniteMagnitude)) }
    let byte = { (v: Double) in UInt8((v * 255).rounded()) }
    var bytes: [UInt8] = []
    for y in 0..<buffer.height {
        for x in 0..<buffer.width {
            let s = try buffer.pixel(x: x, y: y).unpremultiplied()
            let encoded = try Color3(finite(s.r), finite(s.g), finite(s.b))
                .converted(from: .linearSRGB, to: space).clampedToUnit()
            bytes += [byte(encoded.c0), byte(encoded.c1), byte(encoded.c2), byte(min(max(Double(s.a), 0), 1))]
        }
    }
    return bytes
}

/// `init(rgba8:width:height:colorSpace:)` the way it ran before RT-2.
private func referenceDecode(_ bytes: [UInt8], width: Int, height: Int, _ space: ColorSpace) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for i in stride(from: 0, to: bytes.count, by: 4) {
        let encoded = Color3(Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255)
        let linear = try encoded.converted(from: space, to: .linearSRGB)
        let p = RGBA(r: Float(linear.c0), g: Float(linear.c1), b: Float(linear.c2),
                     a: Float(bytes[i + 3]) / 255).premultiplied()
        try buffer.setPixel(x: (i / 4) % width, y: (i / 4) / width, p)
    }
    return buffer
}

@Test func everyByteDecodesAndEncodesAsBefore() throws {
    // One row per alpha: a gray ramp and the three one-channel ramps.
    let alphas: [UInt8] = [0, 1, 128, 255]
    var bytes: [UInt8] = []
    for alpha in alphas {
        for v in 0...255 {
            let b = UInt8(v)
            bytes += [b, b, b, alpha, b, 0, 0, alpha, 0, b, 0, alpha, 0, 0, b, alpha]
        }
    }
    let (width, height) = (256 * 4, alphas.count)
    for space in PixelBuffer.displayColorSpaces {
        let fast = try PixelBuffer(rgba8: bytes, width: width, height: height, colorSpace: space)
        let reference = try referenceDecode(bytes, width: width, height: height, space)
        #expect(fast == reference)
        #expect(try fast.rgba8(colorSpace: space) == referenceRGBA8(reference, space))
    }
}

@Test func randomAndTinyAlphaPixelsEncodeAsBefore() throws {
    var rng = SplitMix64(seed: 311)
    var buffers: [PixelBuffer] = []
    for _ in 0..<50 {
        let (w, h) = (Int.random(in: 1...24, using: &rng), Int.random(in: 1...24, using: &rng))
        var buffer = try PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
        }
        buffers.append(buffer)
    }
    // Premultiplied colors over alpha 1e-38 and 1e-45: some divide to past
    // Float's range (the finite clamp), some stay finite.
    var tiny = try PixelBuffer(width: 8, height: 1)
    let colors: [Float] = [1000, 0.5, -3, 1e-40]
    for (i, alpha) in [Float(1e-38), Float(1e-45)].enumerated() {
        for (j, v) in colors.enumerated() {
            try tiny.setPixel(x: i * 4 + j, y: 0, RGBA(r: v, g: -v, b: v / 2, a: alpha))
        }
    }
    buffers.append(tiny)
    for buffer in buffers {
        for space in PixelBuffer.displayColorSpaces {
            #expect(try buffer.rgba8(colorSpace: space) == referenceRGBA8(buffer, space))
        }
    }
}

@Test func regionEqualsCropThenEncode() throws {
    var rng = SplitMix64(seed: 3110)
    var buffer = try PixelBuffer(width: 600, height: 300)
    for y in 0..<300 {
        for x in 0..<600 { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
    }
    var rects: [(Int, Int, Int, Int)] = []
    for y in stride(from: 0, to: 300, by: 256) {
        for x in stride(from: 0, to: 600, by: 256) { rects.append((x, y, min(256, 600 - x), min(256, 300 - y))) }
    }
    rects += [(0, 0, 1, 1), (599, 0, 1, 1), (0, 299, 1, 1), (599, 299, 1, 1), (0, 0, 600, 300)]
    for (x, y, w, h) in rects {
        for space in PixelBuffer.displayColorSpaces {
            let region = try buffer.rgba8(x: x, y: y, width: w, height: h, colorSpace: space)
            #expect(region == (try buffer.cropped(x: x, y: y, width: w, height: h).rgba8(colorSpace: space)))
        }
    }
    #expect(try buffer.rgba8(x: 0, y: 0, width: 600, height: 300) == buffer.rgba8())
}

@Test func badRegionsAndSpacesThrowAsCropDoes() throws {
    let buffer = try PixelBuffer(width: 600, height: 300, fill: RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
    let bad = [(-1, 0, 10, 10), (0, -1, 10, 10), (591, 0, 10, 10), (0, 291, 10, 10), (1, 0, 600, 1),
               (0, 1, 1, 300), (0, 0, 601, 1), (0, 0, 1, 301), (0, 0, 0, 1), (0, 0, 1, 0), (5, 5, -2, 3),
               (Int.max, 0, 1, 1), (0, Int.min, 1, 1)]
    for (x, y, w, h) in bad {
        var expected: RasterError?
        do { _ = try buffer.cropped(x: x, y: y, width: w, height: h) } catch let e as RasterError { expected = e }
        #expect(expected != nil)
        #expect(throws: expected ?? RasterError.invalid("")) {
            try buffer.rgba8(x: x, y: y, width: w, height: h, colorSpace: .displayP3)
        }
    }
    let spaceError = RasterError.invalid("color space oklab: display bytes must be sRGB or displayP3")
    #expect(throws: spaceError) { try buffer.rgba8(x: -1, y: 0, width: 0, height: 0, colorSpace: .oklab) }
    for space in ColorSpace.allCases where !PixelBuffer.displayColorSpaces.contains(space) {
        #expect(throws: RasterError.self) { try buffer.rgba8(x: 0, y: 0, width: 1, height: 1, colorSpace: space) }
    }
}
