// MetalBackend+Resident.swift: the Metal side of resident rendering. `blank` clears a new tiled surface with
// blits from a zero buffer and `copied` blits every tile of its source into one, with no CPU tile write
// (an evicted source tile is staged from its shadow); the batched `composite(_:onto:)` encodes every step's
// tile pieces, through each mode's kernel (MetalBackend+Composite.swift's), into one command buffer. All three
// commit with no wait, so a frame that copies its base, composites three layers over it and then displays
// them waits on the GPU once, in the display.
// Invariants: every step's family is checked, and every surface looked up, before anything changes; a step
// whose surface is the backdrop runs the steps one at a time through `compositeInPlace`, which reads such a
// source from a snapshot; evicted source tiles are staged from their shadows, evicted backdrop tiles restored
// to textures under the lock; the command buffer is committed under the lock, so every later op on the
// queue (a display, a `read`, an eviction's readback blit) is ordered after these writes by the tiles' hazard
// tracking, and `blank` and `copied` commit and store the new surface in one locked span, so no op sees it
// before its blits are queued; a GPU failure is recorded from the completion handler (backend failed, nothing thrown); `recover`
// waits for the last one before it swaps queues; the budget holds after on every exit; dispatches in the one
// serial compute encoder run in step order, so later steps blend over earlier.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// A clear `width` x `height` surface: every tile cleared by a blit from a zero buffer, committed with no
    /// wait (later ops on the queue see the zeros). Then evicts as `surface(_:)` does. Throws
    /// `RenderError.raster` for a size the tiling rejects and `deviceLost` (backend failed) when a texture,
    /// buffer or command buffer is unavailable.
    public func blank(width: Int, height: Int) throws -> RenderSurface {
        try storeUnwaited(label: "blank") { clock in
            let output = try MetalSurface(pool: texturePool, device: device, width: width, height: height, clock: clock)
            return (output, { try output.encodeClear(into: $0, device: self.device) })
        }
    }

    /// A new surface with `s`'s exact bits: a blit per tile from its texture (an evicted tile from a
    /// temporary texture staged from its shadow), committed with no wait; `s` is unchanged and marked used.
    /// Then evicts as `surface(_:)` does. Throws `surfaceMismatch` for a surface this backend does not hold
    /// and `deviceLost` (backend failed) when a texture or command buffer is unavailable.
    public func copied(_ s: RenderSurface) throws -> RenderSurface {
        try storeUnwaited(label: "copy") { clock in
            let source = try lookup(s)
            source.touch(clock)
            let tiling = source.tiling
            let from = try (0..<tiling.tileCount).map { index -> any MTLTexture in
                if let tile = source.tiles[index] { return tile }
                guard let shadow = source.shadows[index] else { throw RenderError.raster("copy: tile \(index) has neither a texture nor a shadow") }
                cpuTileUploads += 1  // the staged tile is a CPU upload
                return try Self.makeTile(shadow, on: device)
            }
            let output = try MetalSurface(pool: texturePool, device: device, width: tiling.width, height: tiling.height, clock: clock)
            return (output, { blit in
                for (index, texture) in from.enumerated() {
                    guard let to = output.tiles[index] else { throw RenderError.raster("copy: tile \(index) is missing") }
                    let rect = try tiling.rect(index)
                    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                              sourceSize: MTLSize(width: rect.width, height: rect.height, depth: 1), to: to,
                              destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
                }
            })
        }
    }

    /// Under the lock: `make` (given a fresh use stamp) returns a new surface and the blits that write every
    /// pixel of it; they are encoded into one command buffer, the surface's managed tiles synchronized, the
    /// buffer committed with no wait (as the batched composite is) and the surface stored. Then, lock free,
    /// evicts and returns its handle. A `deviceLost` fails the backend lock free before it is rethrown.
    private func storeUnwaited(label: String, _ make: (UInt64) throws -> (MetalSurface, (any MTLBlitCommandEncoder) throws -> Void))
        throws -> RenderSurface {
        let id = UUID()
        let outcome = try withLock { () throws -> Result<MetalSurface, RenderError> in
            do {
                let (output, encode) = try make(tick())
                guard let commands = commandQueue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else {
                    throw RenderError.deviceLost("\(label): no command buffer or blit encoder on \(device.name)")
                }
                try encode(blit)
                #if os(macOS)
                for case let tile? in output.tiles where tile.storageMode == .managed { blit.synchronize(resource: tile) }
                #endif
                blit.endEncoding()
                commitUnwaited(commands, label: label)
                surfaces[id] = output
                cpuTileUploads += output.uploadedTiles
                return .success(output)
            } catch RenderError.deviceLost(let reason) {
                return .failure(.deviceLost(reason))
            }
        }
        switch outcome {
        case .success(let output):
            evictIfNeeded()
            return handle(id: id, width: output.tiling.width, height: output.tiling.height)
        case .failure(let error):
            if case .deviceLost(let reason) = error { fail(reason) }
            throw error
        }
    }

    /// Every step composited onto `b` in order, in one command buffer: the pixels of one
    /// `composite(_:onto:x:y:mode:opacity:)` per step. Returns once the work is committed, not done: later ops
    /// on this backend see its pixels. Throws `unsupported(<family>)` for a step whose family is not in
    /// `supports` (so while unhealthy), `surfaceMismatch`, CoreRaster's opacity error, or `deviceLost`
    /// (backend failed) when the GPU work cannot be encoded; nothing changes before the GPU runs. A command
    /// buffer that fails on the GPU marks the backend failed when it completes, so later ops throw.
    public func composite(_ steps: [CompositeStep], onto b: inout RenderSurface) throws {
        if steps.contains(where: { $0.surface == b }) {
            for step in steps {
                try compositeInPlace(step.surface, onto: b, x: step.x, y: step.y, mode: step.mode, opacity: step.opacity)
            }
            return
        }
        let target = b
        let encoded = try withLock { () throws -> RenderError? in
            let backdrop = try lookup(target)
            var planned: [(step: CompositeStep, source: MetalSurface, pieces: [TilePiece], pipeline: any MTLComputePipelineState)] = []
            for step in steps {
                guard state.effectiveSupports.contains(step.family) else { throw RenderError.unsupported(step.family) }
                let source = try lookup(step.surface)
                try CompositeMap.validate(opacity: step.opacity)
                let kernel = try Self.compositeKernel(for: step.mode)
                let pieces = try CompositeMap.pieces(source: source.tiling, onto: backdrop.tiling, x: step.x, y: step.y)
                planned.append((step, source, pieces, try pipelines.pipeline(for: kernel.key, source: kernel.source)))
            }
            guard planned.contains(where: { !$0.pieces.isEmpty }) else { return nil }
            do {
                try encodeSteps(planned, onto: backdrop)
                return nil
            } catch let error as RenderError {
                return error
            }
        }
        defer { evictIfNeeded() }  // restored backdrop tiles leave again on every exit
        guard let encoded else { return }
        if case .deviceLost(let reason) = encoded { fail(reason) }
        throw encoded
    }

    /// Encodes and commits the planned pieces, with no wait; call with the lock held. Restores evicted backdrop tiles and
    /// stages evicted source tiles (CPU uploads, no GPU wait). Throws `deviceLost` without failing the
    /// backend (the caller does, lock free) when a texture, command buffer or encoder is unavailable.
    private func encodeSteps(_ planned: [(step: CompositeStep, source: MetalSurface, pieces: [TilePiece],
                                          pipeline: any MTLComputePipelineState)],
                             onto backdrop: MetalSurface) throws {
        let clock = tick()
        backdrop.touch(clock)
        var staged: [ObjectIdentifier: [Int: any MTLTexture]] = [:]
        for index in Set(planned.flatMap { $0.pieces.map(\.destinationTile) }) where backdrop.tiles[index] == nil {
            guard let shadow = backdrop.shadows[index] else { continue }
            backdrop.tiles[index] = try Self.makeTile(shadow, on: device)
            backdrop.shadows[index] = nil
            backdrop.residentBytes += MetalSurface.bytes(of: try backdrop.tiling.rect(index))
        }
        guard let commands = commandQueue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw RenderError.deviceLost("batched composite: no command buffer or encoder on \(device.name)")
        }
        var targets: [Int: any MTLTexture] = [:]
        for (step, source, pieces, pipeline) in planned where !pieces.isEmpty {
            source.touch(clock)
            encoder.setComputePipelineState(pipeline)
            let width = max(pipeline.threadExecutionWidth, 1)
            let group = MTLSize(width: width, height: max(pipeline.maxTotalThreadsPerThreadgroup / width, 1), depth: 1)
            var alpha = step.opacity
            for piece in pieces {
                let from: any MTLTexture
                if let resident = source.tiles[piece.sourceTile] {
                    from = resident
                } else if let held = staged[ObjectIdentifier(source)]?[piece.sourceTile] {
                    from = held
                } else if let shadow = source.shadows[piece.sourceTile] {
                    from = try Self.makeTile(shadow, on: device)
                    staged[ObjectIdentifier(source), default: [:]][piece.sourceTile] = from
                } else {
                    throw RenderError.raster("batched composite: source tile \(piece.sourceTile) has neither a texture nor a shadow")
                }
                guard let to = backdrop.tiles[piece.destinationTile] else {
                    throw RenderError.raster("batched composite: backdrop tile \(piece.destinationTile) is missing")
                }
                targets[piece.destinationTile] = to
                let parameters = [piece.destinationX, piece.destinationY, piece.width, piece.height, piece.sourceX, piece.sourceY]
                    .map { Int32(clamping: $0) }
                encoder.setTextures([from, to], range: 0..<2)
                encoder.setBytes(parameters, length: parameters.count * MemoryLayout<Int32>.stride, index: 0)
                encoder.setBytes(&alpha, length: MemoryLayout<Float>.size, index: 1)
                encoder.dispatchThreadgroups(
                    MTLSize(width: (piece.width + group.width - 1) / group.width,
                            height: (piece.height + group.height - 1) / group.height, depth: 1),
                    threadsPerThreadgroup: group)
            }
        }
        encoder.endEncoding()
        #if os(macOS)
        let managed = targets.values.filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else {
                throw RenderError.deviceLost("batched composite: no blit encoder on \(device.name)")
            }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commitUnwaited(commands, label: "batched composite")
    }

    /// Commits `commands` with no wait and keeps it as `lastUnwaited`; call with the lock held. A GPU failure
    /// fails the backend when the buffer completes. The handler runs on Metal's thread; `fail` takes the lock,
    /// which a readback may hold while it waits on a later buffer, so it goes to another queue rather than
    /// block Metal's completion delivery.
    private func commitUnwaited(_ commands: any MTLCommandBuffer, label: String) {
        commands.addCompletedHandler { [self] done in
            guard let reason = Self.commandBufferFailure(status: done.status, error: done.error, label: label) else { return }
            DispatchQueue.global().async { self.fail(reason) }
        }
        commands.commit()
        lastUnwaited = commands
    }
}
#endif
