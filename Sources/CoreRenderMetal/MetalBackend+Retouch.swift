// MetalBackend+Retouch.swift: clone through a mask (MB-15) on the GPU. The source is read like `read` (resident
// tiles merged with the shadows of evicted ones), packed with the mask's coverage into whole-image buffers, and
// `retouch_clone` (Shaders/RetouchShader.swift) writes each tile of a new surface. Invariants: `unsupported(.retouch)`
// while unhealthy, then `surfaceMismatch`, then CoreRaster's mask-size error, in the CPU backend's order; an offset
// whose every source is off the image returns a new surface of the pixels unchanged with no GPU work, and past that
// guard |dx| < width and |dy| < height; an image whose buffers exceed `maxBufferLength` throws `unsupported(.retouch)`
// without failing the backend (clone on the CPU backend); the source is unchanged; the lock is free across the GPU
// wait; a failed command buffer or allocation marks the backend failed and throws `deviceLost`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `s` with each pixel replaced by the one `offset` away, mixed by `mask`'s coverage, as `CPUBackend.cloned`.
    func clone(_ s: RenderSurface, offset: (dx: Int, dy: Int), through mask: Mask) throws -> RenderSurface {
        let (image, clock, queue) = try withLock { () throws -> (PixelBuffer, UInt64, any MTLCommandQueue) in
            guard state.effectiveSupports.contains(.retouch) else { throw RenderError.unsupported(.retouch) }
            let stored = try lookup(s)
            let clock = tick()
            stored.touch(clock)
            return (try stored.read(), clock, commandQueue)
        }
        let (w, h, dx, dy) = (image.width, image.height, offset.dx, offset.dy)
        // CoreRaster's own size check and message: with dx == width every source is off the image, so `cloned`
        // checks the mask and returns at once without touching a pixel.
        _ = try RenderError.mapping { try image.cloned(offset: (dx: w, dy: 0), through: mask) }
        guard dx > -w, dx < w, dy > -h, dy < h else {
            return try retouchStore(retouchAllocate { try MetalSurface(device: device, buffer: image, clock: clock) })
        }
        guard w * h * 16 <= device.maxBufferLength, w <= Int(Int32.max), h <= Int(Int32.max) else {
            throw RenderError.unsupported(.retouch)
        }
        let pipeline = try withLock { try pipelines.pipeline(for: RetouchShader.key, source: RetouchShader.source) }
        guard let pixels = device.makeBuffer(length: w * h * 16, options: .storageModeShared),
              let coverage = device.makeBuffer(length: w * h * 4, options: .storageModeShared) else {
            throw retouchLost("retouch: buffer allocation failed for \(w)x\(h)")
        }
        let rgba = pixels.contents().bindMemory(to: Float.self, capacity: w * h * 4)
        let cover = coverage.contents().bindMemory(to: Float.self, capacity: w * h)
        try RenderError.mapping {
            for y in 0..<h {
                for x in 0..<w {
                    let at = y * w + x, p = try image.pixel(x: x, y: y)
                    cover[at] = try mask.coverage(x: x, y: y)
                    (rgba[at * 4], rgba[at * 4 + 1], rgba[at * 4 + 2], rgba[at * 4 + 3]) = (p.r, p.g, p.b, p.a)
                }
            }
        }
        let output = try retouchAllocate { try MetalSurface(device: device, buffer: PixelBuffer(width: w, height: h), clock: clock) }
        guard let work = queue.makeCommandBuffer(), let encoder = work.makeComputeCommandEncoder() else {
            throw retouchLost("retouch: no command buffer or compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(pixels, offset: 0, index: 0)
        encoder.setBuffer(coverage, offset: 0, index: 1)
        let gx = max(pipeline.threadExecutionWidth, 1), gy = max(pipeline.maxTotalThreadsPerThreadgroup / gx, 1)
        for index in 0..<output.tiling.tileCount {
            let rect = try output.tiling.rect(index)
            guard let tile = output.tiles[index] else { throw RenderError.raster("retouch: output tile \(index) is missing") }
            encoder.setTexture(tile, index: 0)
            [rect.x, rect.y, rect.width, rect.height, w, h, dx, dy].map { Int32(clamping: $0) }.withUnsafeBytes { raw in
                if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: 2) }
            }
            encoder.dispatchThreadgroups(MTLSize(width: (rect.width + gx - 1) / gx, height: (rect.height + gy - 1) / gy, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: gx, height: gy, depth: 1))
        }
        encoder.endEncoding()
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        if output.tiles.contains(where: { $0?.storageMode == .managed }) {
            guard let blitter = work.makeBlitCommandEncoder() else { throw retouchLost("retouch: no blit encoder on \(device.name)") }
            for case let tile? in output.tiles where tile.storageMode == .managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        work.commit()
        work.waitUntilCompleted()
        try recordCompletion(status: work.status, error: work.error, label: "retouch")
        return try retouchStore(output)
    }

    /// Stores `output` under a new id, enforces the budget and returns its handle.
    private func retouchStore(_ output: MetalSurface) throws -> RenderSurface {
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: output.tiling.width, height: output.tiling.height)
    }

    /// `body`'s surface; a texture allocation failure inside it marks the backend failed, as `surface` does.
    private func retouchAllocate(_ body: () throws -> MetalSurface) throws -> MetalSurface {
        do { return try body() } catch RenderError.deviceLost(let reason) { throw retouchLost(reason) }
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func retouchLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
