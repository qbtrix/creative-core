// MetalBackend+OpaqueRows.swift: the opaque-row fast path of the in-place composite (MB-6). Under `.normal` at
// opacity exactly 1, the rows of a piece whose stored source alphas are all exactly 1 are blitted onto the
// backdrop instead of run through the kernel: CoreRaster copies those rows too, so the pixels are equal.
// Invariants: the decision reads the Float16 pixels the source tile holds (resident or staged), through
// OpaqueRows' Linux-tested split; any other mode or opacity, or a row with one alpha below 1, takes the kernel;
// blits and kernel pieces write disjoint rows; the blits encode before the managed-tile synchronize.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

extension MetalBackend {
    /// Rows of composite pieces copied by blit since init (a test hook: 0 unless the fast path ran).
    package var opaqueRowsBlitted: Int { withLock { blittedRows } }

    /// `pieces` split into the bands the kernel runs (`kernel`) and the opaque bands to blit (`blits`).
    /// Everything goes to the kernel unless `OpaqueRows.applies(mode:opacity:)`. `textures` holds each
    /// piece's source tile; a piece with none goes to the kernel, whose encode reports it. Lock free.
    func opaqueRowSplit(_ pieces: [TilePiece], textures: [Int: any MTLTexture], mode: BlendMode,
                        opacity: Float) throws -> (kernel: [TilePiece], blits: [TilePiece]) {
        guard OpaqueRows.applies(mode: mode, opacity: opacity) else { return (pieces, []) }
        var stored: [Int: PixelBuffer] = [:]
        let queue = withLock { commandQueue }
        var (kernel, blits): ([TilePiece], [TilePiece]) = ([], [])
        for piece in pieces {
            guard let texture = textures[piece.sourceTile] else { kernel.append(piece); continue }
            let tile = try stored[piece.sourceTile] ?? MetalSurface.download(
                texture, rect: TileRect(x: 0, y: 0, width: texture.width, height: texture.height), index: piece.sourceTile,
                queue: queue)
            stored[piece.sourceTile] = tile
            for run in try OpaqueRows.runs(of: piece, opaque: OpaqueRows.flags(of: piece, in: tile)) {
                if run.opaque { blits.append(run.piece) } else { kernel.append(run.piece) }
            }
        }
        return (kernel, blits)
    }

    /// Encodes one blit copy per band of `blits` from its source tile onto its backdrop tile in `commands`.
    /// Throws `RenderError.raster` for a missing tile and `deviceLost` (after marking the backend failed)
    /// when no blit encoder is made. Nothing is encoded for no bands. Lock free.
    func encodeOpaqueRows(_ blits: [TilePiece], textures: [Int: any MTLTexture], targets: [Int: any MTLTexture],
                          on commands: any MTLCommandBuffer) throws {
        guard !blits.isEmpty else { return }
        let pairs = try blits.map { piece in
            guard let from = textures[piece.sourceTile], let to = targets[piece.destinationTile] else {
                throw RenderError.raster("composite: tile \(piece.sourceTile) or \(piece.destinationTile) is missing")
            }
            return (piece, from, to)
        }
        guard let blitter = commands.makeBlitCommandEncoder() else {
            let reason = "composite: no blit encoder on \(device.name)"
            fail(reason)
            throw RenderError.deviceLost(reason)
        }
        for (piece, from, to) in pairs {
            blitter.copy(from: from, sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: piece.sourceX, y: piece.sourceY, z: 0),
                         sourceSize: MTLSize(width: piece.width, height: piece.height, depth: 1),
                         to: to, destinationSlice: 0, destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: piece.destinationX, y: piece.destinationY, z: 0))
        }
        blitter.endEncoding()
        withLock { blittedRows += blits.reduce(0) { $0 + $1.height } }
    }
}
#endif
