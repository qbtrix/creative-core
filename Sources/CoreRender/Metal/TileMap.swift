// TileMap.swift: the pixel map of a crop or quarter turn between tiled surfaces and the tile-to-tile pieces
// the Metal backend copies (MB-7). Destination (x, y) reads source origin + x * column + y * row (unit axis
// steps, so the inverse is the transpose). Invariants: a crop passes CoreRaster's `cropped` checks with its
// messages; `pieces` refuses a tiling of another size than the map's source; every destination pixel lies
// in exactly one piece, local to its tiles. Integer math, Linux-safe.
import CoreRaster

/// One unit step in source pixels: exactly one of `x` and `y` is plus or minus 1.
public struct PixelStep: Equatable, Hashable, Sendable {
    public let x: Int, y: Int
}

/// A rectangle of the destination that lies in one destination tile and reads from one source
/// tile. Coordinates are local to their tiles; `width` and `height` are in destination pixels.
public struct TilePiece: Equatable, Hashable, Sendable {
    /// The row-major indexes of the source tile the piece reads and the destination tile it writes.
    public let sourceTile: Int, destinationTile: Int
    /// The source pixel (local to `sourceTile`) of the piece's top-left pixel (local to `destinationTile`).
    public let sourceX: Int, sourceY: Int, destinationX: Int, destinationY: Int
    /// The piece's size in destination pixels, each at least 1.
    public let width: Int, height: Int
}

/// The map of a crop or a quarter turn from a source surface to a new `width` x `height` one.
public struct TileMap: Equatable, Hashable, Sendable {
    /// The source pixel of destination pixel (0, 0).
    public let originX: Int, originY: Int
    /// The source step for one destination column (x + 1) and for one row (y + 1).
    public let column: PixelStep, row: PixelStep
    /// The destination size in pixels.
    public let width: Int, height: Int
    /// The size of the source this map was made for.
    public let sourceWidth: Int, sourceHeight: Int

    /// The `width` x `height` region of `source` at (`x`, `y`). Throws `RenderError.raster` with
    /// CoreRaster's messages, size first, then bounds; no subtraction can overflow for any `Int`.
    public static func crop(_ source: SurfaceTiling, x: Int, y: Int, width: Int, height: Int) throws -> TileMap {
        _ = try RenderError.mapping { try PixelBuffer.validatedSize(width: width, height: height) }
        guard x >= 0, y >= 0, width <= source.width, height <= source.height,
              x <= source.width - width, y <= source.height - height else {
            throw RenderError.raster("crop \(width)x\(height) at (\(x), \(y)) is outside \(source.width)x\(source.height)")
        }
        return TileMap(originX: x, originY: y, column: PixelStep(x: 1, y: 0), row: PixelStep(x: 0, y: 1),
                       width: width, height: height, sourceWidth: source.width, sourceHeight: source.height)
    }

    /// `source` turned clockwise by `turn`, as CoreRaster's `rotated`: a quarter turn swaps width and height.
    public static func turn(_ source: SurfaceTiling, _ turn: QuarterTurn) -> TileMap {
        let (w, h) = (source.width, source.height)
        let step = { (x: Int, y: Int) in PixelStep(x: x, y: y) }
        switch turn {
        case .degrees90: return TileMap(originX: 0, originY: h - 1, column: step(0, -1), row: step(1, 0), width: h, height: w, sourceWidth: w, sourceHeight: h)
        case .degrees180: return TileMap(originX: w - 1, originY: h - 1, column: step(-1, 0), row: step(0, -1), width: w, height: h, sourceWidth: w, sourceHeight: h)
        case .degrees270: return TileMap(originX: w - 1, originY: 0, column: step(0, 1), row: step(-1, 0), width: h, height: w, sourceWidth: w, sourceHeight: h)
        }
    }

    /// The source pixel destination pixel (`x`, `y`) copies.
    public func source(x: Int, y: Int) -> (x: Int, y: Int) {
        (originX + x * column.x + y * row.x, originY + x * column.y + y * row.y)
    }

    /// The destination pixel source pixel (`x`, `y`) lands on: the transpose of `source`.
    func destination(x: Int, y: Int) -> (x: Int, y: Int) {
        let (u, v) = (x - originX, y - originY)
        return (u * column.x + v * column.y, u * row.x + v * row.y)
    }

    /// Every destination pixel, split by destination tile and then by source tile, one piece per
    /// overlapping pair. Throws `RenderError.raster` unless `source` is the size this map was made for.
    public func pieces(from source: SurfaceTiling) throws -> [TilePiece] {
        guard source.width == sourceWidth, source.height == sourceHeight else {
            throw RenderError.raster("tile map made for \(sourceWidth)x\(sourceHeight), given \(source.width)x\(source.height)")
        }
        let grid = try SurfaceTiling(width: width, height: height)
        var pieces: [TilePiece] = []
        for d in 0..<grid.tileCount {
            let tile = try grid.rect(d)
            let a = self.source(x: tile.x, y: tile.y)
            let b = self.source(x: tile.x + tile.width - 1, y: tile.y + tile.height - 1)
            let (sx0, sy0, sx1, sy1) = (min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
            for s in source.tiles(touching: sx0, y: sy0, width: sx1 - sx0 + 1, height: sy1 - sy0 + 1) {
                let from = try source.rect(s)
                let (ix0, iy0) = (max(sx0, from.x), max(sy0, from.y))
                let (ix1, iy1) = (min(sx1, from.x + from.width - 1), min(sy1, from.y + from.height - 1))
                guard ix0 <= ix1, iy0 <= iy1 else { continue }
                let p = destination(x: ix0, y: iy0), q = destination(x: ix1, y: iy1)
                let (dx, dy) = (min(p.x, q.x), min(p.y, q.y))
                let start = self.source(x: dx, y: dy)
                pieces.append(TilePiece(sourceTile: s, destinationTile: d, sourceX: start.x - from.x, sourceY: start.y - from.y,
                                        destinationX: dx - tile.x, destinationY: dy - tile.y, width: abs(p.x - q.x) + 1, height: abs(p.y - q.y) + 1))
            }
        }
        return pieces
    }
}
