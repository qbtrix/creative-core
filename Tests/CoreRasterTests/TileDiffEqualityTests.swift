// TileDiffEqualityTests.swift: adversarial tests for TileDiff `==` (#165).
// Equal diffs must undo and redo to the same bytes on any buffer; diffs that
// differ in size, kept tiles or any component bit must compare unequal.
import CoreRaster
import Testing

/// True when both buffers have one size and every component matches bit for bit.
private func sameBytes(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Bool {
    guard a.width == b.width, a.height == b.height else { return false }
    for y in 0..<a.height {
        for x in 0..<a.width {
            let p = try a.pixel(x: x, y: y), q = try b.pixel(x: x, y: y)
            guard p.r.bitPattern == q.r.bitPattern, p.g.bitPattern == q.g.bitPattern,
                  p.b.bitPattern == q.b.bitPattern, p.a.bitPattern == q.a.bitPattern else { return false }
        }
    }
    return true
}

/// Values that compare equal or nearly so under Float `==` but differ in bits,
/// plus the extremes a buffer may legally hold.
private let trickyValues: [Float] = [
    0, -0.0, .leastNonzeroMagnitude, -.leastNonzeroMagnitude, .leastNormalMagnitude,
    .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1, Float(1).nextUp,
]

private func trickyPixel(_ rng: inout SplitMix64) -> RGBA {
    func v() -> Float { trickyValues[Int.random(in: 0..<trickyValues.count, using: &rng)] }
    return RGBA(r: v(), g: v(), b: v(), a: v())
}

@Test func negativeZeroInEveryChannelAndEdgeTileMakesDiffsUnequal() throws {
    // 300x300 has a partial last column and row of tiles; hit the far corner.
    let zero = try PixelBuffer(width: 300, height: 300)
    for channel in 0..<4 {
        var c: [Float] = [0, 0, 0, 0]
        c[channel] = -0.0
        var negative = zero
        try negative.setPixel(x: 299, y: 299, RGBA(r: c[0], g: c[1], b: c[2], a: c[3]))
        #expect(negative == zero)  // PixelBuffer == is left as Float ==
        let forward = try TileDiff(before: zero, after: negative)
        let backward = try TileDiff(before: negative, after: zero)
        #expect(forward.tileCount == 1)
        #expect(forward != backward)
        #expect(backward != forward)
    }
}

@Test func diffsOfDifferentSizesAreUnequalEvenWhenEmpty() throws {
    let a = try PixelBuffer(width: 4, height: 4)
    let b = try PixelBuffer(width: 4, height: 5)
    let c = try PixelBuffer(width: 5, height: 4)
    let da = try TileDiff(before: a, after: a)
    let db = try TileDiff(before: b, after: b)
    let dc = try TileDiff(before: c, after: c)
    #expect(da.tileCount == 0)
    #expect(da != db && da != dc && db != dc)
    #expect(da == (try TileDiff(before: a, after: a)))
}

@Test func sameEditInDifferentTilesIsUnequal() throws {
    let base = try PixelBuffer(width: 512, height: 512)
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)
    var left = base, right = base
    try left.setPixel(x: 0, y: 0, red)
    try right.setPixel(x: 256, y: 0, red)
    #expect(try TileDiff(before: base, after: left) != TileDiff(before: base, after: right))
}

@Test func subnormalAndExtremeValuesCompareByBits() throws {
    let base = try PixelBuffer(width: 2, height: 2)
    for (i, x) in trickyValues.enumerated() {
        for y in trickyValues[(i + 1)...] where x.bitPattern != y.bitPattern {
            var bx = base, by = base
            try bx.setPixel(x: 1, y: 1, RGBA(r: x, g: 0, b: 0, a: 0))
            try by.setPixel(x: 1, y: 1, RGBA(r: y, g: 0, b: 0, a: 0))
            #expect(try TileDiff(before: base, after: bx) != TileDiff(before: base, after: by))
            #expect(try TileDiff(before: bx, after: base) != TileDiff(before: by, after: base))
        }
    }
}

/// Fuzz: over buffers built from bit-tricky values, `==` is reflexive and
/// symmetric, and equal diffs always undo and redo any base to the same bytes.
@Test func fuzzEqualDiffsUndoAndRedoToTheSameBytes() throws {
    var rng = SplitMix64(seed: 0x165E)
    for _ in 0..<200 {
        let w = Int.random(in: 1...3, using: &rng), h = Int.random(in: 1...3, using: &rng)
        func buffer() throws -> PixelBuffer {
            var b = try PixelBuffer(width: w, height: h)
            for _ in 0..<Int.random(in: 0...2, using: &rng) {
                try b.setPixel(x: Int.random(in: 0..<w, using: &rng),
                               y: Int.random(in: 0..<h, using: &rng), trickyPixel(&rng))
            }
            return b
        }
        let p = try TileDiff(before: buffer(), after: buffer())
        let q = try TileDiff(before: buffer(), after: buffer())
        #expect(p == p)
        #expect((p == q) == (q == p))
        guard p == q else { continue }
        var base1 = try buffer()
        var base2 = base1
        try p.undo(&base1)
        try q.undo(&base2)
        #expect(try sameBytes(base1, base2))
        try p.redo(&base1)
        try q.redo(&base2)
        #expect(try sameBytes(base1, base2))
    }
}

@Test func largeBufferDiffEqualityIsExactAcrossManyTiles() throws {
    // 1025x1025 is a 5x5 tile grid with one-pixel last column and row.
    let base = try PixelBuffer(width: 1025, height: 1025, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
    var edited = base
    for t in 0..<5 { try edited.setPixel(x: t * 256, y: 1024, RGBA(r: 1, g: 0, b: 0, a: 1)) }
    var flipped = edited
    try flipped.setPixel(x: 1024, y: 1024, RGBA(r: 1, g: -0.0, b: 0, a: 1))
    let d1 = try TileDiff(before: base, after: edited)
    #expect(d1.tileCount == 5)
    #expect(d1 == (try TileDiff(before: base, after: edited)))
    #expect(d1 != (try TileDiff(before: base, after: flipped)))
}
