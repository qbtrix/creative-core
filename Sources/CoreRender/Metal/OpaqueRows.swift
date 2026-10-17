// OpaqueRows.swift: the opaque-row fast path's pure part (MB-6). CoreRaster's in-place composite copies a
// source row in when the mode is `.normal`, the opacity is exactly 1 and every alpha of the row is exactly 1
// (the formula then gives the source itself); the Metal backend blits those rows. This splits a CompositeMap
// piece into runs of whole rows, blit or kernel, from the stored pixels. Invariants: the rule is CoreRaster's
// (`==` on alpha and opacity, never a near-1 threshold); the runs cover every row of the piece exactly once,
// in order, and adjacent runs differ in kind. Linux-safe.
import CoreRaster

/// Whole rows of a composite piece that are all copied (`opaque`) or all blended by the kernel.
public struct RowRun: Equatable, Hashable, Sendable {
    /// The rows as a piece of their own: the parent's columns and tiles, a band of its rows.
    public let piece: TilePiece
    /// True when every row of the run is copied as is.
    public let opaque: Bool
}

/// The row split of the opaque-row fast path.
public enum OpaqueRows {
    /// CoreRaster's copy condition on the call: `.normal` at opacity exactly 1. Anything else never copies.
    public static func applies(mode: BlendMode, opacity: Float) -> Bool { mode == .normal && opacity == 1 }

    /// Per row of `piece`, whether every alpha in its columns of `tile` (the piece's source tile, as stored)
    /// is exactly 1. Throws `RenderError.raster` when the piece does not lie inside `tile`.
    public static func flags(of piece: TilePiece, in tile: PixelBuffer) throws -> [Bool] {
        guard piece.width >= 1, piece.height >= 1, piece.sourceX >= 0, piece.sourceY >= 0,
              piece.sourceX <= tile.width - piece.width, piece.sourceY <= tile.height - piece.height else {
            throw RenderError.raster("piece \(piece.width)x\(piece.height) at (\(piece.sourceX), \(piece.sourceY)) is outside its \(tile.width)x\(tile.height) tile")
        }
        return try (piece.sourceY..<(piece.sourceY + piece.height)).map { y in
            try (piece.sourceX..<(piece.sourceX + piece.width)).allSatisfy { x in
                try RenderError.mapping { try tile.pixel(x: x, y: y) }.a == 1
            }
        }
    }

    /// `piece` split into maximal runs of rows with the same `opaque` flag, top to bottom. Throws
    /// `RenderError.raster` unless there is one flag per row.
    public static func runs(of piece: TilePiece, opaque: [Bool]) throws -> [RowRun] {
        guard opaque.count == piece.height else {
            throw RenderError.raster("\(opaque.count) row flags for a piece \(piece.height) rows high")
        }
        var runs: [RowRun] = []
        var start = 0
        while start < opaque.count {
            var end = start + 1
            while end < opaque.count, opaque[end] == opaque[start] { end += 1 }
            let rows = TilePiece(sourceTile: piece.sourceTile, destinationTile: piece.destinationTile,
                                 sourceX: piece.sourceX, sourceY: piece.sourceY + start,
                                 destinationX: piece.destinationX, destinationY: piece.destinationY + start,
                                 width: piece.width, height: end - start)
            runs.append(RowRun(piece: rows, opaque: opaque[start]))
            start = end
        }
        return runs
    }
}
