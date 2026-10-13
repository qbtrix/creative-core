// RotateTests.swift: PixelBuffer rotation by any angle and straightenCrop.
// Quarter turns stay exact, the turned size is the rotated bounds, a turn is
// clockwise, the border is anti-aliased, and the crop holds only opaque image
// pixels with the original aspect ratio. Non-finite angles throw.
import CoreRaster
import Testing
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private let filters: [ResampleFilter] = [.bilinear, .lanczos3]

private func randomBuffer(width: Int, height: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) }
    }
    return buffer
}

@Test func zeroAndFullTurnsReturnTheInputUnchanged() throws {
    let image = try randomBuffer(width: 9, height: 5, seed: 230)
    for degrees in [0.0, -0.0, 360, -720] {
        for filter in filters { #expect(try image.rotated(degrees: degrees, filter: filter) == image) }
    }
}

@Test func multiplesOfNinetyAreTheExactQuarterTurns() throws {
    let image = try randomBuffer(width: 7, height: 4, seed: 231)
    let cases: [(Double, QuarterTurn)] = [
        (90, .degrees90), (180, .degrees180), (270, .degrees270), (-90, .degrees270), (450, .degrees90),
    ]
    for (degrees, turn) in cases {
        for filter in filters { #expect(try image.rotated(degrees: degrees, filter: filter) == image.rotated(turn)) }
    }
}

@Test func theTurnedSizeHoldsTheWholeRotatedImage() throws {
    let image = try PixelBuffer(width: 400, height: 300, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
    let out = try image.rotated(degrees: 10, filter: .bilinear)
    let t = 10 * Double.pi / 180
    #expect(out.width == Int((400 * cos(t) + 300 * sin(t)).rounded(.up)))
    #expect(out.height == Int((400 * sin(t) + 300 * cos(t)).rounded(.up)))
    #expect(try out.pixel(x: 0, y: 0) == .clear)
}

@Test func aPositiveAngleTurnsClockwise() throws {
    // A left-to-right ramp: turned clockwise, the right half swings down, so
    // the pixel below the center is brighter than the one above it.
    var ramp = try PixelBuffer(width: 41, height: 41)
    for y in 0..<41 {
        for x in 0..<41 { try ramp.setPixel(x: x, y: y, RGBA(r: Float(x) / 40, g: 0, b: 0, a: 1)) }
    }
    for filter in filters {
        let out = try ramp.rotated(degrees: 30, filter: filter)
        let (cx, cy) = (out.width / 2, out.height / 2)
        #expect(try out.pixel(x: cx, y: cy + 10).r > out.pixel(x: cx, y: cy - 10).r)
    }
}

@Test func aConstantImageIsConstantAndOpaqueInsideTheCrop() throws {
    let fill = RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)
    for (width, height) in [(160, 120), (61, 97)] {
        let image = try PixelBuffer(width: width, height: height, fill: fill)
        for degrees in [7.5, -7.5, 33] {
            let crop = try PixelBuffer.straightenCrop(width: width, height: height, degrees: degrees)
            for filter in filters {
                let out = try image.rotated(degrees: degrees, filter: filter)
                #expect(crop.x >= 0 && crop.y >= 0 && crop.x + crop.width <= out.width && crop.y + crop.height <= out.height)
                var worst: Float = 0
                for y in crop.y..<(crop.y + crop.height) {
                    for x in crop.x..<(crop.x + crop.width) {
                        let p = try out.pixel(x: x, y: y)
                        worst = max(worst, abs(p.r - fill.r), abs(p.g - fill.g), abs(p.b - fill.b), abs(p.a - 1))
                    }
                }
                #expect(worst <= 1e-5, "\(width)x\(height) at \(degrees) with \(filter): off by \(worst)")
            }
        }
    }
}

@Test func theBorderIsAntiAliased() throws {
    let image = try PixelBuffer(width: 64, height: 48, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
    for filter in filters {
        let out = try image.rotated(degrees: 7.5, filter: filter)
        var partial = 0
        for y in 0..<out.height {
            for x in 0..<out.width {
                let p = try out.pixel(x: x, y: y)
                #expect(p.isFinite)
                if p.a > 0.05, p.a < 0.95 { partial += 1 }
            }
        }
        #expect(partial > out.height, "\(filter) left \(partial) partly covered pixels")
    }
}

@Test func theCropKeepsTheAspectRatioAndIsCentered() throws {
    for (width, height) in [(400, 300), (300, 400), (64, 48)] {
        for degrees in [0.5, 5, -12, 45, 90.25] {
            let crop = try PixelBuffer.straightenCrop(width: width, height: height, degrees: degrees)
            let t = degrees * Double.pi / 180
            let turnedWidth = Int((Double(width) * abs(cos(t)) + Double(height) * abs(sin(t))).rounded(.up))
            #expect(crop.width >= 1 && crop.height >= 1 && crop.width <= width && crop.height <= height)
            #expect(abs(Double(crop.width) - Double(crop.height) * Double(width) / Double(height)) <= 1)
            #expect(abs(2 * crop.x + crop.width - turnedWidth) <= 1)
        }
    }
    // Too thin to keep the ratio: still at least one pixel, inside the image.
    let sliver = try PixelBuffer.straightenCrop(width: 1000, height: 17, degrees: -12)
    #expect(sliver.width >= 1 && sliver.height >= 1 && sliver.x >= 0 && sliver.y >= 0)
    let whole = try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: 0)
    #expect(whole.x == 0 && whole.y == 0 && whole.width == 400 && whole.height == 300)
    let upright = try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: 90)
    #expect(upright.x == 0 && upright.y == 87 && upright.width == 300 && upright.height == 225)
}

@Test func theCropIsTheLargestThatStaysClearOfTheKernel() throws {
    // One pixel more on each side would let the widest kernel (lanczos3,
    // radius 3) read past the image, so the crop is tight to within 2 pixels.
    let crop = try PixelBuffer.straightenCrop(width: 400, height: 300, degrees: 10)
    let t = 10 * Double.pi / 180
    let k = min(395 / (400 * cos(t) + 300 * sin(t)), 295 / (400 * sin(t) + 300 * cos(t)))
    #expect(crop.height >= Int(k * 300) - 1 && crop.height <= Int(k * 300))
}

@Test func nonFiniteAnglesAndBadSizesThrow() throws {
    let image = try PixelBuffer(width: 4, height: 4)
    for degrees in [Double.nan, .infinity, -.infinity] {
        #expect(throws: RasterError.self) { try image.rotated(degrees: degrees, filter: .bilinear) }
        #expect(throws: RasterError.self) { try PixelBuffer.straightenCrop(width: 4, height: 4, degrees: degrees) }
    }
    #expect(throws: RasterError.self) { try PixelBuffer.straightenCrop(width: 0, height: 4, degrees: 5) }
}
