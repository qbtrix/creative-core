// TilesTests.swift: the PixelBuffer tile grid. Grid counts and clipped edge
// rects, a seeded read-every-tile/write-every-tile round trip, and rejection
// of out-of-range indexes and mismatched replacements without changing the
// buffer, and the static grid math (`tileCount(covering:)`, `tileRect`) that
// CoreRender's SurfaceTiling shares.
import CoreRaster
import Testing

private func randomBuffer(width: Int, height: Int, _ rng: inout SplitMix64) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng)) }
    }
    return buffer
}

@Test func gridCountsRoundUpAndEdgeTilesAreClipped() throws {
    #expect(PixelBuffer.tileSize == 256)
    let buffer = try PixelBuffer(width: 600, height: 300)
    #expect(buffer.tileColumns == 3 && buffer.tileRows == 2)
    #expect(try buffer.tileRect(column: 0, row: 0) == TileRect(x: 0, y: 0, width: 256, height: 256))
    #expect(try buffer.tileRect(column: 1, row: 0) == TileRect(x: 256, y: 0, width: 256, height: 256))
    #expect(try buffer.tileRect(column: 2, row: 1) == TileRect(x: 512, y: 256, width: 88, height: 44))
    let edge = try buffer.tile(column: 2, row: 1)
    #expect(edge.width == 88 && edge.height == 44)

    let exact = try PixelBuffer(width: 512, height: 256)
    #expect(exact.tileColumns == 2 && exact.tileRows == 1)
    #expect(try exact.tileRect(column: 1, row: 0) == TileRect(x: 256, y: 0, width: 256, height: 256))

    let single = try PixelBuffer(width: 1, height: 1)
    #expect(single.tileColumns == 1 && single.tileRows == 1)
    #expect(try single.tileRect(column: 0, row: 0) == TileRect(x: 0, y: 0, width: 1, height: 1))
    let justOver = try PixelBuffer(width: 257, height: 1)
    #expect(justOver.tileColumns == 2)
    #expect(try justOver.tileRect(column: 1, row: 0) == TileRect(x: 256, y: 0, width: 1, height: 1))
}

@Test func tileHoldsTheSourcePixels() throws {
    var rng = SplitMix64(seed: 155)
    let buffer = try randomBuffer(width: 300, height: 270, &rng)
    let tile = try buffer.tile(column: 1, row: 1)
    #expect(tile.width == 44 && tile.height == 14)
    for (x, y) in [(0, 0), (43, 0), (0, 13), (43, 13), (17, 5)] {
        #expect(try tile.pixel(x: x, y: y) == buffer.pixel(x: 256 + x, y: 256 + y))
    }
}

@Test func readingEveryTileAndWritingItIntoAClearedBufferRebuildsTheOriginal() throws {
    var rng = SplitMix64(seed: 1_550)
    var sizes = [(1, 1), (256, 256), (257, 513)]
    for _ in 0..<6 {
        sizes.append((Int.random(in: 1...700, using: &rng), Int.random(in: 1...700, using: &rng)))
    }
    for (w, h) in sizes {
        var original = try randomBuffer(width: w, height: h, &rng)
        var rebuilt = try PixelBuffer(width: w, height: h)
        let before = original
        for row in 0..<original.tileRows {
            for column in 0..<original.tileColumns {
                let tile = try original.tile(column: column, row: row)
                try rebuilt.replaceTile(column: column, row: row, with: tile)
                try original.replaceTile(column: column, row: row, with: tile)
            }
        }
        #expect(rebuilt == before, "rebuilt \(w)x\(h)")
        #expect(original == before, "read and wrote back \(w)x\(h)")
    }
}

@Test func outOfRangeIndexesAndMismatchedReplacementsThrowAndChangeNothing() throws {
    var rng = SplitMix64(seed: 15_500)
    var buffer = try randomBuffer(width: 600, height: 300, &rng)
    let before = buffer
    let full = try PixelBuffer(width: 256, height: 256, fill: RGBA(r: 1, g: 1, b: 1, a: 1))
    let bad = [(-1, 0), (0, -1), (buffer.tileColumns, 0), (0, buffer.tileRows), (Int.min, Int.max)]
    for (column, row) in bad {
        #expect(throws: RasterError.self) { try buffer.tileRect(column: column, row: row) }
        #expect(throws: RasterError.self) { try buffer.tile(column: column, row: row) }
        #expect(throws: RasterError.self) { try buffer.replaceTile(column: column, row: row, with: full) }
    }
    #expect(throws: RasterError.self) { try buffer.replaceTile(column: 2, row: 1, with: full) }
    let tall = try PixelBuffer(width: 88, height: 45)
    #expect(throws: RasterError.self) { try buffer.replaceTile(column: 2, row: 1, with: tall) }
    #expect(buffer == before)
}

@Test func staticTileCountRoundsUpAndNeverOverflows() throws {
    #expect(PixelBuffer.tileCount(covering: 0) == 0)
    #expect(PixelBuffer.tileCount(covering: -5) == 0)
    #expect(PixelBuffer.tileCount(covering: 1) == 1)
    #expect(PixelBuffer.tileCount(covering: 256) == 1)
    #expect(PixelBuffer.tileCount(covering: 257) == 2)
    #expect(PixelBuffer.tileCount(covering: Int.max) == (Int.max - 1) / 256 + 1)
    #expect(try PixelBuffer.tileRect(column: 2, row: 1, width: 600, height: 300) == TileRect(x: 512, y: 256, width: 88, height: 44))
    #expect(throws: RasterError.invalid("tile (3, 0) is outside the 3x2 tile grid")) {
        try PixelBuffer.tileRect(column: 3, row: 0, width: 600, height: 300)
    }
}
