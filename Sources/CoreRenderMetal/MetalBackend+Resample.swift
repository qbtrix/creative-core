// MetalBackend+Resample.swift: resampling (MB-8) as two separable GPU passes of ResampleTable over float4 image
// buffers in the CPU's pass order, scattered into a new surface. Invariants: `unsupported(.resample)` while the
// backend is unhealthy; an invalid size throws the CPU's error first; a valid size whose largest real buffer
// (`ResampleTable.peakPixels`) is over `maxBufferLength` throws `unsupported(.resample)` without failing the backend,
// so the caller resamples on the CPU backend; the lock is free across the GPU wait; a failed command buffer or
// allocation marks the backend failed and throws `deviceLost`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `s` resampled to `width` x `height` with `filter`, as a new surface. Throws `unsupported(.resample)` while
    /// unhealthy or when a buffer would exceed this GPU's `maxBufferLength` (resample on the CPU backend instead).
    func resample(_ s: RenderSurface, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface {
        let (image, clock, queue, pass, scatter) = try withLock {
            () throws -> (PixelBuffer, UInt64, any MTLCommandQueue, any MTLComputePipelineState, any MTLComputePipelineState) in
            guard state.effectiveSupports.contains(.resample) else { throw RenderError.unsupported(.resample) }
            let stored = try lookup(s)
            _ = try RenderError.mapping { try PixelBuffer.validatedSize(width: width, height: height) }
            let clock = tick()
            stored.touch(clock)
            return (try stored.read(), clock, commandQueue,
                    try pipelines.pipeline(for: ResampleShader.pass, source: ResampleShader.source),
                    try pipelines.pipeline(for: ResampleShader.scatter, source: ResampleShader.source))
        }
        let (w, h) = (image.width, image.height)
        let across = try ResampleTable(length: w, newLength: width, filter: filter)
        let down = try ResampleTable(length: h, newLength: height, filter: filter)
        // A valid size whose largest buffer exceeds this GPU's limit is a device limit, not bad input.
        guard ResampleTable.peakPixels(width: w, height: h, newWidth: width, newHeight: height) <= device.maxBufferLength / 16 else {
            throw RenderError.unsupported(.resample)
        }
        let input = try floatBuffer(w * h)
        let floats = input.contents().bindMemory(to: Float.self, capacity: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let (p, base) = (try RenderError.mapping { try image.pixel(x: x, y: y) }, (y * w + x) * 4)
                (floats[base], floats[base + 1], floats[base + 2], floats[base + 3]) = (p.r, p.g, p.b, p.a)
            }
        }
        let output: MetalSurface
        do { output = try MetalSurface(device: device, buffer: PixelBuffer(width: width, height: height), clock: clock) } catch RenderError.deviceLost(let reason) { throw resampleLost(reason) }
        guard let commands = queue.makeCommandBuffer() else { throw resampleLost("resample: no command buffer on \(device.name)") }
        // The CPU's order: the pass that leaves the smaller intermediate runs first.
        let last: any MTLBuffer
        if width * h <= w * height {
            let mid = try self.pass(across, lines: h, src: (1, w), dst: (1, width), from: input, commands, pass)
            last = try self.pass(down, lines: width, src: (width, 1), dst: (width, 1), from: mid, commands, pass)
        } else {
            let mid = try self.pass(down, lines: w, src: (w, 1), dst: (w, 1), from: input, commands, pass)
            last = try self.pass(across, lines: height, src: (1, w), dst: (1, width), from: mid, commands, pass)
        }
        try encode(commands, scatter) { encoder, group in
            encoder.setBuffer(last, offset: 0, index: 0)
            for index in 0..<output.tiling.tileCount {
                let rect = try output.tiling.rect(index)
                guard let tile = output.tiles[index] else { throw RenderError.raster("resample: output tile \(index) is missing") }
                encoder.setTexture(tile, index: 0)
                Self.setInts([rect.x, rect.y, rect.width, rect.height, width], encoder, index: 1)
                encoder.dispatchThreadgroups(Self.grid(rect.width, rect.height, group), threadsPerThreadgroup: group)
            }
        }
        #if os(macOS)
        // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
        let managed = output.tiles.compactMap { $0 }.filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw resampleLost("resample: no blit encoder on \(device.name)") }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "resample")
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: width, height: height)
    }

    /// Encodes one `resample_pass` of `table` over `lines` lines into a new buffer, or returns `input` when
    /// the axis keeps its length (the CPU skips that pass). `src`/`dst`: pixel steps along and across a line.
    private func pass(_ table: ResampleTable, lines: Int, src: (Int, Int), dst: (Int, Int), from input: any MTLBuffer,
                      _ commands: any MTLCommandBuffer, _ pipeline: any MTLComputePipelineState) throws -> any MTLBuffer {
        if table.isIdentity { return input }
        let output = try floatBuffer(lines * table.newLength)
        let tables = try [bytesBuffer(table.offsets), bytesBuffer(table.indices), bytesBuffer(table.weights)]
        try encode(commands, pipeline) { encoder, group in
            encoder.setBuffer(input, offset: 0, index: 0)
            encoder.setBuffer(output, offset: 0, index: 1)
            for (index, buffer) in tables.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index + 2) }
            Self.setInts([lines, table.newLength, src.0, src.1, dst.0, dst.1], encoder, index: 5)
            encoder.dispatchThreadgroups(Self.grid(table.newLength, lines, group), threadsPerThreadgroup: group)
        }
        return output
    }

    /// Runs `body` in a new compute encoder on `commands` with `pipeline` set and its threadgroup size.
    private func encode(_ commands: any MTLCommandBuffer, _ pipeline: any MTLComputePipelineState,
                        _ body: (any MTLComputeCommandEncoder, MTLSize) throws -> Void) throws {
        guard let encoder = commands.makeComputeCommandEncoder() else { throw resampleLost("resample: no compute encoder on \(device.name)") }
        encoder.setComputePipelineState(pipeline)
        let width = max(pipeline.threadExecutionWidth, 1), height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        defer { encoder.endEncoding() }
        try body(encoder, MTLSize(width: width, height: height, depth: 1))
    }

    /// A zeroed shared buffer of `pixels` float4s.
    private func floatBuffer(_ pixels: Int) throws -> any MTLBuffer {
        guard let buffer = device.makeBuffer(length: pixels * 16, options: .storageModeShared) else {
            throw resampleLost("resample: buffer allocation failed for \(pixels) pixels")
        }
        return buffer
    }

    /// A shared buffer holding `values` (never empty: a table has at least one tap and one offset).
    private func bytesBuffer<T>(_ values: [T]) throws -> any MTLBuffer {
        let made = values.withUnsafeBytes { raw -> (any MTLBuffer)? in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }
        guard let made else { throw resampleLost("resample: table buffer allocation failed") }
        return made
    }

    /// Sets `values` as Int32s (clamped) at buffer `index`.
    private static func setInts(_ values: [Int], _ encoder: any MTLComputeCommandEncoder, index: Int) {
        values.map { Int32(clamping: $0) }.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: index) }
        }
    }

    /// Threadgroups of `group` covering `width` x `height` threads, rounded up.
    private static func grid(_ width: Int, _ height: Int, _ group: MTLSize) -> MTLSize {
        MTLSize(width: (width + group.width - 1) / group.width, height: (height + group.height - 1) / group.height, depth: 1)
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func resampleLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
