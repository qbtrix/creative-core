// TileDiffTests.swift: tile-by-tile undo. Exact tile counts for one pixel, a
// square across four tiles and no change; a seeded property test that undo and
// redo restore bit-identical buffers and keep exactly the overlapped tiles; a
// 0.0 to -0.0 edit; size mismatches that throw and change nothing; and `==`,
// which tells apart diffs that undo to different bytes.
import CoreRaster
import Testing

/// True when every component of `a` and `b` has the same bit pattern.
private func bitIdentical(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Bool {
    guard a.width == b.width, a.height == b.height else { return false }
    for y in 0..<a.height {
        for x in 0..<a.width {
            let p = try a.pixel(x: x, y: y)
            let q = try b.pixel(x: x, y: y)
            let same = p.r.bitPattern == q.r.bitPattern && p.g.bitPattern == q.g.bitPattern
                && p.b.bitPattern == q.b.bitPattern && p.a.bitPattern == q.a.bitPattern
            if !same { return false }
        }
    }
    return true
}

@Test func keepsOnlyTheTilesAnEditTouches() throws {
    let before = try PixelBuffer(width: 1024, height: 1024)
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)

    var onePixel = before
    try onePixel.setPixel(x: 700, y: 30, red)
    #expect(try TileDiff(before: before, after: onePixel).tileCount == 1)

    var square = before
    for (x, y) in [(255, 255), (256, 255), (255, 256), (256, 256)] { try square.setPixel(x: x, y: y, red) }
    let diff = try TileDiff(before: before, after: square)
    #expect(diff.tileCount == 4)
    var buffer = square
    try diff.undo(&buffer)
    #expect(try buffer.pixel(x: 256, y: 256) == .clear)
    #expect(buffer == before)

    #expect(try TileDiff(before: before, after: before).tileCount == 0)
}

@Test func undoAndRedoRestoreRandomEditsBitForBit() throws {
    var rng = SplitMix64(seed: 156)
    for _ in 0..<12 {
        let w = Int.random(in: 1...700, using: &rng)
        let h = Int.random(in: 1...700, using: &rng)
        let before = try PixelBuffer(width: w, height: h, fill: randomPixel(&rng))
        var after = before
        var touched = Set<[Int]>()
        for _ in 0..<Int.random(in: 1...5, using: &rng) {
            let x0 = Int.random(in: 0..<w, using: &rng), y0 = Int.random(in: 0..<h, using: &rng)
            let x1 = Int.random(in: x0..<min(w, x0 + 40), using: &rng)
            let y1 = Int.random(in: y0..<min(h, y0 + 40), using: &rng)
            for y in y0...y1 {
                for x in x0...x1 { try after.setPixel(x: x, y: y, randomPixel(&rng)) }
            }
            for row in (y0 / PixelBuffer.tileSize)...(y1 / PixelBuffer.tileSize) {
                for column in (x0 / PixelBuffer.tileSize)...(x1 / PixelBuffer.tileSize) { touched.insert([column, row]) }
            }
        }
        let diff = try TileDiff(before: before, after: after)
        #expect(diff.tileCount == touched.count, "\(w)x\(h)")
        var buffer = after
        try diff.undo(&buffer)
        #expect(try bitIdentical(buffer, before), "undo \(w)x\(h)")
        try diff.redo(&buffer)
        #expect(try bitIdentical(buffer, after), "redo \(w)x\(h)")
    }
}

@Test func negativeZeroIsKeptAndUndoneExactly() throws {
    let before = try PixelBuffer(width: 300, height: 300)
    var after = before
    try after.setPixel(x: 299, y: 299, RGBA(r: -0.0, g: 0, b: 0, a: 0))
    #expect(after == before)  // == can't see the change; the diff must.
    let diff = try TileDiff(before: before, after: after)
    #expect(diff.tileCount == 1)
    var buffer = after
    try diff.undo(&buffer)
    #expect(try buffer.pixel(x: 299, y: 299).r.bitPattern == Float(0).bitPattern)
    #expect(try bitIdentical(buffer, before))
    try diff.redo(&buffer)
    #expect(try buffer.pixel(x: 299, y: 299).r.bitPattern == Float(-0.0).bitPattern)
}

@Test func mismatchedSizesThrowAndChangeNothing() throws {
    let small = try PixelBuffer(width: 300, height: 200)
    let wide = try PixelBuffer(width: 301, height: 200)
    let tall = try PixelBuffer(width: 300, height: 201)
    #expect(throws: RasterError.self) { try TileDiff(before: small, after: wide) }
    #expect(throws: RasterError.self) { try TileDiff(before: tall, after: small) }

    var edited = small
    try edited.setPixel(x: 0, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
    let diff = try TileDiff(before: small, after: edited)
    var other = try PixelBuffer(width: 301, height: 200, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
    let original = other
    #expect(throws: RasterError.self) { try diff.undo(&other) }
    #expect(throws: RasterError.self) { try diff.redo(&other) }
    #expect(try bitIdentical(other, original))
}

@Test func inverseNegativeZeroDiffsAreNotEqual() throws {
    let zero = try PixelBuffer(width: 4, height: 4)
    var negative = zero
    try negative.setPixel(x: 0, y: 0, RGBA(r: -0.0, g: 0, b: 0, a: 0))
    let forward = try TileDiff(before: zero, after: negative)
    let backward = try TileDiff(before: negative, after: zero)

    var a = negative
    try forward.undo(&a)
    var b = negative
    try backward.undo(&b)
    #expect(try a.pixel(x: 0, y: 0).r.bitPattern == 0)
    #expect(try b.pixel(x: 0, y: 0).r.bitPattern == 0x8000_0000)
    #expect(forward != backward)
    #expect(forward == forward)
}

@Test func diffsOfTheSameBuffersAreEqual() throws {
    var rng = SplitMix64(seed: 165)
    for _ in 0..<12 {
        let w = Int.random(in: 1...600, using: &rng)
        let h = Int.random(in: 1...600, using: &rng)
        let before = try PixelBuffer(width: w, height: h, fill: randomPixel(&rng))
        var after = before
        for _ in 0..<Int.random(in: 1...20, using: &rng) {
            let x = Int.random(in: 0..<w, using: &rng), y = Int.random(in: 0..<h, using: &rng)
            try after.setPixel(x: x, y: y, randomPixel(&rng))
        }
        let diff = try TileDiff(before: before, after: after)
        #expect(diff == (try TileDiff(before: before, after: after)))
        if diff.tileCount > 0 { #expect(diff != (try TileDiff(before: after, after: before))) }
    }
}
