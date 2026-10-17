// MetalBackend+Unsharp.swift: unsharp mask (MB-12) in one command buffer on whole-image float4 buffers: `blur_pass`
// across, then `blur_unsharp` down plus UnsharpRule per premultiplied component, scattered into a new surface.
// Invariants: `unsupported(.blur)` while unhealthy; invalid parameters throw the CPU's exact error, in its order,
// before GPU work; a non-finite result throws the CPU's overflow error and stores nothing; a valid image whose
// w x h x 16 bytes are over `maxBufferLength` throws `unsupported(.blur)` without failing the backend (a device
// limit, not bad input: sharpen it on the CPU backend), as resample does; the lock is free across the GPU wait; a failed command buffer or
// allocation marks the backend failed and throws `deviceLost`.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `s` sharpened as `CPUBackend.unsharpMask` does, as a new surface. Throws `unsupported(.blur)` while unhealthy
    /// or, after the parameter checks, when a whole-image buffer would exceed this GPU's `maxBufferLength` (sharpen
    /// on the CPU backend instead). `bufferLimit`, for tests, stands in for `maxBufferLength` when set.
    package func unsharp(_ s: RenderSurface, amount: Double, sigma: Double, threshold: Double,
                         bufferLimit: Int? = nil) throws -> RenderSurface {
        let (image, clock, queue) = try withLock { () throws -> (PixelBuffer, UInt64, any MTLCommandQueue) in
            guard state.effectiveSupports.contains(.blur) else { throw RenderError.unsupported(.blur) }
            let found = (surface: try lookup(s), now: tick())
            found.surface.touch(found.now)
            return (try found.surface.read(), found.now, commandQueue)
        }
        let rule = try UnsharpRule(amount: amount, threshold: threshold)
        let (w, h) = (image.width, image.height)
        let table = try BlurTable(sigma: sigma, width: w, height: h)
        // A valid image whose buffers exceed this GPU's limit is a device limit, not bad input.
        guard SurfaceTiling.wholeImageFits(width: w, height: h, bytesPerPixel: 16,
                                          maxBufferLength: bufferLimit ?? device.maxBufferLength) else {
            throw RenderError.unsupported(.blur)
        }
        let (pass, mask, scatter) = try withLock {
            () throws -> (any MTLComputePipelineState, any MTLComputePipelineState, any MTLComputePipelineState) in
            (try pipelines.pipeline(for: BlurShader.pass, source: BlurShader.source),
             try pipelines.pipeline(for: UnsharpShader.mask, source: UnsharpShader.source),
             try pipelines.pipeline(for: ResampleShader.scatter, source: ResampleShader.source))
        }
        let (src, across, out) = (try unsharpBuffer(w * h * 16), try unsharpBuffer(w * h * 16), try unsharpBuffer(w * h * 16))
        let floats = src.contents().bindMemory(to: Float.self, capacity: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let (p, at) = (try RenderError.mapping { try image.pixel(x: x, y: y) }, (y * w + x) * 4)
            (floats[at], floats[at + 1], floats[at + 2], floats[at + 3]) = (p.r, p.g, p.b, p.a)
        } }
        let weights = try unsharpBuffer(table.weights.count * 4)
        let tableFloats = weights.contents().bindMemory(to: Float.self, capacity: table.weights.count)
        for (k, weight) in table.weights.enumerated() { tableFloats[k] = weight }
        let output: MetalSurface
        do { output = try MetalSurface(device: device, buffer: PixelBuffer(width: w, height: h), clock: clock) } catch RenderError.deviceLost(let reason) { throw unsharpLost(reason) }
        guard let commands = queue.makeCommandBuffer() else { throw unsharpLost("unsharp: no command buffer on \(device.name)") }
        try unsharpEncode(commands, pass, w, h) { encoder in
            for (index, buffer) in [src, across, weights].enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
            Self.unsharpBytes([h, w, table.radius, 1, w].map { Int32(clamping: $0) }, encoder, index: 3)
        }
        try unsharpEncode(commands, mask, w, h) { encoder in
            for (index, buffer) in [src, across, out, weights].enumerated() { encoder.setBuffer(buffer, offset: 0, index: index) }
            Self.unsharpBytes([w, h, table.radius].map { Int32(clamping: $0) }, encoder, index: 4)
            Self.unsharpBytes(rule.parameters, encoder, index: 5)
        }
        var managed: [any MTLTexture] = []
        for index in 0..<output.tiling.tileCount {
            guard let tile = output.tiles[index] else { throw RenderError.raster("unsharp: output tile \(index) is missing") }
            let rect = try output.tiling.rect(index)
            #if os(macOS)
            if tile.storageMode == .managed { managed.append(tile) }
            #endif
            try unsharpEncode(commands, scatter, rect.width, rect.height) { encoder in
                encoder.setTexture(tile, index: 0)
                encoder.setBuffer(out, offset: 0, index: 0)
                Self.unsharpBytes([rect.x, rect.y, rect.width, rect.height, w].map { Int32(clamping: $0) }, encoder, index: 1)
            }
        }
        if !managed.isEmpty {
            // A managed tile's CPU copy is stale after GPU writes until synchronized; `read` uses `getBytes`.
            guard let blitter = commands.makeBlitCommandEncoder() else { throw unsharpLost("unsharp: no blit encoder on \(device.name)") }
            managed.forEach { blitter.synchronize(resource: $0) }
            blitter.endEncoding()
        }
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "unsharp")
        try rule.check(UnsafeBufferPointer(start: out.contents().bindMemory(to: Float.self, capacity: w * h * 4), count: w * h * 4))
        let id = UUID()
        withLock { surfaces[id] = output }
        evictIfNeeded()
        return handle(id: id, width: w, height: h)
    }

    /// Encodes `pipeline` over `width` x `height` threads, rounded up to whole threadgroups, with what `bind` sets.
    private func unsharpEncode(_ commands: any MTLCommandBuffer, _ pipeline: any MTLComputePipelineState,
                               _ width: Int, _ height: Int, bind: (any MTLComputeCommandEncoder) -> Void) throws {
        let across = max(pipeline.threadExecutionWidth, 1)
        let group = MTLSize(width: across, height: max(pipeline.maxTotalThreadsPerThreadgroup / across, 1), depth: 1)
        let grid = MTLSize(width: (width + group.width - 1) / group.width, height: (height + group.height - 1) / group.height, depth: 1)
        guard let encoder = commands.makeComputeCommandEncoder() else { throw unsharpLost("unsharp: no compute encoder on \(device.name)") }
        encoder.setComputePipelineState(pipeline)
        bind(encoder)
        encoder.dispatchThreadgroups(grid, threadsPerThreadgroup: group)
        encoder.endEncoding()
    }

    /// Sets `values` (4-byte scalars, under 4 KB) at buffer `index`.
    private static func unsharpBytes<T>(_ values: [T], _ encoder: any MTLComputeCommandEncoder, index: Int) {
        values.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: index) }
        }
    }

    /// A zeroed shared buffer of `bytes` bytes.
    private func unsharpBuffer(_ bytes: Int) throws -> any MTLBuffer {
        guard let buffer = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            throw unsharpLost("unsharp: buffer allocation failed for \(bytes) bytes")
        }
        return buffer
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func unsharpLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
