// TileMapTests.swift: the maps the Metal backend copies by (MB-7) give exactly CoreRaster's `cropped` and
// `rotated` across tiles, writing every pixel once; an invalid crop throws the CPU backend's error, and a
// map refuses pieces for a tiling of another size than its source.
import CoreRaster
import CoreRender
import Testing

@Suite struct TileMapTests {
    /// A buffer whose pixel (x, y) is (x, y, x + y, 1): every pixel distinct, every value finite.
    private static func coordinates(_ width: Int, _ height: Int) throws -> PixelBuffer {
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height { for x in 0..<width { try buffer.setPixel(x: x, y: y, RGBA(r: Float(x), g: Float(y), b: Float(x + y), a: 1)) } }
        return buffer
    }

    /// `map`'s pieces applied to `source` tile by tile, as the GPU does, counting writes per pixel.
    private static func apply(_ map: TileMap, to source: PixelBuffer) throws -> (PixelBuffer, [Int]) {
        let (from, to) = (try SurfaceTiling(width: source.width, height: source.height), try SurfaceTiling(width: map.width, height: map.height))
        var out = try PixelBuffer(width: map.width, height: map.height)
        var writes = [Int](repeating: 0, count: map.width * map.height)
        for piece in try map.pieces(from: from) {
            let s = try from.rect(piece.sourceTile), d = try to.rect(piece.destinationTile)
            #expect(piece.width >= 1 && piece.height >= 1 && piece.destinationX >= 0 && piece.destinationY >= 0)
            #expect(piece.destinationX + piece.width <= d.width && piece.destinationY + piece.height <= d.height)
            for gy in 0..<piece.height { for gx in 0..<piece.width {
                let lx = piece.sourceX + gx * map.column.x + gy * map.row.x
                let ly = piece.sourceY + gx * map.column.y + gy * map.row.y
                #expect(lx >= 0 && ly >= 0 && lx < s.width && ly < s.height, "a piece reads inside its source tile")
                let (x, y) = (d.x + piece.destinationX + gx, d.y + piece.destinationY + gy)
                try out.setPixel(x: x, y: y, source.pixel(x: s.x + lx, y: s.y + ly))
                writes[y * map.width + x] += 1
            } }
        }
        return (out, writes)
    }

    @Test func turnsMatchCoreRasterAcrossTiles() throws {
        for (w, h) in [(300, 520), (1, 257), (256, 256), (3, 2)] {
            let source = try Self.coordinates(w, h)
            let tiling = try SurfaceTiling(width: w, height: h)
            for turn in [QuarterTurn.degrees90, .degrees180, .degrees270] {
                let (out, writes) = try Self.apply(TileMap.turn(tiling, turn), to: source)
                #expect(out == source.rotated(turn), "\(w)x\(h) \(turn)")
                #expect(writes.allSatisfy { $0 == 1 }, "every pixel written once, \(w)x\(h) \(turn)")
            }
        }
    }

    @Test func cropsAtEveryCornerAndAcrossSeamsMatchCoreRaster() throws {
        let (w, h) = (530, 300)
        let source = try Self.coordinates(w, h)
        let tiling = try SurfaceTiling(width: w, height: h)
        let (cw, ch) = (270, 100)
        let rects = [(0, 0, cw, ch), (w - cw, 0, cw, ch), (0, h - ch, cw, ch), (w - cw, h - ch, cw, ch),
                     (200, 150, cw, ch), (0, 0, w, h), (255, 255, 2, 2)]
        for (x, y, cw, ch) in rects {
            let (out, writes) = try Self.apply(TileMap.crop(tiling, x: x, y: y, width: cw, height: ch), to: source)
            #expect(out == (try source.cropped(x: x, y: y, width: cw, height: ch)), "crop \(cw)x\(ch) at (\(x), \(y))")
            #expect(writes.allSatisfy { $0 == 1 })
        }
    }

    @Test func piecesRefuseATilingOfAnotherSize() throws {
        let tiling = try SurfaceTiling(width: 300, height: 200)
        let maps = [TileMap.turn(tiling, .degrees90), TileMap.turn(tiling, .degrees180),
                    try TileMap.crop(tiling, x: 10, y: 20, width: 100, height: 50)]
        for map in maps {
            #expect(map.sourceWidth == 300 && map.sourceHeight == 200)
            #expect(try !map.pieces(from: tiling).isEmpty)
            for (w, h) in [(600, 600), (301, 200), (300, 199), (200, 300)] {
                #expect(throws: RenderError.raster("tile map made for 300x200, given \(w)x\(h)")) {
                    try map.pieces(from: SurfaceTiling(width: w, height: h))
                }
            }
        }
    }

    @Test func invalidCropsThrowTheCPUBackendsError() throws {
        let (cpu, tiling) = (CPUBackend(), try SurfaceTiling(width: 300, height: 20))
        let surface = try cpu.surface(PixelBuffer(width: 300, height: 20))
        let bad = [(-1, 0, 2, 2), (0, -1, 2, 2), (299, 0, 2, 2), (0, 19, 2, 2), (0, 0, 0, 2), (0, 0, 2, -3),
                   (0, 0, 301, 1), (Int.max, Int.max, Int.max, Int.max), (Int.min, 0, 1, 1), (1, 1, 300, 20)]
        for (x, y, w, h) in bad {
            do {
                _ = try cpu.cropped(surface, x: x, y: y, width: w, height: h)
                Issue.record("the CPU accepts \(w)x\(h) at (\(x), \(y))")
            } catch let expected as RenderError {
                #expect(throws: expected) { try TileMap.crop(tiling, x: x, y: y, width: w, height: h) }
            }
        }
    }
}
