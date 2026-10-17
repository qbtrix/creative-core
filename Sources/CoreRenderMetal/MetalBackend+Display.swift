// MetalBackend+Display.swift: the display encode (metal-backend MB-3). Resident tiles go through
// `display_encode` (Shaders/DisplayShader.swift), one dispatch per tile in one command buffer, into one
// shared byte buffer; evicted tiles encode from their shadows with `PixelBuffer.rgba8`, the CPU path.
// The lock covers lookup, use stamp, tiles and pipeline (compiled on first use), not the GPU wait. Errors
// follow the CPU's order (surface, then space); an output over `maxBufferLength` is a device limit, so it
// throws `unsupported(.display)` without failing the backend, and only a nil buffer within it is `lost`.
#if canImport(Metal)
import CoreColor
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `surface` as straight-alpha bytes in `colorSpace`. Throws, in this order: `unsupported(.display)` while
    /// the backend is unhealthy, `surfaceMismatch`, the CPU backend's `RenderError.raster` for a non-display
    /// space, `unsupported(.display)` (backend still healthy) when the bytes exceed `maxBufferLength`, or
    /// `deviceLost` (backend failed) when the GPU work cannot run or fails.
    func encodeDisplay(_ surface: RenderSurface, colorSpace: ColorSpace) throws -> [UInt8] {
        let (tiling, tiles, shadows, pipeline, queue) = try withLock {
            guard state.effectiveSupports.contains(.display) else { throw RenderError.unsupported(.display) }
            let stored = try lookup(surface)
            stored.touch(tick())
            let pipeline = try pipelines.pipeline(for: DisplayShader.key, source: DisplayShader.source)
            return (stored.tiling, stored.tiles, stored.shadows, pipeline, commandQueue)
        }
        // After the lookup, as the CPU backend checks the surface before the space; the same error text.
        let table = try DisplayTable(colorSpace)
        guard DisplayTable.outputFits(width: tiling.width, height: tiling.height, maxBufferLength: device.maxBufferLength) else {
            throw RenderError.unsupported(.display)
        }
        guard tiles.count == tiling.tileCount, shadows.count == tiling.tileCount else {
            throw RenderError.raster("display: \(tiles.count) tiles and \(shadows.count) shadows for \(tiling.tileCount)")
        }
        let count = tiling.width * tiling.height * 4
        guard let output = device.makeBuffer(length: max(count, 1), options: .storageModeShared) else {
            throw lost("display: no \(count)-byte buffer on \(device.name)")
        }
        var resident: [(texture: any MTLTexture, rect: TileRect)] = []
        for index in 0..<tiling.tileCount {
            if let texture = tiles[index] { resident.append((texture, try tiling.rect(index))) }
        }
        if !resident.isEmpty {
            try encodeTiles(resident, table: table, imageWidth: tiling.width, into: output, pipeline: pipeline, queue: queue)
        }
        var bytes = Array(UnsafeBufferPointer(start: output.contents().bindMemory(to: UInt8.self, capacity: count), count: count))
        for index in 0..<tiling.tileCount where tiles[index] == nil {
            let rect = try tiling.rect(index)
            guard let shadow = shadows[index], shadow.width == rect.width, shadow.height == rect.height else {
                throw RenderError.raster("display: tile \(index) has neither a texture nor a matching shadow")
            }
            let encoded = try RenderError.mapping { try shadow.rgba8(colorSpace: colorSpace) }
            let row = rect.width * 4
            for y in 0..<rect.height {
                let to = ((rect.y + y) * tiling.width + rect.x) * 4
                bytes.replaceSubrange(to..<(to + row), with: encoded[(y * row)..<(y * row + row)])
            }
        }
        return bytes
    }

    /// One `display_encode` dispatch per resident tile, in one command buffer, then a wait with the lock free.
    private func encodeTiles(_ resident: [(texture: any MTLTexture, rect: TileRect)], table: DisplayTable,
                             imageWidth: Int, into output: any MTLBuffer,
                             pipeline: any MTLComputePipelineState, queue: any MTLCommandQueue) throws {
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw lost("display: no command buffer or compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(output, offset: 0, index: 0)
        Self.setConstants(table.thresholds, on: encoder, index: 1)
        Self.setConstants(table.matrix ?? [1, 0, 0, 0, 1, 0, 0, 0, 1], on: encoder, index: 3)
        let width = max(pipeline.threadExecutionWidth, 1)
        let height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        let p3: UInt32 = table.matrix == nil ? 0 : 1
        for (texture, rect) in resident {
            let params = [UInt32(clamping: rect.x), UInt32(clamping: rect.y), UInt32(clamping: imageWidth), p3]
            Self.setConstants(params, on: encoder, index: 2)
            encoder.setTexture(texture, index: 0)
            encoder.dispatchThreadgroups(
                MTLSize(width: (rect.width + width - 1) / width, height: (rect.height + height - 1) / height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        }
        encoder.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "display")
    }

    /// Binds `values` as a small constant buffer (under 4 KB) at `index`.
    private static func setConstants<T>(_ values: [T], on encoder: any MTLComputeCommandEncoder, index: Int) {
        values.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: index) }
        }
    }

    /// Marks the backend failed with `reason` and returns the `deviceLost` to throw. Call with the lock free.
    private func lost(_ reason: String) -> RenderError {
        fail(reason)
        return RenderError.deviceLost(reason)
    }
}
#endif
