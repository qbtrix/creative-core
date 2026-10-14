// RetouchBoundsTests.swift: clone limited to the mask's covered bounds
// (issue #257). `Mask.coveredBounds` is the tight rectangle of coverage above
// 0; `cloned(offset:through:)` gives exactly what the full per-pixel pass gave
// for every mask and offset; and a small dab costs far less than a full mask
// on the same buffer.
import CoreRaster
import Testing

/// The clone as it was before #257: every pixel through the throwing
/// accessors, coverage 0 included. The reference the bounded clone must match.
private func fullPassClone(_ input: PixelBuffer, dx: Int, dy: Int, mask: Mask) throws -> PixelBuffer {
    var result = input
    for y in 0..<input.height {
        for x in 0..<input.width {
            guard (0..<input.width).contains(x + dx), (0..<input.height).contains(y + dy) else { continue }
            let c = try mask.coverage(x: x, y: y)
            let s = try input.pixel(x: x + dx, y: y + dy)
            let b = try input.pixel(x: x, y: y)
            let keep = 1 - c
            try result.setPixel(x: x, y: y, RGBA(r: s.r * c + b.r * keep, g: s.g * c + b.g * keep,
                                                 b: s.b * c + b.b * keep, a: s.a * c + b.a * keep))
        }
    }
    return result
}

@Test func coveredBoundsIsTheTightRectangleOfCoverage() throws {
    #expect(try Mask(width: 6, height: 4).coveredBounds == nil)
    #expect(try Mask(width: 6, height: 4, fill: 1).coveredBounds == TileRect(x: 0, y: 0, width: 6, height: 4))
    let rect = try Mask.rectangle(width: 10, height: 8, x: 2, y: 3, w: 4, h: 2)
    #expect(rect.coveredBounds == TileRect(x: 2, y: 3, width: 4, height: 2))
    // A shape off the top-left corner is clipped to the mask.
    let corner = try Mask.rectangle(width: 10, height: 8, x: -5, y: -5, w: 6, h: 6)
    #expect(corner.coveredBounds == TileRect(x: 0, y: 0, width: 1, height: 1))
    // One soft pixel at the bottom-right corner still counts.
    let soft = try Mask.rectangle(width: 10, height: 8, x: 9.75, y: 7.75, w: 1, h: 1)
    #expect(soft.coveredBounds == TileRect(x: 9, y: 7, width: 1, height: 1))
    // Two separate spots: the bounds span both.
    var spots = try Mask.rectangle(width: 10, height: 8, x: 1, y: 6, w: 1, h: 1)
    try spots.add(Mask.rectangle(width: 10, height: 8, x: 7, y: 2, w: 2, h: 1))
    #expect(spots.coveredBounds == TileRect(x: 1, y: 2, width: 8, height: 5))
}

@Test func boundedCloneMatchesTheFullPassForEveryMaskAndOffset() throws {
    var rng = SplitMix64(seed: 257)
    for round in 0..<300 {
        let w = Int.random(in: 1...24, using: &rng)
        let h = Int.random(in: 1...24, using: &rng)
        var input = try PixelBuffer(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w { try input.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
        }
        var mask: Mask
        switch round % 5 {
        case 0: mask = try Mask(width: w, height: h)
        case 1: mask = try Mask(width: w, height: h, fill: 1)
        case 2:
            // Soft-edged rectangles that often hang off an edge.
            mask = try Mask.rectangle(width: w, height: h,
                                      x: .random(in: -4...Double(w), using: &rng),
                                      y: .random(in: -4...Double(h), using: &rng),
                                      w: .random(in: 0...Double(w), using: &rng),
                                      h: .random(in: 0...Double(h), using: &rng))
        default:
            mask = try Mask.ellipse(width: w, height: h,
                                    centerX: .random(in: -3...Double(w + 3), using: &rng),
                                    centerY: .random(in: -3...Double(h + 3), using: &rng),
                                    radiusX: .random(in: 0...Double(w), using: &rng),
                                    radiusY: .random(in: 0...Double(h), using: &rng))
            if round % 5 == 4 { mask.invert() }
        }
        let dx = Int.random(in: -(w + 1)...(w + 1), using: &rng)
        let dy = Int.random(in: -(h + 1)...(h + 1), using: &rng)
        let got = try input.cloned(offset: (dx: dx, dy: dy), through: mask)
        let expected = try fullPassClone(input, dx: dx, dy: dy, mask: mask)
        #expect(got == expected, "round \(round): \(w)x\(h), offset (\(dx), \(dy))")
    }
}

@Test func aSmallDabCostsFarLessThanAFullMask() throws {
    let size = 2048
    let buffer = try PixelBuffer(width: size, height: size, fill: RGBA(r: 0.2, g: 0.2, b: 0.2, a: 1))
    let dab = try Mask.ellipse(width: size, height: size, centerX: 1024, centerY: 1024, radiusX: 8, radiusY: 8)
    let full = try Mask(width: size, height: size, fill: 0.5)
    let clock = ContinuousClock()
    func fastest(_ mask: Mask) throws -> Duration {
        var best = Duration.seconds(1_000)
        for _ in 0..<3 {
            best = min(best, try clock.measure { _ = try buffer.cloned(offset: (dx: 300, dy: 0), through: mask) })
        }
        return best
    }
    let dabTime = try fastest(dab)
    let fullTime = try fastest(full)
    print("clone on \(size)x\(size): 16 px dab \(dabTime), full mask \(fullTime)")
    // The dab pays for the buffer copy and one read of the mask; the full
    // mask also mixes every pixel. Before #257 they cost the same.
    #expect(dabTime * 2 < fullTime)
}
