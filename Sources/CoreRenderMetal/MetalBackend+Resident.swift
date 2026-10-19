// MetalBackend+Resident.swift: the Metal side of resident rendering. `blank` makes a clear tiled surface
// with no conversion, and the batched `composite(_:onto:)` encodes every step's tile pieces, through each
// mode's kernel (MetalBackend+Composite.swift's), into one command buffer committed with no wait, so a frame
// that composites three layers over a region and then displays them waits on the GPU once, in the display.
// Invariants: every step's family is checked, and every surface looked up, before anything changes; a step
// whose surface is the backdrop runs the steps one at a time through `compositeInPlace`, which reads such a
// source from a snapshot; evicted source tiles are staged from their shadows, evicted backdrop tiles restored
// to textures under the lock; the command buffer is committed under the lock, so every later op on the
// queue (a display, a `read`, an eviction's readback blit) is ordered after these writes by the tiles' hazard
// tracking; a GPU failure is recorded from the completion handler (backend failed, nothing thrown); `recover`
// waits for the last one before it swaps queues; the budget holds after on every exit; dispatches in the one
// serial compute encoder run in step order, so later steps blend over earlier.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// A clear `width` x `height` surface: tiles filled from zeros, no Float32 buffer or conversion. Then
    /// evicts as `surface(_:)` does. Throws `RenderError.raster` for a size the tiling rejects and
    /// `deviceLost` (backend failed) when a texture will not allocate.
    public func blank(width: Int, height: Int) throws -> RenderSurface {
        let clock = withLock { tick() }
        let stored: MetalSurface
        do {
            stored = try MetalSurface(device: device, width: width, height: height, clock: clock)
        } catch RenderError.deviceLost(let reason) {
            fail(reason)
            throw RenderError.deviceLost(reason)
        }
        let id = UUID()
        withLock { surfaces[id] = stored }
        evictIfNeeded()
        return handle(id: id, width: width, height: height)
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
        // The handler runs on Metal's thread; `fail` takes the lock, which a readback may hold while it waits
        // on a later buffer, so it goes to another queue rather than block Metal's completion delivery.
        commands.addCompletedHandler { [self] done in
            guard let reason = Self.commandBufferFailure(status: done.status, error: done.error, label: "batched composite")
            else { return }
            DispatchQueue.global().async { self.fail(reason) }
        }
        commands.commit()
        lastUnwaited = commands
    }
}
#endif
