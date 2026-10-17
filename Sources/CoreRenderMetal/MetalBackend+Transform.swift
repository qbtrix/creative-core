// MetalBackend+Transform.swift: crop as blits and quarter turns through `transform_rotate` (MB-7), piece
// by piece from a TileMap into a new surface. Invariants: an invalid crop throws the CPU's exact error;
// each output pixel is a bit-exact copy of one source half (evicted tiles via a temporary texture); the
// lock is never held across the GPU wait; a failed command buffer or allocation throws `deviceLost`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// Copies `s` into a new surface along `makeMap`'s map: blits when `blit` (a crop), else the kernel.
    func transformed(_ s: RenderSurface, blit: Bool, _ makeMap: (SurfaceTiling) throws -> TileMap) throws -> RenderSurface {
        let (map, pieces, sources, pipeline, queue, clock) = try withLock { () throws -> TransformPlan in
            guard state.healthy else { throw RenderError.deviceLost(state.lastError ?? "backend unhealthy") }
            let stored = try lookup(s)
            let map = try makeMap(stored.tiling)
            let pieces = try map.pieces(from: stored.tiling)
            let clock = tick()
            stored.touch(clock)
            var sources: [Int: SourceTile] = [:]
            for index in Set(pieces.map(\.sourceTile)) {
                sources[index] = stored.tiles[index].map(SourceTile.texture) ?? stored.shadows[index].map(SourceTile.shadow)
            }
            let pipeline: (any MTLComputePipelineState)? = try blit ? nil : pipelines.pipeline(for: TransformShader.key, source: TransformShader.source)
            return (map, pieces, sources, pipeline, commandQueue, clock)
        }
        let textures = try sources.mapValues { source -> any MTLTexture in
            switch source {
            case .texture(let texture): return texture
            case .shadow(let shadow): // A one-tile surface never stored: its texture lives as long as this op.
                guard let texture = try allocate({ try MetalSurface(device: device, buffer: shadow, clock: 0) }).tiles.first ?? nil
                else { throw RenderError.raster("transform: empty staged tile") }
                return texture
            }
        }
        let output = try allocate { try MetalSurface(device: device, buffer: PixelBuffer(width: map.width, height: map.height), clock: clock) }
        let pairs = try pieces.map { piece in
            guard let from = textures[piece.sourceTile], let to = output.tiles[piece.destinationTile] else {
                throw RenderError.raster("transform: tile \(piece.sourceTile) or \(piece.destinationTile) is missing")
            }
            return (piece, from, to)
        }
        guard let commands = queue.makeCommandBuffer() else { throw lost("transform: no command buffer on \(device.name)") }
        if let pipeline {
            guard let encoder = commands.makeComputeCommandEncoder() else { throw lost("transform: no compute encoder on \(device.name)") }
            encoder.setComputePipelineState(pipeline)
            let width = max(pipeline.threadExecutionWidth, 1), height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
            let group = MTLSize(width: width, height: height, depth: 1)
            for (piece, from, to) in pairs {
                let parameters = [piece.destinationX, piece.destinationY, piece.width, piece.height, piece.sourceX,
                                  piece.sourceY, map.column.x, map.column.y, map.row.x, map.row.y].map { Int32(clamping: $0) }
                encoder.setTexture(from, index: 0)
                encoder.setTexture(to, index: 1)
                parameters.withUnsafeBytes { raw in
                    if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: 0) }
                }
                let grid = MTLSize(width: (piece.width + group.width - 1) / group.width, height: (piece.height + group.height - 1) / group.height, depth: 1)
                encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
            }
            encoder.endEncoding()
        }
        guard let blitter = commands.makeBlitCommandEncoder() else { throw lost("transform: no blit encoder on \(device.name)") }
        for (piece, from, to) in pairs where blit {
            blitter.copy(from: from, sourceSlice: 0, sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: piece.sourceX, y: piece.sourceY, z: 0),
                         sourceSize: MTLSize(width: piece.width, height: piece.height, depth: 1),
                         to: to, destinationSlice: 0, destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: piece.destinationX, y: piece.destinationY, z: 0))
        }
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        for case let tile? in output.tiles where tile.storageMode == .managed { blitter.synchronize(resource: tile) }
        #endif
        blitter.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "transform")
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: map.width, height: map.height)
    }

    /// `body`'s surface; a texture allocation failure inside it marks the backend failed, as `surface` does.
    private func allocate(_ body: () throws -> MetalSurface) throws -> MetalSurface {
        do { return try body() } catch RenderError.deviceLost(let reason) { throw lost(reason) }
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func lost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}

/// A source tile while a transform runs: its resident texture, or its shadow (uploaded to a temporary texture).
private enum SourceTile { case texture(any MTLTexture), shadow(PixelBuffer) }

/// Taken under the lock: map, pieces, source tiles, rotate pipeline (nil for a crop), queue, use stamp.
private typealias TransformPlan = (TileMap, [TilePiece], [Int: SourceTile], (any MTLComputePipelineState)?,
                                   any MTLCommandQueue, UInt64)
#endif
