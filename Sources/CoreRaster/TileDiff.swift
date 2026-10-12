// TileDiff.swift: undo data for a raster edit that keeps only the tiles that
// changed. Built on the PixelBuffer tile grid (Tiles.swift): each kept tile
// holds its grid index and its before and after contents; unchanged tiles store
// nothing. Tiles compare by Float bit pattern, so 0.0 to -0.0 counts as a change
// and undo restores the exact bytes. A diff only applies to a buffer of the size
// it was made from.

/// The changed tiles between two same-sized buffers, with undo and redo.
/// A plain value, not a FlareCore `Command`: paint commands hold one.
public struct TileDiff: Equatable, Sendable {
    /// One changed tile: its grid index and its contents before and after.
    struct Tile: Equatable, Sendable {
        var column: Int
        var row: Int
        var before: PixelBuffer
        var after: PixelBuffer
    }

    public let width: Int
    public let height: Int
    var tiles: [Tile]

    /// Compares `before` and `after` tile by tile and keeps the tiles that
    /// differ in any component's bits. Throws `RasterError.invalid` when the
    /// buffers differ in size.
    public init(before: PixelBuffer, after: PixelBuffer) throws {
        guard before.width == after.width, before.height == after.height else {
            throw RasterError.invalid(
                "tile diff of a \(before.width)x\(before.height) and a \(after.width)x\(after.height) buffer")
        }
        var tiles: [Tile] = []
        for row in 0..<before.tileRows {
            for column in 0..<before.tileColumns {
                let old = try before.tile(column: column, row: row)
                let new = try after.tile(column: column, row: row)
                let same = old.components.elementsEqual(new.components) { $0.bitPattern == $1.bitPattern }
                if !same { tiles.append(Tile(column: column, row: row, before: old, after: new)) }
            }
        }
        self.width = before.width
        self.height = before.height
        self.tiles = tiles
    }

    /// The number of changed tiles the diff keeps.
    public var tileCount: Int { tiles.count }

    /// Writes the before tiles into `buffer`. Throws `RasterError.invalid`,
    /// leaving `buffer` unchanged, when its size isn't the diff's.
    public func undo(_ buffer: inout PixelBuffer) throws {
        try apply(to: &buffer) { $0.before }
    }

    /// Writes the after tiles into `buffer`. Throws `RasterError.invalid`,
    /// leaving `buffer` unchanged, when its size isn't the diff's.
    public func redo(_ buffer: inout PixelBuffer) throws {
        try apply(to: &buffer) { $0.after }
    }

    private func apply(to buffer: inout PixelBuffer, _ contents: (Tile) -> PixelBuffer) throws {
        guard buffer.width == width, buffer.height == height else {
            throw RasterError.invalid(
                "tile diff for \(width)x\(height) applied to a \(buffer.width)x\(buffer.height) buffer")
        }
        for tile in tiles {
            try buffer.replaceTile(column: tile.column, row: tile.row, with: contents(tile))
        }
    }
}
