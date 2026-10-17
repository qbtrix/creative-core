// SurfaceTilingTests.swift: the 256 px tile grid over a Metal surface. Exact
// counts and rects for 4K and for one pixel past a full column, the clipped
// last tile, `tiles(touching:)` for spanning, corner, outside, empty and
// extreme rects, the thrown errors, and two seeded property tests: every pixel
// is in exactly one tile, and `tiles(touching:)` matches a brute-force overlap;
// and a seeded check that the grid equals a PixelBuffer's of the same size.
import CoreRaster
import CoreRender
import Testing

/// SplitMix64: tiny, fast, seedable. Same seed, same sequence, on every platform.
/// A private copy: test targets cannot share files.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct SurfaceTilingTests {
    @Test func fourKIsSixteenByNineTiles() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(SurfaceTiling.tileSize == 256)
        // 4096 is exactly 16 x 256. The packet's acceptance row says "17 x 9":
        // a 17th column would start at x = 4096 and be 0 px wide, which is the
        // very off-by-one the grid must never have. 2160 = 8 x 256 + 112 does
        // need a ninth, 112 px row.
        #expect(tiling.columns == 16)
        #expect(tiling.rows == 9)
        #expect(tiling.tileCount == 144)
        #expect(try tiling.rect(0) == TileRect(x: 0, y: 0, width: 256, height: 256))
        #expect(try tiling.rect(16) == TileRect(x: 0, y: 256, width: 256, height: 256))
        #expect(try tiling.rect(143) == TileRect(x: 3840, y: 2048, width: 256, height: 112))
    }

    @Test func onePixelPastAFullColumnAddsAOnePixelColumn() throws {
        let tiling = try SurfaceTiling(width: 4097, height: 1)
        #expect(tiling.columns == 17)
        #expect(tiling.rows == 1)
        #expect(tiling.tileCount == 17)
        #expect(try tiling.rect(16) == TileRect(x: 4096, y: 0, width: 1, height: 1))
        let small = try SurfaceTiling(width: 3, height: 5)
        #expect(small.tileCount == 1)
        #expect(try small.rect(0) == TileRect(x: 0, y: 0, width: 3, height: 5), "a surface under a tile is one clipped tile")
    }

    @Test func tilesTouchingARectSpanningTwoTilesGivesBoth() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(tiling.tiles(touching: 250, y: 10, width: 12, height: 1) == [0, 1])
        #expect(tiling.tiles(touching: 10, y: 255, width: 1, height: 2) == [0, 16])
        #expect(tiling.tiles(touching: 255, y: 255, width: 2, height: 2) == [0, 1, 16, 17])
        #expect(tiling.tiles(touching: 0, y: 0, width: 256, height: 256) == [0], "a rect ending on a tile edge does not touch the next tile")
    }

    @Test func tilesTouchingTheBottomRightCornerGivesOnlyTheLastTile() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(tiling.tiles(touching: 4095, y: 2159, width: 1, height: 1) == [143])
        #expect(tiling.tiles(touching: 4000, y: 2100, width: 500, height: 500) == [143], "a rect past the edge is clipped to the surface")
    }

    @Test func tilesTouchingARectOutsideOrEmptyGivesNothing() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(tiling.tiles(touching: 4096, y: 0, width: 10, height: 10) == [])
        #expect(tiling.tiles(touching: 0, y: 2160, width: 10, height: 10) == [])
        #expect(tiling.tiles(touching: -50, y: 0, width: 50, height: 10) == [], "ends on the pixel before the surface")
        #expect(tiling.tiles(touching: 10, y: 10, width: 0, height: 10) == [])
        #expect(tiling.tiles(touching: 10, y: 10, width: 10, height: -3) == [])
    }

    @Test func tilesTouchingExtremeRectsNeverTraps() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(tiling.tiles(touching: Int.max, y: Int.max, width: Int.max, height: Int.max) == [])
        #expect(tiling.tiles(touching: Int.min, y: Int.min, width: Int.max, height: Int.max) == [], "ends at -2, still left of the surface")
        #expect(tiling.tiles(touching: Int.min, y: 0, width: Int.min, height: 1) == [])
        #expect(tiling.tiles(touching: -1, y: -1, width: Int.max, height: Int.max) == Array(0..<144), "a rect past both ends covers every tile")
        #expect(tiling.tiles(touching: 4095, y: 2159, width: Int.max, height: Int.max) == [143])
        #expect(tiling.tiles(touching: -1, y: 0, width: 2, height: 1) == [0], "one pixel of overlap")
    }

    @Test func rectOutsideTheGridThrows() throws {
        let tiling = try SurfaceTiling(width: 4096, height: 2160)
        #expect(throws: RenderError.raster("tile index 144 out of 0..<144")) { try tiling.rect(144) }
        #expect(throws: RenderError.raster("tile index -1 out of 0..<144")) { try tiling.rect(-1) }
        #expect(throws: RenderError.self) { try tiling.rect(Int.max) }
    }

    @Test func invalidSizesThrowRasterWithTheBoundInTheMessage() {
        #expect(throws: RenderError.raster("size 0x1: width and height must be at least 1")) {
            try SurfaceTiling(width: 0, height: 1)
        }
        // 16385 x 16384 is one row of pixels over 256 megapixels.
        #expect(throws: RenderError.raster("size 16385x16384: more than \(PixelBuffer.maxPixels) pixels")) {
            try SurfaceTiling(width: 16385, height: 16384)
        }
        #expect(throws: RenderError.self) { try SurfaceTiling(width: Int.max, height: 2) }
        #expect(throws: Never.self) { try SurfaceTiling(width: 16384, height: 16384) }
    }

    @Test func seededSizesPutEveryPixelInExactlyOneTile() throws {
        var rng = SplitMix64(seed: 2026)
        for _ in 0..<50 {
            let width = Int.random(in: 1...1500, using: &rng)
            let height = Int.random(in: 1...1500, using: &rng)
            let tiling = try SurfaceTiling(width: width, height: height)
            #expect(tiling.tileCount == tiling.columns * tiling.rows)
            var area = 0
            for index in 0..<tiling.tileCount {
                let rect = try tiling.rect(index)
                #expect(rect.width > 0 && rect.height > 0, "\(width)x\(height) tile \(index) is \(rect)")
                #expect(rect.x >= 0 && rect.y >= 0)
                #expect(rect.x + rect.width <= width && rect.y + rect.height <= height, "\(width)x\(height) tile \(index) is \(rect)")
                area += rect.width * rect.height
            }
            #expect(area == width * height, "\(width)x\(height): tiles cover the surface once")
        }
    }

    @Test func seededSizesLayTheSameGridAsAPixelBuffer() throws {
        var rng = SplitMix64(seed: 348)
        for _ in 0..<20 {
            let width = Int.random(in: 1...700, using: &rng)
            let height = Int.random(in: 1...700, using: &rng)
            let tiling = try SurfaceTiling(width: width, height: height)
            let buffer = try PixelBuffer(width: width, height: height)
            #expect(tiling.columns == buffer.tileColumns && tiling.rows == buffer.tileRows, "\(width)x\(height)")
            for index in 0..<tiling.tileCount {
                let rect = try buffer.tileRect(column: index % tiling.columns, row: index / tiling.columns)
                #expect(try tiling.rect(index) == rect, "\(width)x\(height) tile \(index)")
            }
        }
    }

    @Test func seededRectsMatchBruteForceOverlap() throws {
        var rng = SplitMix64(seed: 77)
        let tiling = try SurfaceTiling(width: 1300, height: 900)
        let rects = try (0..<tiling.tileCount).map { try tiling.rect($0) }
        for _ in 0..<50 {
            let x = Int.random(in: -300...1400, using: &rng)
            let y = Int.random(in: -300...1000, using: &rng)
            let width = Int.random(in: -10...700, using: &rng)
            let height = Int.random(in: -10...700, using: &rng)
            let expected = rects.indices.filter { index in
                let rect = rects[index]
                return width > 0 && height > 0
                    && x < rect.x + rect.width && x + width > rect.x
                    && y < rect.y + rect.height && y + height > rect.y
            }
            #expect(tiling.tiles(touching: x, y: y, width: width, height: height) == expected, "rect (\(x), \(y), \(width)x\(height))")
        }
    }

    @Test func defaultBudgetIsHalfTheWorkingSetButAtLeastOneTile() {
        let tile = SurfaceTiling.tileSize * SurfaceTiling.tileSize * 8
        #expect(tile == 524_288)
        #expect(SurfaceTiling.defaultBudget(workingSet: 0, tileBytes: tile) == tile)
        #expect(SurfaceTiling.defaultBudget(workingSet: 1, tileBytes: tile) == tile)
        #expect(SurfaceTiling.defaultBudget(workingSet: 8_000_000_000, tileBytes: tile) == 4_000_000_000)
        #expect(SurfaceTiling.defaultBudget(workingSet: .max, tileBytes: tile) == Int(UInt64.max / 2))
    }

    @Test func theLastRowIsClippedToTheSurface() throws {
        let tiling = try SurfaceTiling(width: 10, height: 300)
        #expect(tiling.rows == 2)
        #expect(try tiling.rect(1).height == 44)
        #expect(try tiling.rect(0).height == 256)
    }
}
