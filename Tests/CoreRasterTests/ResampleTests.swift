// ResampleTests.swift: PixelBuffer resize (bilinear, lanczos3), crop and
// quarter-turn rotation. Seeded sizes and pixels; invalid sizes and crops throw.
import CoreRaster
import Testing

private let filters: [ResampleFilter] = [.bilinear, .lanczos3]

private func randomBuffer(width: Int, height: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) }
    }
    return buffer
}

private func row(_ buffer: PixelBuffer, _ y: Int = 0) throws -> [RGBA] {
    try (0..<buffer.width).map { try buffer.pixel(x: $0, y: y) }
}

@Test func constantImageStaysConstantAtExactSizes() throws {
    var rng = SplitMix64(seed: 116)
    for _ in 0..<60 {
        let fill = randomPixel(&rng)
        let source = try PixelBuffer(width: .random(in: 1...20, using: &rng),
                                     height: .random(in: 1...20, using: &rng), fill: fill)
        let w = Int.random(in: 1...40, using: &rng)
        let h = Int.random(in: 1...40, using: &rng)
        for filter in filters {
            let out = try source.resized(width: w, height: h, filter: filter)
            #expect(out.width == w && out.height == h)
            for y in 0..<h {
                for x in 0..<w {
                    let p = try out.pixel(x: x, y: y)
                    #expect(abs(p.r - fill.r) <= 1e-6 && abs(p.g - fill.g) <= 1e-6)
                    #expect(abs(p.b - fill.b) <= 1e-6 && abs(p.a - fill.a) <= 1e-6)
                }
            }
        }
    }
}

@Test func downscalingACheckerGivesItsAverage() throws {
    let black = RGBA(r: 0, g: 0, b: 0, a: 1)
    let white = RGBA(r: 1, g: 1, b: 1, a: 1)
    var checker = try PixelBuffer(width: 2, height: 2, fill: black)
    try checker.setPixel(x: 1, y: 0, white)
    try checker.setPixel(x: 0, y: 1, white)
    for filter in filters {
        let p = try checker.resized(width: 1, height: 1, filter: filter).pixel(x: 0, y: 0)
        #expect(abs(p.r - 0.5) <= 1e-6 && abs(p.g - 0.5) <= 1e-6 && abs(p.b - 0.5) <= 1e-6)
        #expect(abs(p.a - 1) <= 1e-6)
    }
}

@Test func bilinearUpscaleInterpolatesAndClampsAtTheEdges() throws {
    var line = try PixelBuffer(width: 2, height: 1)
    try line.setPixel(x: 1, y: 0, RGBA(r: 1, g: 2, b: 4, a: 1))
    let out = try row(line.resized(width: 4, height: 1, filter: .bilinear))
    #expect(out.map(\.r) == [0, 0.25, 0.75, 1])
    #expect(out.map(\.b) == [0, 1, 3, 4])
    #expect(try line.resized(width: 2, height: 1, filter: .lanczos3) == line)
}

@Test func lanczosOvershootsAHardEdgeWhereBilinearDoesNot() throws {
    var step = try PixelBuffer(width: 4, height: 1)
    for x in 2..<4 { try step.setPixel(x: x, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1)) }
    let sharp = try row(step.resized(width: 16, height: 1, filter: .lanczos3)).map(\.r)
    let smooth = try row(step.resized(width: 16, height: 1, filter: .bilinear)).map(\.r)
    #expect((sharp.max() ?? 0) > 1 && (sharp.min() ?? 0) < 0)
    #expect(smooth.allSatisfy { (0...1).contains($0) })
}

@Test func resizeOverflowAndInvalidSizesThrow() throws {
    let big = Float.greatestFiniteMagnitude
    var step = try PixelBuffer(width: 4, height: 1, fill: RGBA(r: big, g: 0, b: 0, a: 1))
    try step.setPixel(x: 0, y: 0, RGBA(r: -big, g: 0, b: 0, a: 1))
    #expect(throws: RasterError.self) { try step.resized(width: 16, height: 1, filter: .lanczos3) }
    let image = try PixelBuffer(width: 3, height: 3)
    for (w, h) in [(0, 3), (3, 0), (-1, 5), (Int.max, 2), (16_385, 16_384)] {
        for filter in filters {
            #expect(throws: RasterError.self) { try image.resized(width: w, height: h, filter: filter) }
        }
    }
}

@Test func fourQuarterTurnsReturnTheOriginal() throws {
    var rng = SplitMix64(seed: 90)
    for _ in 0..<30 {
        let image = try randomBuffer(width: .random(in: 1...9, using: &rng),
                                     height: .random(in: 1...9, using: &rng), &rng)
        let once = image.rotated(.degrees90)
        #expect(once.width == image.height && once.height == image.width)
        #expect(once.rotated(.degrees90).rotated(.degrees90).rotated(.degrees90) == image)
        #expect(image.rotated(.degrees180) == once.rotated(.degrees90))
        #expect(image.rotated(.degrees270) == once.rotated(.degrees180))
        #expect(image.rotated(.degrees270).rotated(.degrees90) == image)
    }
}

@Test func quarterTurnIsClockwise() throws {
    let a = RGBA(r: 1, g: 0, b: 0, a: 1)
    let b = RGBA(r: 0, g: 1, b: 0, a: 1)
    var image = try PixelBuffer(width: 2, height: 1, fill: a)
    try image.setPixel(x: 1, y: 0, b)
    // [a b] turned clockwise is a column with a on top.
    let turned = image.rotated(.degrees90)
    #expect(try turned.pixel(x: 0, y: 0) == a && turned.pixel(x: 0, y: 1) == b)
    let back = image.rotated(.degrees270)
    #expect(try back.pixel(x: 0, y: 0) == b && back.pixel(x: 0, y: 1) == a)
    #expect(try row(image.rotated(.degrees180)) == [b, a])
}

@Test func cropCopiesTheRegion() throws {
    var rng = SplitMix64(seed: 4)
    let image = try randomBuffer(width: 7, height: 5, &rng)
    for _ in 0..<40 {
        let w = Int.random(in: 1...7, using: &rng)
        let h = Int.random(in: 1...5, using: &rng)
        let x = Int.random(in: 0...(7 - w), using: &rng)
        let y = Int.random(in: 0...(5 - h), using: &rng)
        let crop = try image.cropped(x: x, y: y, width: w, height: h)
        #expect(crop.width == w && crop.height == h)
        for cy in 0..<h {
            for cx in 0..<w { #expect(try crop.pixel(x: cx, y: cy) == image.pixel(x: x + cx, y: y + cy)) }
        }
    }
    #expect(try image.cropped(x: 0, y: 0, width: 7, height: 5) == image)
}

@Test func cropsOutsideTheBufferThrow() throws {
    var rng = SplitMix64(seed: 116_116)
    let image = try PixelBuffer(width: 6, height: 4)
    let edges = [Int.min, -7, -1, 0, 1, 3, 4, 6, 7, Int.max]
    var invalid = 0
    for _ in 0..<2_000 {
        let v = (0..<4).map { _ in edges.randomElement(using: &rng) ?? 0 }
        let (x, y, w, h) = (v[0], v[1], v[2], v[3])
        let inside = x >= 0 && y >= 0 && w >= 1 && h >= 1 && x <= 6 - w && y <= 4 - h
        if inside {
            #expect(try image.cropped(x: x, y: y, width: w, height: h).width == w)
        } else {
            invalid += 1
            #expect(throws: RasterError.self) { try image.cropped(x: x, y: y, width: w, height: h) }
        }
    }
    #expect(invalid > 1_000)
}
