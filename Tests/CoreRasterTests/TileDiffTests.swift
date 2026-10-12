// TileDiffTests.swift: tile-by-tile undo for raster edits. Counts of kept tiles
// for one pixel, a square straddling four tiles and no change; a seeded property
// test that undo and redo restore exact bits and that the kept tiles are the
// ones the edits overlap, clipped edge tiles included; signed zero; and size
// mismatches throwing without touching the buffer.
import CoreRaster
import Testing

/// True when both buffers have the same size and every component's bits match.
private func bitIdentical(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Bool {
    guard a.width == b.width, a.height == b.height else { return false }
    for y in 0..<a.height {
        for x in 0..<a.width {
            let p = try a.pixel(x: x, y: y)
            let q = try b.pixel(x: x, y: y)
            let same = [p.r, p.g, p.b, p.a].map(\.bitPattern) == [q.r, q.g, q.b, q.a].map(\.bitPattern)
            if !same { return false }
        }
    }
    return true
}

@Test func keepsOnlyTheTilesAnEditTouches() throws {
    let before = try PixelBuffer(width: 1024, height: 1024)
    let red = RGBA(r: 1, g: 0, b: 0, a: 1)
    #expect(try TileDiff(before: before, after: before).tileCount == 0)

    var onePixel = before
    try onePixel.setPixel(x: 700, y: 300, red)
    #expect(try TileDiff(before: before, after: onePixel).tileCount == 1)

    var square = before
    for (x, y) in [(255, 255), (256, 255), (255, 256), (256, 256)] { try square.setPixel(x: x, y: y, red) }
    #expect(try TileDiff(before: before, after: square).tileCount == 4)
}

@Test func undoAndRedoRestoreExactBitsAndKeepTheOverlappedTiles() throws {
    var rng = SplitMix64(seed: 156)
    var sizes = [(300, 270), (257, 513)]
    for _ in 0..<6 {
        sizes.append((Int.random(in: 1...700, using: &rng), Int.random(in: 1...700, using: &rng)))
    }
    for (w, h) in sizes {
        let before = try randomBuffer(width: w, height: h, &rng)
        var after = before
        var touched = Set<[Int]>()
        for _ in 0..<Int.random(in: 1...5, using: &rng) {
            let x0 = Int.random(in: 0..<w, using: &rng), y0 = Int.random(in: 0..<h, using: &rng)
            let x1 = Int.random(in: x0..<w, using: &rng), y1 = Int.random(in: y0..<h, using: &rng)
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

@Test func signedZeroCountsAsAChangeAndUndoesExactly() throws {
    let before = try PixelBuffer(width: 600, height: 300)
    var after = before
    try after.setPixel(x: 599, y: 299, RGBA(r: -0.0, g: 0, b: 0, a: 0))
    let diff = try TileDiff(before: before, after: after)
    #expect(diff.tileCount == 1)
    var buffer = after
    try diff.undo(&buffer)
    #expect(try buffer.pixel(x: 599, y: 299).r.bitPattern == Float(0).bitPattern)
    try diff.redo(&buffer)
    #expect(try buffer.pixel(x: 599, y: 299).r.bitPattern == Float(-0.0).bitPattern)
}

@Test func mismatchedSizesThrowAndLeaveTheBufferUnchanged() throws {
    let small = try PixelBuffer(width: 300, height: 300)
    let wide = try PixelBuffer(width: 301, height: 300)
    #expect(throws: RasterError.self) { try TileDiff(before: small, after: wide) }
    #expect(throws: RasterError.self) { try TileDiff(before: wide, after: small) }

    var after = small
    try after.setPixel(x: 0, y: 0, RGBA(r: 1, g: 1, b: 1, a: 1))
    let diff = try TileDiff(before: small, after: after)
    var other = wide
    #expect(throws: RasterError.self) { try diff.undo(&other) }
    #expect(throws: RasterError.self) { try diff.redo(&other) }
    #expect(other == wide)
}
