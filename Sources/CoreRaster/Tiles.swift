// Tiles.swift: the tile grid over a PixelBuffer, for per-tile storage, paint
// and undo. Tiles are `tileSize` square from the top left; the last column and
// row are narrower or shorter when the size isn't a multiple of `tileSize`, so
// every tile lies inside the buffer. Tile reads and writes copy whole rows.

/// A tile's position and size in pixels within its buffer.
public struct TileRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension PixelBuffer {
    /// The width and height of a full tile, in pixels.
    public static let tileSize = 256

    /// The number of tile columns: the width divided by `tileSize`, rounded up.
    public var tileColumns: Int { (width + Self.tileSize - 1) / Self.tileSize }

    /// The number of tile rows: the height divided by `tileSize`, rounded up.
    public var tileRows: Int { (height + Self.tileSize - 1) / Self.tileSize }

    /// The pixel rectangle of the tile at `column`, `row`, clipped to the buffer.
    /// Throws `RasterError.invalid` when the index is outside the tile grid.
    public func tileRect(column: Int, row: Int) throws -> TileRect {
        guard (0..<tileColumns).contains(column), (0..<tileRows).contains(row) else {
            throw RasterError.invalid("tile (\(column), \(row)) is outside the \(tileColumns)x\(tileRows) tile grid")
        }
        let x = column * Self.tileSize
        let y = row * Self.tileSize
        return TileRect(x: x, y: y, width: min(Self.tileSize, width - x), height: min(Self.tileSize, height - y))
    }

    /// A copy of the tile at `column`, `row`, sized to its `tileRect`.
    /// Throws `RasterError.invalid` when the index is outside the tile grid.
    public func tile(column: Int, row: Int) throws -> PixelBuffer {
        let rect = try tileRect(column: column, row: row)
        let input = components
        let rowCount = rect.width * Self.channels
        var output = [Float]()
        output.reserveCapacity(rowCount * rect.height)
        for y in rect.y..<(rect.y + rect.height) {
            let start = (y * width + rect.x) * Self.channels
            output.append(contentsOf: input[start..<(start + rowCount)])
        }
        return PixelBuffer(checkedWidth: rect.width, height: rect.height, storage: output)
    }

    /// Writes `tile` over the tile at `column`, `row`. Throws
    /// `RasterError.invalid` when the index is outside the tile grid or the
    /// tile's size doesn't match that `tileRect`; the buffer is unchanged
    /// when it throws.
    public mutating func replaceTile(column: Int, row: Int, with tile: PixelBuffer) throws {
        let rect = try tileRect(column: column, row: row)
        guard tile.width == rect.width, tile.height == rect.height else {
            throw RasterError.invalid(
                "tile (\(column), \(row)) is \(rect.width)x\(rect.height), replacement is \(tile.width)x\(tile.height)")
        }
        copyRows(from: tile, toX: rect.x, toY: rect.y)
    }
}
