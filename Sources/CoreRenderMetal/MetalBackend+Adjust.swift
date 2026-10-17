// MetalBackend+Adjust.swift: every `ToneAdjustment` (exposure, levels, curves: MB-13; white balance, contrast,
// highlights/shadows: MB-14) through `adjust_tone` (Shaders/AdjustShader.swift), tile by tile into a new surface
// of the same tiling, reading AdjustTable's gains or table. Invariants: `unsupported(.adjust)` while unhealthy;
// invalid parameters throw the CPU backend's error before any GPU work; an evicted source tile is read from its
// shadow through a temporary texture; the source is unchanged; the lock is free across the GPU wait; a failed
// command buffer or allocation marks the backend failed.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `s` with `adjustment` applied on unpremultiplied values, as `CPUBackend.adjusted` does, as a new surface.
    func adjust(_ s: RenderSurface, _ adjustment: ToneAdjustment) throws -> RenderSurface {
        let (tiling, sources, clock, queue) = try withLock {
            () throws -> (SurfaceTiling, [AdjustSource], UInt64, any MTLCommandQueue) in
            guard state.effectiveSupports.contains(.adjust) else { throw RenderError.unsupported(.adjust) }
            let stored = try lookup(s)
            let clock = tick()
            stored.touch(clock)
            let sources = try (0..<stored.tiling.tileCount).map { index -> AdjustSource in
                if let tile = stored.tiles[index] { return .texture(tile) }
                guard let shadow = stored.shadows[index] else { throw RenderError.raster("adjust: tile \(index) has neither a texture nor a shadow") }
                return .shadow(shadow)
            }
            return (stored.tiling, sources, clock, commandQueue)
        }
        let table = try AdjustTable(adjustment)
        let pipeline = try withLock { try pipelines.pipeline(for: AdjustShader.key, source: AdjustShader.source) }
        let inputs = try sources.map { source -> any MTLTexture in
            switch source {
            case .texture(let texture): return texture
            case .shadow(let shadow): // A one-tile surface never stored: its texture lives as long as this op.
                guard let texture = try adjustAllocate({ try MetalSurface(device: device, buffer: shadow, clock: 0) }).tiles.first ?? nil
                else { throw RenderError.raster("adjust: empty staged tile") }
                return texture
            }
        }
        let output = try adjustAllocate {
            try MetalSurface(device: device, buffer: PixelBuffer(width: tiling.width, height: tiling.height), clock: clock)
        }
        let values = table.values.isEmpty ? [Float(0)] : table.values
        let made = values.withUnsafeBytes { raw -> (any MTLBuffer)? in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }
        guard let tableBuffer = made else { throw adjustLost("adjust: no table buffer on \(device.name)") }
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw adjustLost("adjust: no command buffer or compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(tableBuffer, offset: 0, index: 0)
        let luma = AdjustTable.lumaWeights
        var params = AdjustParams(gainR: table.gains.x, gainG: table.gains.y, gainB: table.gains.z,
                                  below: table.below, above: table.above, lumaR: luma.x, lumaG: luma.y, lumaB: luma.z,
                                  n: UInt32(clamping: max(table.values.count - 1, 0)), kind: table.kind.rawValue)
        encoder.setBytes(&params, length: MemoryLayout<AdjustParams>.stride, index: 1)
        let width = max(pipeline.threadExecutionWidth, 1), height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            guard index < inputs.count, let tile = output.tiles[index] else { throw RenderError.raster("adjust: tile \(index) is missing") }
            encoder.setTexture(inputs[index], index: 0)
            encoder.setTexture(tile, index: 1)
            encoder.dispatchThreadgroups(
                MTLSize(width: (rect.width + width - 1) / width, height: (rect.height + height - 1) / height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        }
        encoder.endEncoding()
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        let managed = output.tiles.compactMap { $0 }.filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw adjustLost("adjust: no blit encoder on \(device.name)") }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "adjust")
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: tiling.width, height: tiling.height)
    }

    /// `body`'s surface; a texture allocation failure inside it marks the backend failed, as `surface` does.
    private func adjustAllocate(_ body: () throws -> MetalSurface) throws -> MetalSurface {
        do { return try body() } catch RenderError.deviceLost(let reason) { throw adjustLost(reason) }
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func adjustLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}

/// A source tile while an adjustment runs: its resident texture, or its shadow (uploaded to a temporary texture).
private enum AdjustSource { case texture(any MTLTexture), shadow(PixelBuffer) }

/// `AdjustParams` of AdjustShader.swift: ten 4-byte fields, 40 bytes in both languages.
private struct AdjustParams {
    var gainR: Float
    var gainG: Float
    var gainB: Float
    var below: Float
    var above: Float
    var lumaR: Float
    var lumaG: Float
    var lumaB: Float
    var n: UInt32
    var kind: UInt32
}
#endif
