// CompositeMap.swift: an in-place composite at an integer offset split into tile-to-tile pieces (MB-4), and
// CoreRaster's opacity check. Invariants: CoreRaster's clip (a source wholly outside gives no piece; any `Int`
// offset is safe); every overlap pixel lies in exactly one piece, local to its tiles. Linux-safe.
import CoreRaster

/// The pieces of a composite of one tiled surface onto another.
public enum CompositeMap {
    /// Throws `RenderError.raster` with CoreRaster's message unless `opacity` is a finite value in 0...1 (so not NaN
    /// or infinite), as the CPU backend does.
    public static func validate(opacity: Float) throws {
        guard (0...1).contains(opacity) else { throw RenderError.raster("opacity \(opacity): must be a finite value in 0...1") }
    }

    /// Every backdrop pixel the source covers with its pixel (0, 0) on backdrop pixel (`x`, `y`), split
    /// by backdrop tile (`destinationTile`) and then by source tile, one piece per overlapping pair, in
    /// ascending backdrop tile order. Empty when the source lies wholly outside the backdrop. Throws
    /// `RenderError.raster` only if a tiling's `rect` fails, an internal inconsistency no valid tiling reaches.
    public static func pieces(source: SurfaceTiling, onto backdrop: SurfaceTiling, x: Int, y: Int) throws -> [TilePiece] {
        // Both bounds are checked before adding, so x + width cannot overflow (CoreRaster's clip).
        guard x < backdrop.width, y < backdrop.height, x > -source.width, y > -source.height else { return [] }
        let (ox0, oy0) = (max(x, 0), max(y, 0))
        let (ox1, oy1) = (min(x + source.width, backdrop.width), min(y + source.height, backdrop.height))
        var pieces: [TilePiece] = []
        for d in backdrop.tiles(touching: ox0, y: oy0, width: ox1 - ox0, height: oy1 - oy0) {
            let tile = try backdrop.rect(d)
            let (cx0, cy0) = (max(ox0, tile.x), max(oy0, tile.y))
            let (cx1, cy1) = (min(ox1, tile.x + tile.width), min(oy1, tile.y + tile.height))
            for s in source.tiles(touching: cx0 - x, y: cy0 - y, width: cx1 - cx0, height: cy1 - cy0) {
                let from = try source.rect(s)
                let (ix0, iy0) = (max(cx0, x + from.x), max(cy0, y + from.y))
                let (ix1, iy1) = (min(cx1, x + from.x + from.width), min(cy1, y + from.y + from.height))
                guard ix0 < ix1, iy0 < iy1 else { continue }
                pieces.append(TilePiece(sourceTile: s, destinationTile: d, sourceX: ix0 - x - from.x, sourceY: iy0 - y - from.y,
                                        destinationX: ix0 - tile.x, destinationY: iy0 - tile.y, width: ix1 - ix0, height: iy1 - iy0))
            }
        }
        return pieces
    }
}
