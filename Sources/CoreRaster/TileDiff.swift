// TileDiff.swift: tile-by-tile undo for a raster edit. A diff keeps, for each
// tile of the grid in Tiles.swift whose components differ between two buffers
// of one size, that tile's index and its before and after contents; unchanged
// tiles store nothing. Components compare by bit pattern, so 0.0 to -0.0 is a
// change and undo restores the exact bytes; `==` compares kept tiles the same
// way, so equal diffs always undo and redo to the same bytes. Every kept tile matches its
// `tileRect` in a buffer of the diff's size, so undo and redo can only fail on
// a buffer of another size, which they reject before writing anything.

/// The tiles that changed between two same-size buffers, with their before
/// and after contents. A plain value; raster commands hold one for undo.
public struct TileDiff: Equatable, Sendable {
    /// One changed tile: its grid index and its contents before and after.
    /// Equal only when the indices match and both tiles match bit for bit,
    /// unlike `PixelBuffer ==`, which treats 0.0 and -0.0 as equal.
    struct Entry: Equatable, Sendable {
        let column: Int
        let row: Int
        let before: PixelBuffer
        let after: PixelBuffer

        static func == (lhs: Entry, rhs: Entry) -> Bool {
            lhs.column == rhs.column && lhs.row == rhs.row
                && sameBits(lhs.before, rhs.before) && sameBits(lhs.after, rhs.after)
        }

        private static func sameBits(_ a: PixelBuffer, _ b: PixelBuffer) -> Bool {
            guard a.width == b.width, a.height == b.height else { return false }
            let whole = TileRect(x: 0, y: 0, width: a.width, height: a.height)
            return !TileDiff.differ(a.components, b.components, in: whole, width: a.width)
        }
    }

    /// The width of the buffers the diff was made from.
    public let width: Int
    /// The height of the buffers the diff was made from.
    public let height: Int
    let entries: [Entry]

    /// Compares `before` and `after` tile by tile. Throws `RasterError.invalid`
    /// when their sizes differ.
    public init(before: PixelBuffer, after: PixelBuffer) throws {
        guard before.width == after.width, before.height == after.height else {
            throw RasterError.invalid(
                "diff of a \(before.width)x\(before.height) buffer and a \(after.width)x\(after.height) buffer")
        }
        let old = before.components
        let new = after.components
        var entries = [Entry]()
        for row in 0..<before.tileRows {
            for column in 0..<before.tileColumns {
                let rect = try before.tileRect(column: column, row: row)
                guard Self.differ(old, new, in: rect, width: before.width) else { continue }
                entries.append(Entry(column: column, row: row,
                                     before: try before.tile(column: column, row: row),
                                     after: try after.tile(column: column, row: row)))
            }
        }
        self.width = before.width
        self.height = before.height
        self.entries = entries
    }

    /// How many tiles changed and are kept.
    public var tileCount: Int { entries.count }

    /// Writes the before tiles back into `buffer`. Throws `RasterError.invalid`
    /// when `buffer` isn't the diff's size, leaving it unchanged.
    public func undo(_ buffer: inout PixelBuffer) throws {
        try apply(to: &buffer) { $0.before }
    }

    /// Writes the after tiles into `buffer`. Throws `RasterError.invalid`
    /// when `buffer` isn't the diff's size, leaving it unchanged.
    public func redo(_ buffer: inout PixelBuffer) throws {
        try apply(to: &buffer) { $0.after }
    }

    private func apply(to buffer: inout PixelBuffer, _ contents: (Entry) -> PixelBuffer) throws {
        guard buffer.width == width, buffer.height == height else {
            throw RasterError.invalid("diff of \(width)x\(height) buffers applied to \(buffer.width)x\(buffer.height)")
        }
        for entry in entries {
            try buffer.replaceTile(column: entry.column, row: entry.row, with: contents(entry))
        }
    }

    /// True when any component inside `rect` differs by bit pattern. Both
    /// arrays hold a buffer `width` pixels wide that contains `rect`.
    private static func differ(_ a: [Float], _ b: [Float], in rect: TileRect, width: Int) -> Bool {
        let rowCount = rect.width * PixelBuffer.channels
        for y in rect.y..<(rect.y + rect.height) {
            let start = (y * width + rect.x) * PixelBuffer.channels
            for i in start..<(start + rowCount) where a[i].bitPattern != b[i].bitPattern {
                return true
            }
        }
        return false
    }
}
