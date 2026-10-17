// MetalBackend+Blur.swift: Gaussian blur (MB-11) as two separable GPU passes of BlurTable over whole-image float4
// buffers in the CPU's order (across, then down) with clamp-to-edge taps, scattered into a new surface by the
// resample scatter kernel. Invariants: an invalid sigma throws the CPU backend's exact error before any GPU work;
// sigma 0 returns a new surface of the source's pixels unchanged; an image over `maxBufferLength` throws `raster`
// without failing the backend; the source is unchanged; the lock is free across the GPU wait; a failed command
// buffer or allocation marks the backend failed and throws `deviceLost`. `.blur` stays out of `supports` until MB-12.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `s` blurred by a Gaussian of `sigma` pixels, as `CPUBackend.gaussianBlur` does, as a new surface.
    func blur(_ s: RenderSurface, sigma: Double) throws -> RenderSurface {
        let (image, clock, queue) = try withLock { () throws -> (PixelBuffer, UInt64, any MTLCommandQueue) in
            guard state.healthy else { throw RenderError.deviceLost(state.lastError ?? "backend unhealthy") }
            let stored = try lookup(s)
            let clock = tick()
            stored.touch(clock)
            return (try stored.read(), clock, commandQueue)
        }
        let (w, h) = (image.width, image.height)
        let table = try BlurTable(sigma: sigma, width: w, height: h)
        if table.isIdentity { return try blurStore(blurAllocate { try MetalSurface(device: device, buffer: image, clock: clock) }, w, h) }
        guard w * h * 16 <= device.maxBufferLength else {
            throw RenderError.raster("blur: \(w)x\(h) needs buffers over \(device.maxBufferLength) bytes")
        }
        let (pass, scatter) = try withLock { () throws -> (any MTLComputePipelineState, any MTLComputePipelineState) in
            (try pipelines.pipeline(for: BlurShader.pass, source: BlurShader.source),
             try pipelines.pipeline(for: ResampleShader.scatter, source: ResampleShader.source))
        }
        var pixels = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = try RenderError.mapping { try image.pixel(x: x, y: y) }
                let at = (y * w + x) * 4
                pixels[at] = p.r; pixels[at + 1] = p.g; pixels[at + 2] = p.b; pixels[at + 3] = p.a
            }
        }
        let first = try blurBuffer(pixels), second = try blurBuffer([Float](repeating: 0, count: w * h * 4))
        let weights = try blurBuffer(table.weights)
        let output = try blurAllocate { try MetalSurface(device: device, buffer: PixelBuffer(width: w, height: h), clock: clock) }
        guard let commands = queue.makeCommandBuffer() else { throw blurLost("blur: no command buffer on \(device.name)") }
        // Across each row into `second`, then down each column back into `first`, as CoreRaster runs them.
        let passes: [(any MTLBuffer, any MTLBuffer, [Int])] = [(first, second, [h, w, table.radius, 1, w]),
                                                               (second, first, [w, h, table.radius, w, 1])]
        for (from, to, ints) in passes {
            try blurEncode(commands, pass, ints, at: 3, width: ints[1], height: ints[0]) { encoder in
                encoder.setBuffer(from, offset: 0, index: 0)
                encoder.setBuffer(to, offset: 0, index: 1)
                encoder.setBuffer(weights, offset: 0, index: 2)
            }
        }
        for index in 0..<output.tiling.tileCount {
            let rect = try output.tiling.rect(index)
            guard let tile = output.tiles[index] else { throw RenderError.raster("blur: output tile \(index) is missing") }
            try blurEncode(commands, scatter, [rect.x, rect.y, rect.width, rect.height, w], at: 1, width: rect.width, height: rect.height) { encoder in
                encoder.setBuffer(first, offset: 0, index: 0)
                encoder.setTexture(tile, index: 0)
            }
        }
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        if output.tiles.contains(where: { $0?.storageMode == .managed }) {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw blurLost("blur: no blit encoder on \(device.name)") }
            for case let tile? in output.tiles where tile.storageMode == .managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "blur")
        return try blurStore(output, w, h)
    }

    /// Encodes `pipeline` over `width` x `height` threads with `ints` as Int32s (clamped) at buffer `intsIndex`
    /// (3 for a pass, 1 for the scatter) and whatever `bind` sets.
    private func blurEncode(_ commands: any MTLCommandBuffer, _ pipeline: any MTLComputePipelineState, _ ints: [Int],
                            at intsIndex: Int, width: Int, height: Int, bind: (any MTLComputeCommandEncoder) -> Void) throws {
        guard let encoder = commands.makeComputeCommandEncoder() else { throw blurLost("blur: no compute encoder on \(device.name)") }
        encoder.setComputePipelineState(pipeline)
        bind(encoder)
        let values = ints.map { Int32(clamping: $0) }
        values.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: intsIndex) }
        }
        let gx = max(pipeline.threadExecutionWidth, 1), gy = max(pipeline.maxTotalThreadsPerThreadgroup / gx, 1)
        encoder.dispatchThreadgroups(MTLSize(width: (width + gx - 1) / gx, height: (height + gy - 1) / gy, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: gx, height: gy, depth: 1))
        encoder.endEncoding()
    }

    /// A shared buffer holding `values` (never empty here).
    private func blurBuffer(_ values: [Float]) throws -> any MTLBuffer {
        let made = values.withUnsafeBytes { raw -> (any MTLBuffer)? in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }
        guard let made else { throw blurLost("blur: buffer allocation failed for \(values.count) floats") }
        return made
    }

    /// Stores `output` under a new id, enforces the budget and returns its handle.
    private func blurStore(_ output: MetalSurface, _ width: Int, _ height: Int) throws -> RenderSurface {
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: width, height: height)
    }

    /// `body`'s surface; a texture allocation failure inside it marks the backend failed, as `surface` does.
    private func blurAllocate(_ body: () throws -> MetalSurface) throws -> MetalSurface {
        do { return try body() } catch RenderError.deviceLost(let reason) { throw blurLost(reason) }
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func blurLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
