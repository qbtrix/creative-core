// TilesAdversarialTests.swift: tile-grid edge cases beyond the acceptance test.
// Sizes either side of every tile boundary, extreme aspect ratios, a seeded
// fuzz of arbitrary (including Int.min/Int.max) indexes and mismatched
// replacement sizes, that the tile rects partition the buffer exactly, that a
// replacement touches only its own tile, and that tiles are independent copies.
import CoreRaster
import Testing

/// A buffer whose every pixel encodes its own coordinate, so any misplaced
/// copy shows up as a wrong value.
private func coordinateBuffer(width: Int, height: Int) throws -> PixelBuffer {
    var buffer = try PixelBuffer(width: width, height: height)
    for y in 0..<height {
        for x in 0..<width {
            try buffer.setPixel(x: x, y: y, RGBA(r: Float(x), g: Float(y), b: Float(x &+ y), a: 1))
        }
    }
    return buffer
}

@Test func gridCountsAroundEveryTileBoundary() throws {
    let cases: [(size: Int, tiles: Int, last: Int)] = [
        (1, 1, 1), (2, 1, 2), (255, 1, 255), (256, 1, 256), (257, 2, 1),
        (511, 2, 255), (512, 2, 256), (513, 3, 1), (768, 3, 256), (769, 4, 1),
    ]
    for c in cases {
        let wide = try PixelBuffer(width: c.size, height: 1)
        #expect(wide.tileColumns == c.tiles && wide.tileRows == 1, "width \(c.size)")
        let lastColumn = try wide.tileRect(column: c.tiles - 1, row: 0)
        #expect(lastColumn == TileRect(x: (c.tiles - 1) * 256, y: 0, width: c.last, height: 1), "width \(c.size)")

        let tall = try PixelBuffer(width: 1, height: c.size)
        #expect(tall.tileColumns == 1 && tall.tileRows == c.tiles, "height \(c.size)")
        let lastRow = try tall.tileRect(column: 0, row: c.tiles - 1)
        #expect(lastRow == TileRect(x: 0, y: (c.tiles - 1) * 256, width: 1, height: c.last), "height \(c.size)")
    }
}

@Test func extremeAspectRatiosClipTheLastTile() throws {
    let wide = try PixelBuffer(width: 1_000_000, height: 1)
    #expect(wide.tileColumns == 3_907 && wide.tileRows == 1)
    #expect(try wide.tileRect(column: 3_906, row: 0) == TileRect(x: 999_936, y: 0, width: 64, height: 1))
    #expect(throws: RasterError.self) { try wide.tileRect(column: 3_907, row: 0) }
    #expect(try wide.tile(column: 3_906, row: 0).width == 64)

    let tall = try PixelBuffer(width: 1, height: 1_000_000)
    #expect(tall.tileColumns == 1 && tall.tileRows == 3_907)
    #expect(try tall.tileRect(column: 0, row: 3_906) == TileRect(x: 0, y: 999_936, width: 1, height: 64))
    #expect(throws: RasterError.self) { try tall.tileRect(column: 0, row: 3_907) }
}

@Test func tileRectsPartitionTheBufferExactly() throws {
    var rng = SplitMix64(seed: 0x155A)
    for _ in 0..<40 {
        let w = Int.random(in: 1...1_300, using: &rng)
        let h = Int.random(in: 1...1_300, using: &rng)
        let buffer = try PixelBuffer(width: w, height: h)
        var area = 0
        for row in 0..<buffer.tileRows {
            for column in 0..<buffer.tileColumns {
                let rect = try buffer.tileRect(column: column, row: row)
                #expect(rect.x == column * 256 && rect.y == row * 256)
                #expect((1...256).contains(rect.width) && (1...256).contains(rect.height))
                #expect(rect.x + rect.width <= w && rect.y + rect.height <= h)
                // Only the last column and row may be short.
                #expect(rect.width == 256 || column == buffer.tileColumns - 1)
                #expect(rect.height == 256 || row == buffer.tileRows - 1)
                area += rect.width * rect.height
            }
        }
        #expect(area == w * h, "\(w)x\(h)")
    }
}

@Test func fuzzedIndexesEitherThrowOrStayInsideTheBuffer() throws {
    var rng = SplitMix64(seed: 0x155B)
    let specials = [Int.min, Int.min + 1, -257, -256, -2, -1, 0, 1, 2, 3, 255, 256, Int.max - 1, Int.max]
    for _ in 0..<30 {
        let w = Int.random(in: 1...900, using: &rng)
        let h = Int.random(in: 1...900, using: &rng)
        var buffer = try PixelBuffer(width: w, height: h, fill: RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1))
        let before = buffer
        let replacement = try PixelBuffer(width: 1, height: 1)
        for _ in 0..<40 {
            let column = Bool.random(using: &rng) ? specials.randomElement(using: &rng) ?? 0 : Int.random(in: -5...8, using: &rng)
            let row = Bool.random(using: &rng) ? specials.randomElement(using: &rng) ?? 0 : Int.random(in: -5...8, using: &rng)
            let inGrid = (0..<buffer.tileColumns).contains(column) && (0..<buffer.tileRows).contains(row)
            if inGrid {
                let rect = try buffer.tileRect(column: column, row: row)
                #expect(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= w && rect.y + rect.height <= h)
                let tile = try buffer.tile(column: column, row: row)
                #expect(tile.width == rect.width && tile.height == rect.height)
            } else {
                #expect(throws: RasterError.self) { try buffer.tileRect(column: column, row: row) }
                #expect(throws: RasterError.self) { try buffer.tile(column: column, row: row) }
                #expect(throws: RasterError.self) { try buffer.replaceTile(column: column, row: row, with: replacement) }
            }
        }
        #expect(buffer == before, "\(w)x\(h)")
    }
}

@Test func fuzzedMismatchedReplacementsThrowAndChangeNothing() throws {
    var rng = SplitMix64(seed: 0x155C)
    var buffer = try coordinateBuffer(width: 600, height: 300)
    let before = buffer
    for _ in 0..<200 {
        let column = Int.random(in: 0..<buffer.tileColumns, using: &rng)
        let row = Int.random(in: 0..<buffer.tileRows, using: &rng)
        let rect = try buffer.tileRect(column: column, row: row)
        let w = Int.random(in: 1...300, using: &rng)
        let h = Int.random(in: 1...300, using: &rng)
        guard w != rect.width || h != rect.height else { continue }
        let replacement = try PixelBuffer(width: w, height: h, fill: RGBA(r: 9, g: 9, b: 9, a: 1))
        #expect(throws: RasterError.self) { try buffer.replaceTile(column: column, row: row, with: replacement) }
    }
    // Transposed edge tile: 44x88 for an 88x44 slot.
    let transposed = try PixelBuffer(width: 44, height: 88)
    #expect(throws: RasterError.self) { try buffer.replaceTile(column: 2, row: 1, with: transposed) }
    #expect(buffer == before)
}

@Test func replacingOneTileChangesOnlyThatTile() throws {
    let before = try coordinateBuffer(width: 600, height: 300)
    let marker = RGBA(r: -1, g: -1, b: -1, a: 0.5)
    for row in 0..<before.tileRows {
        for column in 0..<before.tileColumns {
            var target = before
            let rect = try target.tileRect(column: column, row: row)
            let patch = try PixelBuffer(width: rect.width, height: rect.height, fill: marker)
            try target.replaceTile(column: column, row: row, with: patch)
            for y in stride(from: 0, to: 300, by: 7) {
                for x in stride(from: 0, to: 600, by: 7) {
                    let inside = x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
                    let expected = inside ? marker : try before.pixel(x: x, y: y)
                    #expect(try target.pixel(x: x, y: y) == expected, "tile (\(column), \(row)) at (\(x), \(y))")
                }
            }
            // The four corners of the rect are the edges most likely to be off by one.
            for (x, y) in [(rect.x, rect.y), (rect.x + rect.width - 1, rect.y),
                           (rect.x, rect.y + rect.height - 1), (rect.x + rect.width - 1, rect.y + rect.height - 1)] {
                #expect(try target.pixel(x: x, y: y) == marker)
            }
        }
    }
}

@Test func tilesAreIndependentCopies() throws {
    let source = try coordinateBuffer(width: 300, height: 300)
    var tile = try source.tile(column: 1, row: 1)
    #expect(try tile.pixel(x: 0, y: 0) == RGBA(r: 256, g: 256, b: 512, a: 1))
    try tile.setPixel(x: 0, y: 0, .clear)
    #expect(try source.pixel(x: 256, y: 256) == RGBA(r: 256, g: 256, b: 512, a: 1))

    // Writing into a copy leaves the original alone.
    let original = source
    var copy = source
    try copy.replaceTile(column: 1, row: 1, with: tile)
    #expect(try copy.pixel(x: 256, y: 256) == .clear)
    #expect(original == source)
    #expect(try original.pixel(x: 256, y: 256) == RGBA(r: 256, g: 256, b: 512, a: 1))
}

@Test func aTileFromOneBufferFitsAMatchingSlotInAnother() throws {
    // 300x300 tile (1, 1) and 812x300 tile (3, 1) are both 44x44 edge tiles.
    let a = try coordinateBuffer(width: 300, height: 300)
    var b = try PixelBuffer(width: 812, height: 300)
    let tile = try a.tile(column: 1, row: 1)
    #expect(try b.tileRect(column: 3, row: 1) == TileRect(x: 768, y: 256, width: 44, height: 44))
    try b.replaceTile(column: 3, row: 1, with: tile)
    #expect(try b.pixel(x: 768, y: 256) == a.pixel(x: 256, y: 256))
    #expect(try b.pixel(x: 811, y: 299) == a.pixel(x: 299, y: 299))
    #expect(try b.tile(column: 3, row: 1) == tile)
}
