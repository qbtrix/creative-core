// RetouchBoundsTests.swift: issue #257. Clone loops only over the mask's
// covered rect, and its output stays bit-identical to the full pass that mixes
// every pixel whose source is on the buffer: a small dab, a full mask, an
// empty mask, and dabs at the edges with negative and positive offsets. A
// 64x64 dab on 12 megapixels reports its time and must stay well under the
// old full pass (about 0.6 s in release, 4.5 s in debug).
import CoreRaster
import Testing

private func randomBuffer(_ w: Int, _ h: Int, seed: UInt64) throws -> PixelBuffer {
    var rng = SplitMix64(seed: seed)
    var buffer = try PixelBuffer(width: w, height: h)
    for y in 0..<h {
        for x in 0..<w { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
    }
    return buffer
}

/// The full pass: every pixel whose source is on the buffer is mixed by its
/// coverage, even coverage 0, the way clone worked before #257.
private func fullPass(_ input: PixelBuffer, _ dx: Int, _ dy: Int, _ mask: Mask) throws -> PixelBuffer {
    var out = input
    for y in 0..<input.height where (0..<input.height).contains(y + dy) {
        for x in 0..<input.width where (0..<input.width).contains(x + dx) {
            let c = try mask.coverage(x: x, y: y)
            let s = try input.pixel(x: x + dx, y: y + dy), b = try input.pixel(x: x, y: y)
            let mix = { (s: Float, b: Float) in s * c + b * (1 - c) }
            try out.setPixel(x: x, y: y, RGBA(r: mix(s.r, b.r), g: mix(s.g, b.g),
                                              b: mix(s.b, b.b), a: mix(s.a, b.a)))
        }
    }
    return out
}

/// Expects every component of every pixel to have the same bits.
private func expectBitIdentical(_ a: PixelBuffer, _ b: PixelBuffer, _ label: String) throws {
    for y in 0..<a.height {
        for x in 0..<a.width {
            let p = try a.pixel(x: x, y: y), q = try b.pixel(x: x, y: y)
            let same = [p.r, p.g, p.b, p.a].map(\.bitPattern) == [q.r, q.g, q.b, q.a].map(\.bitPattern)
            #expect(same, "\(label): (\(x), \(y)) \(p) vs \(q)")
        }
    }
}

@Test func boundedCloneMatchesTheFullPassBitForBit() throws {
    let w = 24, h = 18
    let input = try randomBuffer(w, h, seed: 257)
    let cases: [(String, Mask, Int, Int)] = [
        ("small dab", try Mask.ellipse(width: w, height: h, centerX: 10, centerY: 8, radiusX: 2.5, radiusY: 2), 5, 3),
        ("full mask", try Mask(width: w, height: h, fill: 1), -3, 2),
        ("soft full mask", try Mask(width: w, height: h, fill: 0.37), 4, -5),
        ("empty mask", try Mask(width: w, height: h), 2, 2),
        ("top-left edge, negative offset", try Mask.ellipse(width: w, height: h, centerX: 1, centerY: 1,
                                                             radiusX: 3, radiusY: 3), -2, -1),
        ("top-left edge, positive offset", try Mask.ellipse(width: w, height: h, centerX: 1, centerY: 1,
                                                             radiusX: 3, radiusY: 3), 6, 4),
        ("bottom-right edge, positive offset", try Mask.ellipse(width: w, height: h, centerX: 23, centerY: 17,
                                                                 radiusX: 3, radiusY: 3), 2, 1),
        ("bottom-right edge, negative offset", try Mask.ellipse(width: w, height: h, centerX: 23, centerY: 17,
                                                                 radiusX: 3, radiusY: 3), -7, -6),
        ("dab whose sources are all off the buffer", try Mask.rectangle(width: w, height: h, x: 20, y: 2,
                                                                         w: 4, h: 3), 5, 0),
    ]
    for (label, mask, dx, dy) in cases {
        let out = try input.cloned(offset: (dx: dx, dy: dy), through: mask)
        try expectBitIdentical(out, try fullPass(input, dx, dy, mask), label)
    }
}

@Test func boundedCloneFuzzMatchesTheFullPass() throws {
    var rng = SplitMix64(seed: 2570)
    for i in 0..<100 {
        let w = Int.random(in: 1...12, using: &rng), h = Int.random(in: 1...12, using: &rng)
        let input = try randomBuffer(w, h, seed: rng.next())
        let mask = try Mask.ellipse(width: w, height: h,
                                    centerX: .random(in: -2...Double(w + 2), using: &rng),
                                    centerY: .random(in: -2...Double(h + 2), using: &rng),
                                    radiusX: .random(in: 0...Double(w) / 2, using: &rng),
                                    radiusY: .random(in: 0...Double(h) / 2, using: &rng))
        let dx = Int.random(in: -w...w, using: &rng), dy = Int.random(in: -h...h, using: &rng)
        let out = try input.cloned(offset: (dx: dx, dy: dy), through: mask)
        try expectBitIdentical(out, try fullPass(input, dx, dy, mask), "case \(i) offset (\(dx), \(dy))")
    }
}

@Test func smallDabOn12MegapixelsCostsFarLessThanTheFullPass() throws {
    let width = 4000, height = 3000
    let buffer = try PixelBuffer(width: width, height: height, fill: RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
    let paint = RGBA(r: 0.8, g: 0.1, b: 0.1, a: 1)
    var input = buffer
    for y in 1500..<1564 {
        for x in 2300..<2364 { try input.setPixel(x: x, y: y, paint) }
    }
    let mask = try Mask.rectangle(width: width, height: height, x: 2000, y: 1500, w: 64, h: 64)
    var out = input
    let elapsed = try ContinuousClock().measure {
        out = try input.cloned(offset: (dx: 300, dy: 0), through: mask)
    }
    print("clone of a 64x64 dab on \(width)x\(height): \(elapsed) (full pass was about 0.6 s release, 4.5 s debug)")
    #expect(elapsed < .seconds(1.5))
    #expect(try out.pixel(x: 2000, y: 1500) == paint)
    #expect(try out.pixel(x: 2063, y: 1563) == paint)
    #expect(try out.pixel(x: 2064, y: 1500) == buffer.pixel(x: 2064, y: 1500))
    #expect(try out.pixel(x: 1999, y: 1563) == buffer.pixel(x: 1999, y: 1563))
}
