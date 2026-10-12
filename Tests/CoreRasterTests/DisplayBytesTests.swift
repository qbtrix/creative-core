// DisplayBytesTests.swift: PixelBuffer to and from 8-bit RGBA display bytes.
// Known values (linear 0.5 is sRGB byte 188, sRGB red in Display P3),
// unpremultiplying, clamping, transparent pixels, round trips on seeded
// random pixels and bytes in both color spaces, and every bad size, byte
// count or color space throws, with a seeded fuzz that never crashes.
import CoreColor
import CoreRaster
import Testing

/// A 1-row buffer holding `pixels` (premultiplied).
private func row(_ pixels: [RGBA]) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: pixels.count, height: 1)
    for (x, p) in pixels.enumerated() {
        try buffer.setPixel(x: x, y: 0, p)
    }
    return buffer
}

@Test func knownSRGBValuesEncode() throws {
    let bytes = try row([
        RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1),
        RGBA(r: 0, g: 1, b: 0.0031308, a: 1),
        RGBA(r: 0.25, g: 0.25, b: 0.25, a: 0.5),
    ]).rgba8()
    #expect(bytes == [188, 188, 188, 255,
                      0, 255, 10, 255,
                      188, 188, 188, 128])
}

@Test func transparentPixelsEncodeAsZero() throws {
    let buffer = try PixelBuffer(width: 2, height: 2)
    #expect(try buffer.rgba8() == [UInt8](repeating: 0, count: 16))
    #expect(try buffer.rgba8(colorSpace: .displayP3) == [UInt8](repeating: 0, count: 16))
}

@Test func outOfRangeValuesClamp() throws {
    let bytes = try row([
        RGBA(r: 3, g: -1, b: 0.5, a: 1),
        RGBA(r: 1e30, g: -1e30, b: 0, a: 1e-30),
        RGBA(r: 1, g: 1, b: 1, a: 2),
    ]).rgba8()
    #expect(bytes == [255, 0, 188, 255,
                      255, 0, 0, 0,
                      188, 188, 188, 255])
}

@Test func sRGBRedEncodesInsideDisplayP3() throws {
    let bytes = try row([RGBA(r: 1, g: 0, b: 0, a: 1)]).rgba8(colorSpace: .displayP3)
    #expect(bytes == [234, 51, 35, 255])
}

@Test func bytesDecodeToLinearPremultiplied() throws {
    let buffer = try PixelBuffer(rgba8: [188, 0, 255, 255, 255, 255, 255, 0], width: 2, height: 1)
    let p = try buffer.pixel(x: 0, y: 0)
    #expect(abs(p.r - 0.5029) < 1e-4)
    #expect(p.g == 0 && p.b == 1 && p.a == 1)
    #expect(try buffer.pixel(x: 1, y: 0) == .clear)
    let half = try PixelBuffer(rgba8: [255, 255, 255, 51], width: 1, height: 1).pixel(x: 0, y: 0)
    #expect(half == RGBA(r: 0.2, g: 0.2, b: 0.2, a: 0.2))
}

@Test func opaqueBytesRoundTripExactly() throws {
    var rng = SplitMix64(seed: 141)
    for space in PixelBuffer.displayColorSpaces {
        for _ in 0..<20 {
            let (w, h) = (Int.random(in: 1...6, using: &rng), Int.random(in: 1...6, using: &rng))
            var bytes = (0..<(w * h * 4)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
            let buffer = try PixelBuffer(rgba8: bytes, width: w, height: h, colorSpace: space)
            #expect(try buffer.rgba8(colorSpace: space) == bytes)
        }
    }
}

@Test func opaquePixelsRoundTripWithinOneStep() throws {
    var rng = SplitMix64(seed: 1410)
    for space in PixelBuffer.displayColorSpaces {
        for _ in 0..<200 {
            let p = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                         b: .random(in: 0...1, using: &rng), a: 1)
            let back = try PixelBuffer(rgba8: row([p]).rgba8(colorSpace: space), width: 1, height: 1,
                                       colorSpace: space).pixel(x: 0, y: 0)
            let encode = { (q: RGBA) in
                try Color3(Double(q.r), Double(q.g), Double(q.b)).converted(from: .linearSRGB, to: space)
            }
            let (a, b) = (try encode(p), try encode(back))
            #expect(abs(a.c0 - b.c0) <= 1.0 / 255 && abs(a.c1 - b.c1) <= 1.0 / 255 && abs(a.c2 - b.c2) <= 1.0 / 255)
            #expect(back.a == 1)
        }
    }
}

@Test func badByteCountsAndColorSpacesThrow() throws {
    for count in [0, 3, 5, 7, 9, 16] {
        #expect(throws: RasterError.self) {
            try PixelBuffer(rgba8: [UInt8](repeating: 0, count: count), width: 2, height: 1)
        }
    }
    let buffer = try PixelBuffer(width: 1, height: 1)
    for space in ColorSpace.allCases where !PixelBuffer.displayColorSpaces.contains(space) {
        #expect(throws: RasterError.self) { try buffer.rgba8(colorSpace: space) }
        #expect(throws: RasterError.self) {
            try PixelBuffer(rgba8: [0, 0, 0, 0], width: 1, height: 1, colorSpace: space)
        }
    }
    #expect(throws: RasterError.self) { try PixelBuffer(rgba8: [], width: 0, height: 0) }
    #expect(throws: RasterError.self) { try PixelBuffer(rgba8: [], width: Int.max, height: 2) }
}

@Test func sizeAndByteFuzzNeverCrashes() throws {
    var rng = SplitMix64(seed: 14141)
    for _ in 0..<500 {
        let (w, h) = (Int.random(in: -3...8, using: &rng), Int.random(in: -3...8, using: &rng))
        let count = Bool.random(using: &rng) ? max(w * h * 4, 0) : Int.random(in: 0...300, using: &rng)
        let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let space = ColorSpace.allCases.randomElement(using: &rng) ?? .sRGB
        do {
            let buffer = try PixelBuffer(rgba8: bytes, width: w, height: h, colorSpace: space)
            #expect(w >= 1 && h >= 1 && bytes.count == w * h * 4)
            #expect(try buffer.rgba8(colorSpace: space).count == bytes.count)
        } catch {
            #expect(error is RasterError)
        }
    }
}
