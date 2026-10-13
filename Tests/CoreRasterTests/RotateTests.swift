// RotateTests.swift: PixelBuffer rotation by any angle and the straighten crop.
// Quarter turns are exact, the turned size and the crop match their closed
// forms, a constant opaque image stays constant and opaque inside the crop,
// corners are transparent, and non-finite angles throw.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

private let filters: [ResampleFilter] = [.bilinear, .lanczos3]

private func radians(_ degrees: Double) -> Double { degrees * Double.pi / 180 }

private func randomBuffer(width: Int, height: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
    }
    return buffer
}

@Test func multiplesOfNinetyMatchQuarterTurnsExactly() throws {
    var rng = SplitMix64(seed: 230)
    let source = try randomBuffer(width: 7, height: 4, &rng)
    for filter in filters {
        #expect(try source.rotated(degrees: 0, filter: filter) == source)
        #expect(try source.rotated(degrees: 360, filter: filter) == source)
        #expect(try source.rotated(degrees: 90, filter: filter) == source.rotated(.degrees90))
        #expect(try source.rotated(degrees: 180, filter: filter) == source.rotated(.degrees180))
        #expect(try source.rotated(degrees: 270, filter: filter) == source.rotated(.degrees270))
        #expect(try source.rotated(degrees: -90, filter: filter) == source.rotated(.degrees270))
        #expect(try source.rotated(degrees: 450, filter: filter) == source.rotated(.degrees90))
    }
}

@Test func turnedSizeIsTheBoundingBox() throws {
    let source = try PixelBuffer(width: 400, height: 300, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
    let out = try source.rotated(degrees: 10, filter: .bilinear)
    let t = radians(10)
    #expect(out.width == Int((400 * cos(t) + 300 * sin(t)).rounded(.up)))
    #expect(out.height == Int((400 * sin(t) + 300 * cos(t)).rounded(.up)))
    #expect(out.width == 447 && out.height == 365)
    // A negative angle has the same bounds.
    let back = try source.rotated(degrees: -10, filter: .bilinear)
    #expect(back.width == out.width && back.height == out.height)
}

@Test func constantOpaqueImageStaysConstantInsideTheCrop() throws {
    let fill = RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)
    let source = try PixelBuffer(width: 400, height: 300, fill: fill)
    for degrees in [7.5, -7.5] {
        let crop = try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: degrees)
        #expect(abs(Double(crop.width) - Double(crop.height) * 4 / 3) <= 1)
        for filter in filters {
            let out = try source.rotated(degrees: degrees, filter: filter)
            #expect(crop.x >= 0 && crop.y >= 0)
            #expect(crop.x + crop.width <= out.width && crop.y + crop.height <= out.height)
            var worst: Float = 0
            for y in crop.y..<(crop.y + crop.height) {
                for x in crop.x..<(crop.x + crop.width) {
                    let p = try out.pixel(x: x, y: y)
                    worst = max(worst, abs(p.r - fill.r), abs(p.g - fill.g), abs(p.b - fill.b), abs(p.a - 1))
                }
            }
            #expect(worst <= 1e-5)
            // The uncovered corners are transparent and the border is anti-aliased.
            #expect(try out.pixel(x: 0, y: 0) == .clear)
            #expect(try out.pixel(x: out.width - 1, y: out.height - 1) == .clear)
            #expect(try (0..<out.width).contains { x in
                let a = try out.pixel(x: x, y: 2).a
                return a > 0.01 && a < 0.99
            })
        }
    }
}

@Test func turnIsClockwise() throws {
    // One opaque pixel right of center turns down (y grows downward).
    var source = try PixelBuffer(width: 21, height: 21)
    try source.setPixel(x: 18, y: 10, RGBA(r: 1, g: 1, b: 1, a: 1))
    let out = try source.rotated(degrees: 30, filter: .bilinear)
    var best = (x: 0, y: 0, a: Float(0))
    for y in 0..<out.height {
        for x in 0..<out.width {
            let a = try out.pixel(x: x, y: y).a
            if a > best.a { best = (x, y, a) }
        }
    }
    let cx = Double(out.width) / 2 - 0.5, cy = Double(out.height) / 2 - 0.5
    #expect(abs(Double(best.x) - (cx + 8 * cos(radians(30)))) <= 1)
    #expect(abs(Double(best.y) - (cy + 8 * sin(radians(30)))) <= 1)
}

@Test func everyComponentIsFinite() throws {
    var rng = SplitMix64(seed: 2300)
    for _ in 0..<8 {
        let source = try randomBuffer(width: .random(in: 1...12, using: &rng),
                                      height: .random(in: 1...12, using: &rng), &rng)
        let degrees = Double.random(in: -720...720, using: &rng)
        for filter in filters {
            let out = try source.rotated(degrees: degrees, filter: filter)
            for y in 0..<out.height {
                for x in 0..<out.width { #expect(try out.pixel(x: x, y: y).isFinite) }
            }
        }
    }
}

@Test func cropAtQuarterTurnsIsTheWholeImage() throws {
    #expect(try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: 0) == (0, 0, 400, 300))
    #expect(try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: 90) == (0, 0, 300, 400))
    #expect(try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: -180) == (0, 0, 400, 300))
}

@Test func cropMatchesTheClosedForm() throws {
    // k = min((w - 1 - c - s) / (w c + h s), (h - 1 - c - s) / (w s + h c)); the
    // shorter side is floor(k * side) and the longer follows the ratio.
    for (w, h, degrees) in [(400, 300, 5.0), (300, 400, -3.0), (256, 256, 10.0), (1000, 200, 2.0)] {
        let c = abs(cos(radians(degrees))), s = abs(sin(radians(degrees)))
        let (dw, dh) = (Double(w), Double(h))
        let k = min((dw - 1 - c - s) / (dw * c + dh * s), (dh - 1 - c - s) / (dw * s + dh * c))
        let short = Int((k * Double(min(w, h))).rounded(.down))
        let long = short * max(w, h) / min(w, h)
        let crop = try PixelBuffer.straightenCrop(width: w, height: h, degrees: degrees)
        #expect(crop.width == (w >= h ? long : short) && crop.height == (w >= h ? short : long))
        let outWidth = Int((dw * c + dh * s).rounded(.up))
        let outHeight = Int((dw * s + dh * c).rounded(.up))
        #expect(crop.x == (outWidth - crop.width) / 2 && crop.y == (outHeight - crop.height) / 2)
    }
    // A square at 45 degrees keeps a centered square of side about w / sqrt(2).
    let square = try PixelBuffer.straightenCrop(width: 200, height: 200, degrees: 45)
    #expect(square.width == square.height)
    #expect(abs(Double(square.width) - 200 / 2.0.squareRoot()) <= 3)
}

@Test func nonFiniteAnglesAndTinyImagesThrow() throws {
    let source = try PixelBuffer(width: 3, height: 2)
    for bad in [Double.nan, .infinity, -.infinity] {
        #expect(throws: RasterError.self) { try source.rotated(degrees: bad, filter: .bilinear) }
        #expect(throws: RasterError.self) { try PixelBuffer.straightenCrop(width: 3, height: 2, degrees: bad) }
    }
    #expect(throws: RasterError.self) { try PixelBuffer.straightenCrop(width: 2, height: 2, degrees: 45) }
    #expect(throws: RasterError.self) { try PixelBuffer.straightenCrop(width: 0, height: 2, degrees: 5) }
}
