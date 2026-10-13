// RetouchAdversarialTests.swift: seeded fuzz and boundary tests for
// PixelBuffer.cloned(offset:through:) against issue #232's clone rules. Random
// sizes, offsets at and around the buffer edges, and soft ellipse masks: zero
// coverage keeps a pixel exactly, a source off the buffer keeps it exactly,
// full coverage copies the input's source pixel exactly, and nothing throws
// for a matching mask. Huge finite components mix without throwing.
import CoreRaster
import Testing

@Test func cloneFuzzKeepsTheRulesAtEveryOffset() throws {
    var rng = SplitMix64(seed: 232)
    for _ in 0..<200 {
        let w = Int.random(in: 1...9, using: &rng)
        let h = Int.random(in: 1...9, using: &rng)
        var input = try PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w { try input.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
        }
        let mask = try Mask.ellipse(width: w, height: h,
                                    centerX: .random(in: -2...Double(w + 2), using: &rng),
                                    centerY: .random(in: -2...Double(h + 2), using: &rng),
                                    radiusX: .random(in: 0...Double(w), using: &rng),
                                    radiusY: .random(in: 0...Double(h), using: &rng))
        let dx = Int.random(in: -(w + 1)...(w + 1), using: &rng)
        let dy = Int.random(in: -(h + 1)...(h + 1), using: &rng)
        let out = try input.cloned(offset: (dx: dx, dy: dy), through: mask)
        for y in 0..<h {
            for x in 0..<w {
                let c = try mask.coverage(x: x, y: y)
                let offBuffer = !(0..<w).contains(x + dx) || !(0..<h).contains(y + dy)
                let got = try out.pixel(x: x, y: y)
                if offBuffer || c == 0 {
                    #expect(got == (try input.pixel(x: x, y: y)), "(\(x), \(y)) offset (\(dx), \(dy))")
                } else if c == 1 {
                    #expect(got == (try input.pixel(x: x + dx, y: y + dy)), "(\(x), \(y)) offset (\(dx), \(dy))")
                }
            }
        }
    }
}

@Test func cloneMixesHugeFiniteComponentsWithoutThrowing() throws {
    let big = Float.greatestFiniteMagnitude
    let input = try PixelBuffer(width: 2, height: 1, fill: RGBA(r: big, g: -big, b: big, a: big))
    for i in 1..<1000 {
        let mask = try Mask(width: 2, height: 1, fill: Float(i) / 1000)
        #expect(throws: Never.self) { try input.cloned(offset: (dx: 1, dy: 0), through: mask) }
    }
}
