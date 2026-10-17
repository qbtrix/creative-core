// SurfaceTiling.swift: the grid of `tileSize` square tiles a Metal surface is
// split into, one texture per tile. The grid math is CoreRaster's
// (`PixelBuffer.tileCount(covering:)` and `tileRect(column:row:width:height:)`),
// so a surface tile uploads from and downloads to the matching buffer tile.
// This file adds the row-major index, `tiles(touching:)`, `defaultBudget`, the
// Metal backend's default memory budget in tile-sized steps, and `wholeImageFits`,
// the device buffer-limit check of the ops that stage a whole image in one buffer.
// Invariants: the size passes `PixelBuffer.validatedSize`; tiles
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
        _ = try RenderError.mapping { try PixelBuffer.validatedSize(width: width, height: height) }
        self.width = width
        self.height = height
    }

    /// The number of tile columns: the width divided by `tileSize`, rounded up.
    public var columns: Int { PixelBuffer.tileCount(covering: width) }

    /// The number of tile rows: the height divided by `tileSize`, rounded up.
    public var rows: Int { PixelBuffer.tileCount(covering: height) }

    /// The number of tiles, `columns * rows`; tile indices are `0..<tileCount`.
    public var tileCount: Int { columns * rows }

    /// The pixel rectangle of tile `index`, counted row-major from the top
    /// left, clipped to the surface. Throws `RenderError.raster` when `index`
    /// is outside `0..<tileCount`.
    public func rect(_ index: Int) throws -> TileRect {
        guard index >= 0, index < tileCount else {
            throw RenderError.raster("tile index \(index) out of 0..<\(tileCount)")
        }
        return try RenderError.mapping {
            try PixelBuffer.tileRect(column: index % columns, row: index / columns, width: width, height: height)
        }
    }

    /// The Metal backend's default memory budget: half the device's
    /// recommended working set, but never less than one full tile of
    /// `tileBytes`, so even a tiny or unknown working set fits one tile.
    public static func defaultBudget(workingSet: UInt64, tileBytes: Int) -> Int {
        max(Int(clamping: workingSet / 2), tileBytes)
    }

    /// True when a `width` x `height` image of `bytesPerPixel` bytes a pixel fits in one buffer of at most
    /// `maxBufferLength` bytes. Blur, unsharp and retouch stage the whole image as float4 (16 bytes a pixel) and
    /// throw their own `unsupported` op (a device limit, not bad input) when this is false. A negative factor
    /// or an overflowing product never fits, so any `Int` is safe.
    public static func wholeImageFits(width: Int, height: Int, bytesPerPixel: Int, maxBufferLength: Int) -> Bool {
        guard width >= 0, height >= 0, bytesPerPixel >= 0 else { return false }
        let (pixels, pixelsOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, bytesOverflow) = pixels.multipliedReportingOverflow(by: bytesPerPixel)
        return !pixelsOverflow && !bytesOverflow && bytes <= maxBufferLength
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
