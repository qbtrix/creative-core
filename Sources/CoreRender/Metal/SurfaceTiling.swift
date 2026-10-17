// SurfaceTiling.swift: the grid of `tileSize` square tiles a Metal surface is
// split into, one texture per tile, on the same grid CoreRaster's Tiles.swift
// lays on a PixelBuffer, so a tile uploads from and downloads to the matching
// buffer tile. Invariants: the size passes `PixelBuffer.validatedSize`; tiles
// are numbered row-major from the top left; the last column and row are
// clipped to the surface and never 0 px wide, so every pixel lies in exactly
// one tile; `tiles(touching:)` never traps. Integer math only, no Metal import.
import CoreRaster

/// The tile grid over a width x height surface: `columns` x `rows` tiles of
/// `tileSize` pixels, the last column and row narrower or shorter when the
/// size is not a multiple of `tileSize`.
public struct SurfaceTiling: Equatable, Sendable {
    /// The width and height of a full tile in pixels: CoreRaster's, so a
    /// surface tile and a buffer tile cover the same pixels.
    public static let tileSize = PixelBuffer.tileSize

    /// The surface width in pixels, at least 1.
    public let width: Int
    /// The surface height in pixels, at least 1.
    public let height: Int

    /// A grid over a width x height surface. Throws `RenderError.raster` with
    /// the message of `PixelBuffer.validatedSize` for a side under 1 or a
    /// pixel count over `PixelBuffer.maxPixels`.
    public init(width: Int, height: Int) throws {
        do {
            _ = try PixelBuffer.validatedSize(width: width, height: height)
        } catch RasterError.invalid(let message) {
            throw RenderError.raster(message)
        }
        self.width = width
        self.height = height
    }

    /// The number of tile columns: the width divided by `tileSize`, rounded up.
    public var columns: Int { (width + Self.tileSize - 1) / Self.tileSize }

    /// The number of tile rows: the height divided by `tileSize`, rounded up.
    public var rows: Int { (height + Self.tileSize - 1) / Self.tileSize }

    /// The number of tiles, `columns * rows`; tile indices are `0..<tileCount`.
    public var tileCount: Int { columns * rows }

    /// The pixel rectangle of tile `index`, counted row-major from the top
    /// left, clipped to the surface. Throws `RenderError.raster` when `index`
    /// is outside `0..<tileCount`.
    public func rect(_ index: Int) throws -> TileRect {
        guard index >= 0, index < tileCount else {
            throw RenderError.raster("tile index \(index) out of 0..<\(tileCount)")
        }
        let x = (index % columns) * Self.tileSize
        let y = (index / columns) * Self.tileSize
        return TileRect(x: x, y: y, width: min(Self.tileSize, width - x), height: min(Self.tileSize, height - y))
    }

    /// The indices of the tiles the pixel rect overlaps, ascending. Empty when
    /// the rect has no area or lies wholly outside the surface. Never traps:
    /// the rect is clipped to the surface before any tile math, and the
    /// inclusive end is taken with overflow reporting, so any `Int` is safe.
    public func tiles(touching x: Int, y: Int, width: Int, height: Int) -> [Int] {
        guard width > 0, height > 0 else { return [] }
        let x0 = max(x, 0)
        let y0 = max(y, 0)
        let x1 = Self.clippedEnd(start: x, length: width, bound: self.width)
        let y1 = Self.clippedEnd(start: y, length: height, bound: self.height)
        guard x0 <= x1, y0 <= y1 else { return [] }
        let firstColumn = x0 / Self.tileSize
        let lastColumn = x1 / Self.tileSize
        let firstRow = y0 / Self.tileSize
        let lastRow = y1 / Self.tileSize
        var indices: [Int] = []
        indices.reserveCapacity((lastColumn - firstColumn + 1) * (lastRow - firstRow + 1))
        for row in firstRow...lastRow {
            for column in firstColumn...lastColumn {
                indices.append(row * columns + column)
            }
        }
        return indices
    }

    /// The inclusive last pixel of a span, `start + length - 1`, clamped to
    /// `bound - 1`. `length` is at least 1, so `length - 1` cannot overflow; a
    /// sum past `Int.max` is beyond the surface and clamps like any other.
    private static func clippedEnd(start: Int, length: Int, bound: Int) -> Int {
        let (end, overflow) = start.addingReportingOverflow(length - 1)
        return overflow ? bound - 1 : min(end, bound - 1)
    }
}
