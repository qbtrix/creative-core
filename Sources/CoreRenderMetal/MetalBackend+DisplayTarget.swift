// MetalBackend+DisplayTarget.swift: the display encode into a texture (resident rendering), so a canvas on
// the GPU shows a surface with no readback: each tile goes through `display_target` (DisplayShader.swift)
// into an 8-bit unorm texture the caller owns (a document texture, or a drawable's), at the surface's
// offset there, as the bytes `display` returns, premultiplied with the CPU's rounding when asked. With a
// non-empty `ToneProgram` the tiles go through `display_tone` (ToneShader.swift) instead, which runs the
// program on each pixel first: a live adjustment is this one pass over the resident picture.
// Invariants: the checks run in `display`'s order (unhealthy, surface, space) and then on the target, all
// before any GPU work; evicted tiles are staged from their shadows, never restored; the lock covers lookup
// and pipeline, not the GPU wait; the call returns once the GPU wrote the texture, so another queue may
// present it straight after. A failed command buffer is `deviceLost` with the backend failed.
#if canImport(Metal)
import CoreColor
import CoreRaster
import CoreRender
import Metal

extension MetalBackend {
    /// Writes `s` in `colorSpace` into `target` with its top-left pixel at (`x`, `y`): the bytes `display`
    /// gives, premultiplied as `(c x a + 127) / 255` when `premultiplied`. `target` is an `.rgba8Unorm` or
    /// `.bgra8Unorm` texture on this backend's device with `.shaderWrite` usage, and the surface must lie
    /// inside it. Throws `unsupported(.display)` while unhealthy, `surfaceMismatch`, `RenderError.raster`
    /// for a non-display space or a target that does not qualify, and `deviceLost` (backend failed) when
    /// the GPU work cannot run or fails. Returns once the GPU is done. A non-empty `tone` is applied to each
    /// pixel before the encode, as `adjusted` with each of its adjustments in turn would.
    public func display(_ s: RenderSurface, into target: any MTLTexture, x: Int, y: Int, colorSpace: ColorSpace,
                        premultiplied: Bool, tone: ToneProgram? = nil) throws {
        let tone = tone.flatMap { $0.isEmpty ? nil : $0 }
        let (tiling, tiles, shadows, pipeline, queue) = try withLock {
            guard state.effectiveSupports.contains(.display) else { throw RenderError.unsupported(.display) }
            let stored = try lookup(s)
            stored.touch(tick())
            let pipeline = tone == nil
                ? try pipelines.pipeline(for: DisplayShader.targetKey, source: DisplayShader.source)
                : try pipelines.pipeline(for: ToneShader.key, source: ToneShader.source)
            return (stored.tiling, stored.tiles, stored.shadows, pipeline, commandQueue)
        }
        let table = try DisplayTable(colorSpace)
        guard target.device === device, [.rgba8Unorm, .bgra8Unorm].contains(target.pixelFormat),
              target.usage.contains(.shaderWrite) else {
            throw RenderError.raster("display target: needs an rgba8Unorm or bgra8Unorm texture on \(device.name) with shaderWrite usage")
        }
        guard x >= 0, y >= 0, x <= target.width - tiling.width, y <= target.height - tiling.height else {
            throw RenderError.raster("display target: \(tiling.width)x\(tiling.height) at (\(x), \(y)) is outside \(target.width)x\(target.height)")
        }
        var sources: [(texture: any MTLTexture, rect: TileRect)] = []
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            if let texture = tiles[index] {
                sources.append((texture, rect))
            } else if let shadow = shadows[index] {
                do { sources.append((try Self.makeTile(shadow, on: device), rect)) } catch RenderError.deviceLost(let reason) {
                    throw targetLost(reason)
                }
            } else {
                throw RenderError.raster("display target: tile \(index) has neither a texture nor a shadow")
            }
        }
        var toneTables: (any MTLBuffer)?
        if let tone {
            let tables = tone.tables.isEmpty ? [Float(0)] : tone.tables
            toneTables = tables.withUnsafeBytes { raw -> (any MTLBuffer)? in
                raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
            }
            if toneTables == nil { throw targetLost("display target: no tone table buffer on \(device.name)") }
        }
        guard let commands = queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw targetLost("display target: no command buffer or compute encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        if let tone {
            let steps = tone.steps.flatMap { [$0.values.x.bitPattern, $0.values.y.bitPattern, $0.values.z.bitPattern,
                                              $0.kind, $0.n, $0.outer, $0.offset] }
            Self.setConstants(steps, on: encoder, index: 4)
            encoder.setBuffer(toneTables, offset: 0, index: 5)
            Self.setConstants([UInt32(clamping: tone.steps.count)], on: encoder, index: 6)
        }
        encoder.setTexture(target, index: 1)
        Self.setConstants(table.thresholds, on: encoder, index: 1)
        Self.setConstants(table.matrix ?? [1, 0, 0, 0, 1, 0, 0, 0, 1], on: encoder, index: 3)
        let width = max(pipeline.threadExecutionWidth, 1)
        let height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        let (p3, premultiply): (UInt32, UInt32) = (table.matrix == nil ? 0 : 1, premultiplied ? 1 : 0)
        for (texture, rect) in sources {
            Self.setConstants([UInt32(clamping: x + rect.x), UInt32(clamping: y + rect.y), premultiply, p3], on: encoder, index: 2)
            encoder.setTexture(texture, index: 0)
            encoder.dispatchThreadgroups(
                MTLSize(width: (rect.width + width - 1) / width, height: (rect.height + height - 1) / height, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
        }
        encoder.endEncoding()
        #if os(macOS)
        if target.storageMode == .managed, let blitter = commands.makeBlitCommandEncoder() {
            blitter.synchronize(resource: target)
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "display target")
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    private func targetLost(_ reason: String) -> RenderError {
        fail(reason)
        return RenderError.deviceLost(reason)
    }
}
#endif
