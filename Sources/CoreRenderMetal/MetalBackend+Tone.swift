// MetalBackend+Tone.swift: `ToneRendering` on Metal: a whole `ToneProgram` through `adjust_program`
// (Shaders/ToneShader.swift), tile by tile into a new surface of the same tiling, in one command buffer.
// Invariants: `unsupported(.adjust)` while unhealthy; the output is allocated from zeros (no Float32 buffer);
// an evicted source tile is read through a temporary texture from its shadow, never restored; the source is
// unchanged; the lock is free across the GPU wait; a failed command buffer or allocation marks the backend failed.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend: ToneRendering {
    public func adjusted(_ s: RenderSurface, tone: ToneProgram) throws -> RenderSurface {
        let (tiling, tiles, shadows, clock, pipeline, queue) = try withLock {
            guard state.effectiveSupports.contains(.adjust) else { throw RenderError.unsupported(.adjust) }
            let stored = try lookup(s)
            let clock = tick()
            stored.touch(clock)
            let pipeline = try pipelines.pipeline(for: ToneShader.adjustKey, source: ToneShader.source)
            return (stored.tiling, stored.tiles, stored.shadows, clock, pipeline, commandQueue)
        }
        let inputs = try (0..<tiling.tileCount).map { index -> any MTLTexture in
            if let tile = tiles[index] { return tile }
            guard let shadow = shadows[index] else { throw RenderError.raster("tone: tile \(index) has neither a texture nor a shadow") }
            do { return try Self.makeTile(shadow, on: device) } catch RenderError.deviceLost(let reason) { throw toneLost(reason) }
        }
        let output: MetalSurface
        do {
            output = try MetalSurface(device: device, width: tiling.width, height: tiling.height, clock: clock)
        } catch RenderError.deviceLost(let reason) {
            throw toneLost(reason)
        }
        let tables = tone.tables.isEmpty ? [Float(0)] : tone.tables
        let made = tables.withUnsafeBytes { raw -> (any MTLBuffer)? in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }
        guard let tableBuffer = made else { throw toneLost("tone: no table buffer on \(device.name)") }
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw toneLost("tone: no command buffer or compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        let steps = tone.steps.flatMap { [$0.values.x.bitPattern, $0.values.y.bitPattern, $0.values.z.bitPattern,
                                          $0.kind, $0.n, $0.outer, $0.offset] }
        Self.setConstants(steps.isEmpty ? [UInt32(0)] : steps, on: encoder, index: 4)
        encoder.setBuffer(tableBuffer, offset: 0, index: 5)
        Self.setConstants([UInt32(clamping: tone.steps.count)], on: encoder, index: 6)
        let width = max(pipeline.threadExecutionWidth, 1), height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            guard let tile = output.tiles[index] else { throw RenderError.raster("tone: tile \(index) is missing") }
            encoder.setTexture(inputs[index], index: 0)
            encoder.setTexture(tile, index: 1)
            encoder.dispatchThreadgroups(
                MTLSize(width: (rect.width + width - 1) / width, height: (rect.height + height - 1) / height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        }
        encoder.endEncoding()
        #if os(macOS)
        let managed = output.tiles.compactMap { $0 }.filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw toneLost("tone: no blit encoder on \(device.name)") }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "tone")
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: tiling.width, height: tiling.height)
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func toneLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
