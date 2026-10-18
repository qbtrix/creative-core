// MetalBackend+Composite.swift: composite in place on the backdrop's tiles (MB-4), piece by piece from
// CompositeMap through `composite_normal` or a separable mode's kernel (MB-5, MetalBackend+BlendSeparable.swift).
// Invariants: an unhealthy backend throws `unsupported(family)` like any family outside `supports`; the CPU
// backend's checks in its order before any pixel changes; evicted backdrop tiles come back to textures first,
// a tile evicted after planning (or whose shadow changed) from its current shadow, and the budget holds after on
// every exit; a source that is the backdrop is read from a snapshot; no GPU wait under the lock; a GPU failure
// throws `deviceLost`; a target tile that leaves while the GPU writes it keeps that write: still evicted, its
// shadow comes from the written texture; evicted and restored (from a shadow taken before the write), the written
// texture replaces the restored one. Not held (no pin set): another op that writes such a restored tile inside
// that GPU window loses its write, since the restored texture it wrote is replaced.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// Read-write texture tier 2, which `composite_normal` needs to read and write rgba16Float tiles in place.
    static func compositesInPlace(on device: any MTLDevice) -> Bool { device.readWriteTextureSupport == .tier2 }

    /// Composites `s` over `b` through `mode` with source pixel (0, 0) on backdrop pixel (`x`, `y`), in place, as the CPU does.
    /// Throws `unsupported(RenderOp(compositing: mode))` when that family is not in `supports` (so while unhealthy).
    /// `afterStaging` runs with the lock free between planning and resolving the backdrop tiles: a test hook.
    package func compositeInPlace(_ s: RenderSurface, onto b: RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float,
                                  afterStaging: () -> Void = {}) throws {
        let planned = try withLock { () throws -> CompositePlan? in
            let family = RenderOp(compositing: mode)
            guard state.effectiveSupports.contains(family) else { throw RenderError.unsupported(family) }
            let (source, backdrop) = (try lookup(s), try lookup(b))
            try CompositeMap.validate(opacity: opacity)
            let pieces = try CompositeMap.pieces(source: source.tiling, onto: backdrop.tiling, x: x, y: y)
            guard !pieces.isEmpty else { return nil }
            let clock = tick()
            for surface in [source, backdrop] { surface.touch(clock) }
            var (resident, staged): ([Int: any MTLTexture], [Int: PixelBuffer]) = ([:], [:])
            for index in Set(pieces.map(\.sourceTile)) {
                if let tile = source.tiles[index], source !== backdrop {
                    resident[index] = tile
                } else if let tile = source.tiles[index] {  // one surface: read a snapshot, never the tile being written
                    staged[index] = try MetalSurface.download(tile, rect: source.tiling.rect(index), index: index, queue: commandQueue)
                } else {
                    staged[index] = source.shadows[index]
                }
            }
            var evicted: [Int: PixelBuffer] = [:]
            for index in Set(pieces.map(\.destinationTile)) where backdrop.tiles[index] == nil {
                evicted[index] = backdrop.shadows[index]
            }
            let kernel = try Self.compositeKernel(for: mode)
            let pipeline = try pipelines.pipeline(for: kernel.key, source: kernel.source)
            return CompositePlan(backdrop: backdrop, pieces: pieces, resident: resident, staged: staged, evicted: evicted, pipeline: pipeline, queue: commandQueue)
        }
        guard let plan = planned else { return }
        defer { evictIfNeeded() }  // restored tiles leave again on every exit, a throw included
        let textures = try plan.resident.merging(plan.staged.mapValues { try stageTile($0) }) { kept, _ in kept }
        let restored = try plan.evicted.mapValues { try stageTile($0) }
        afterStaging()
        let resolved = withLock { () -> Result<[Int: any MTLTexture], any Error> in
            var targets: [Int: any MTLTexture] = [:]
            for index in Set(plan.pieces.map(\.destinationTile)) {
                if let tile = plan.backdrop.tiles[index] {
                    targets[index] = tile
                    continue
                }
                // Evicted now: the staged texture if its shadow is unchanged since planning, else the current
                // shadow (evicted after planning, or rewritten by another op), uploaded here with no GPU wait.
                guard let shadow = plan.backdrop.shadows[index], let rect = try? plan.backdrop.tiling.rect(index) else { continue }
                let texture: any MTLTexture
                if let staged = restored[index], plan.evicted[index] == shadow {
                    texture = staged
                } else {
                    do { texture = try Self.makeTile(shadow, on: device) } catch { return .failure(error) }
                }
                plan.backdrop.tiles[index] = texture
                plan.backdrop.shadows[index] = nil
                plan.backdrop.residentBytes += MetalSurface.bytes(of: rect)
                targets[index] = texture
            }
            return .success(targets)
        }
        let targets: [Int: any MTLTexture]
        do { targets = try resolved.get() } catch RenderError.deviceLost(let reason) { throw compositeLost(reason) }
        let split = try opaqueRowSplit(plan.pieces, textures: textures, mode: mode, opacity: opacity)  // MB-6
        try encode(plan, pieces: split.kernel, blits: split.blits, textures: textures, targets: targets, opacity: opacity)
        do {  // a target that left while the GPU wrote it: an evicted tile's shadow, or a restored tile, is the written texture
            try withLock {
                for (index, texture) in targets {
                    guard let current = plan.backdrop.tiles[index] else {
                        plan.backdrop.shadows[index] = try MetalSurface.download(texture, rect: plan.backdrop.tiling.rect(index), index: index,
                                                                                 queue: commandQueue)
                        continue
                    }
                    if current !== texture { plan.backdrop.tiles[index] = texture }  // same rect, so residentBytes holds
                }
            }
        } catch { throw compositeLost("composite: \(error)") }
    }

    /// Runs the plan's kernel over `pieces`, blits `blits` (MetalBackend+OpaqueRows.swift) and waits; call with the lock free.
    private func encode(_ plan: CompositePlan, pieces: [TilePiece], blits: [TilePiece], textures: [Int: any MTLTexture],
                        targets: [Int: any MTLTexture], opacity: Float) throws {
        let pairs = try pieces.map { piece in
            guard let from = textures[piece.sourceTile], let to = targets[piece.destinationTile] else {
                throw RenderError.raster("composite: tile \(piece.sourceTile) or \(piece.destinationTile) is missing")
            }
            return (piece, from, to)
        }
        guard let commands = plan.queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw compositeLost("composite: no command buffer or encoder on \(device.name)")
        }
        encoder.setComputePipelineState(plan.pipeline)
        let width = max(plan.pipeline.threadExecutionWidth, 1)
        let group = MTLSize(width: width, height: max(plan.pipeline.maxTotalThreadsPerThreadgroup / width, 1), depth: 1)
        var alpha = opacity
        for (piece, from, to) in pairs {
            let parameters = [piece.destinationX, piece.destinationY, piece.width, piece.height, piece.sourceX, piece.sourceY]
                .map { Int32(clamping: $0) }
            encoder.setTextures([from, to], range: 0..<2)
            encoder.setBytes(parameters, length: parameters.count * MemoryLayout<Int32>.stride, index: 0)
            encoder.setBytes(&alpha, length: MemoryLayout<Float>.size, index: 1)
            let grid = MTLSize(width: (piece.width + group.width - 1) / group.width, height: (piece.height + group.height - 1) / group.height, depth: 1)
            encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        }
        encoder.endEncoding()
        try encodeOpaqueRows(blits, textures: textures, targets: targets, on: commands)
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        let managed = targets.values.filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw compositeLost("composite: no blit encoder on \(device.name)") }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "composite")
    }

    /// `pixels` (one tile) as a new tile texture; an allocation failure marks the backend failed. Lock free.
    private func stageTile(_ pixels: PixelBuffer) throws -> any MTLTexture {
        do { return try Self.makeTile(pixels, on: device) } catch RenderError.deviceLost(let reason) { throw compositeLost(reason) }
    }

    /// `pixels` (one tile) as a new tile texture, a CPU upload with no GPU wait; safe under the lock. Throws
    /// `deviceLost` on an allocation failure without failing the backend: the caller does that with the lock free.
    static func makeTile(_ pixels: PixelBuffer, on device: any MTLDevice) throws -> any MTLTexture {
        guard let tile = try MetalSurface(device: device, buffer: pixels, clock: 0).tiles.first ?? nil else {
            throw RenderError.raster("composite: empty staged tile")
        }
        return tile
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func compositeLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}

/// Taken under the lock: the backdrop, pieces, source tiles, evicted backdrop shadows, pipeline and queue.
private struct CompositePlan {
    let backdrop: MetalSurface
    let pieces: [TilePiece]
    let resident: [Int: any MTLTexture]
    let staged: [Int: PixelBuffer]  // source tiles to upload to temporary textures: shadows, or snapshots
    let evicted: [Int: PixelBuffer]
    let pipeline: any MTLComputePipelineState
    let queue: any MTLCommandQueue
}
#endif
