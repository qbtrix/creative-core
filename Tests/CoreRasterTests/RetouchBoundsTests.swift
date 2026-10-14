// RetouchBoundsTests.swift: issue #257. Clone visits only the mask's covered
// rect, so a brush dab costs its area instead of a full-buffer pass. Each test
// checks the output is byte-identical to a full pass over every pixel (the
// loop before #257, kept here as the reference): a small dab, a full mask, an
// empty mask, dabs on each edge with negative and positive offsets, and a
// seeded fuzz. A timing test runs a 64x64 dab on 12 MP.
import CoreRaster
import Testing

/// Clone the way it ran before #257: every pixel whose source is on the
/// buffer, coverage 0 included.
private func fullPassClone(_ input: PixelBuffer, dx: Int, dy: Int, mask: Mask) throws -> PixelBuffer {
    var out = input
    for y in 0..<input.height where (0..<input.height).contains(y + dy) {
        for x in 0..<input.width where (0..<input.width).contains(x + dx) {
            let c = try mask.coverage(x: x, y: y)
            let s = try input.pixel(x: x + dx, y: y + dy)
            let d = try input.pixel(x: x, y: y)
            let k = 1 - c
            try out.setPixel(x: x, y: y, RGBA(r: s.r * c + d.r * k, g: s.g * c + d.g * k,
                                              b: s.b * c + d.b * k, a: s.a * c + d.a * k))
        }
    }
    return out
}

private func noise(_ w: Int, _ h: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
    }
    return buffer
}

private func expectMatchesFullPass(_ input: PixelBuffer, _ mask: Mask, offsets: [(Int, Int)]) throws {
    for (dx, dy) in offsets {
        let got = try input.cloned(offset: (dx: dx, dy: dy), through: mask)
        #expect(got == (try fullPassClone(input, dx: dx, dy: dy, mask: mask)), "offset (\(dx), \(dy))")
    }
}

private let offsets = [(0, 0), (3, 2), (-3, -2), (5, -1), (-4, 3), (11, 0), (0, -9), (-15, 8)]

@Test func smallDabMatchesTheFullPass() throws {
    var rng = SplitMix64(seed: 257)
    let input = try noise(16, 12, &rng)
    let dab = try Mask.ellipse(width: 16, height: 12, centerX: 7.3, centerY: 5.6, radiusX: 2.4, radiusY: 1.7)
    try expectMatchesFullPass(input, dab, offsets: offsets)
}

@Test func fullAndEmptyMasksMatchTheFullPass() throws {
    var rng = SplitMix64(seed: 2571)
    let input = try noise(13, 9, &rng)
    try expectMatchesFullPass(input, try Mask(width: 13, height: 9, fill: 1), offsets: offsets)
    try expectMatchesFullPass(input, try Mask(width: 13, height: 9, fill: 0.4), offsets: offsets)
    let empty = try Mask(width: 13, height: 9)
    try expectMatchesFullPass(input, empty, offsets: offsets)
    #expect(try input.cloned(offset: (dx: 2, dy: 1), through: empty) == input)
}

/// Dabs touching each edge and corner, with offsets that push the source off
/// the buffer on either side, so the covered rect and the source bounds clip.
@Test func dabsAtTheEdgesMatchTheFullPass() throws {
    var rng = SplitMix64(seed: 2572)
    let input = try noise(14, 10, &rng)
    let rects: [(Double, Double, Double, Double)] = [
        (0, 0, 3, 2), (11, 0, 3, 4), (0, 7, 5, 3), (12, 8, 2, 2), (0, 3, 14, 1), (6, 0, 1, 10),
    ]
    for (x, y, w, h) in rects {
        let mask = try Mask.rectangle(width: 14, height: 10, x: x, y: y, w: w, h: h)
        try expectMatchesFullPass(input, mask, offsets: offsets + [(-13, 0), (13, 0), (0, -9), (0, 9), (-1, 1), (1, -1)])
    }
}

@Test func seededFuzzMatchesTheFullPass() throws {
    var rng = SplitMix64(seed: 2573)
    for _ in 0..<150 {
        let w = Int.random(in: 1...12, using: &rng), h = Int.random(in: 1...12, using: &rng)
        let input = try noise(w, h, &rng)
        var mask = try Mask.ellipse(width: w, height: h,
                                    centerX: .random(in: -2...Double(w + 2), using: &rng),
                                    centerY: .random(in: -2...Double(h + 2), using: &rng),
                                    radiusX: .random(in: 0...Double(w) / 2, using: &rng),
                                    radiusY: .random(in: 0...Double(h) / 2, using: &rng))
        if Bool.random(using: &rng) {
            try mask.add(Mask.rectangle(width: w, height: h, x: .random(in: 0...Double(w), using: &rng),
                                        y: .random(in: 0...Double(h), using: &rng), w: 1, h: 1))
        }
        let dx = Int.random(in: -(w + 1)...(w + 1), using: &rng)
        let dy = Int.random(in: -(h + 1)...(h + 1), using: &rng)
        try expectMatchesFullPass(input, mask, offsets: [(dx, dy)])
    }
}

/// A 64x64 dab on 12 MP. Before #257 one call took about 0.6 s in release and
/// 4.5 s in debug; the dab's own pixels are now the only per-pixel work.
@Test func smallDabOn12MegapixelsIsFast() throws {
    let width = 4000, height = 3000
    let gray = RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1)
    var input = try PixelBuffer(width: width, height: height, fill: gray)
    let source = RGBA(r: 0.9, g: 0.1, b: 0.4, a: 1)
    for y in 1500..<1564 {
        for x in 2300..<2364 { try input.setPixel(x: x, y: y, source) }
    }
    let dab = try Mask.rectangle(width: width, height: height, x: 2000, y: 1500, w: 64, h: 64)
    var out = input
    let elapsed = try ContinuousClock().measure {
        out = try input.cloned(offset: (dx: 300, dy: 0), through: dab)
    }
    print("clone 64x64 dab on \(width)x\(height): \(elapsed) (was ~0.6 s release, ~4.5 s debug)")
    #expect(elapsed < .seconds(1.5))
    #expect(try out.pixel(x: 2000, y: 1500) == source)
    #expect(try out.pixel(x: 2063, y: 1563) == source)
    #expect(try out.pixel(x: 2064, y: 1563) == gray)
    #expect(try out.pixel(x: 1999, y: 1500) == gray)
}
