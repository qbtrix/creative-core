// MetalBackend+Distance.swift: the GPU halves of a layer style (layer-style-engine LE-8) that later ops build on:
// the jump-flood distance field and the three-pass box blur, over whole-image buffers so the style encode (LE-9)
// can run them in its own command buffer. The field seeds every pixel from its alpha edge, runs log2 of the
// power of two at or above the larger side steps (half that size down to 1), then one more step of 1 (1+JFA's
// cleanup), and gives `DistanceField`'s outside and inside distances. The box blur is CoreRaster's `boxBlurred`
// (not a Gaussian): across then down, three times, each pass the `blur_pass` kernel over a box table of 2n + 1
// taps of 1 and, for a fractional radius, two outer taps of its fraction, all over 2·radius + 1, clamped to the
// edge. Invariants: a non-finite level or a radius outside 0...1,000 throws CoreRaster's error before any GPU
// work; radius 0 gives the pixels back; while unhealthy, or for a whole-image buffer over `maxBufferLength`, both
// throw `unsupported(.style)` and leave the backend healthy; a failed command buffer or allocation marks the
// backend failed and throws `deviceLost`; the source is unchanged; the lock is free across the GPU wait.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    /// `DistanceField(alpha:level:)` of `s`'s pixels, computed by jump flood: row-major outside and inside fields.
    package func distanceField(_ s: RenderSurface, level: Float = 0.5) throws -> (outside: [Float], inside: [Float]) {
        guard level.isFinite else { throw RenderError.raster("distance field level \(level): must be finite") }
        let (image, queue) = try styleSource(s)
        let (w, h) = (image.width, image.height)
        let commands = try styleCommands(queue)
        let pixels = try styleBuffer(image.components)
        let (outside, inside) = try encodeDistanceField(commands, pixels: pixels, width: w, height: h, level: level)
        try styleFinish(commands, label: "distance field")
        return (styleFloats(outside, w * h), styleFloats(inside, w * h))
    }

    /// `PixelBuffer.boxBlurred(radius:)` of `s`'s pixels, blurred on the GPU in Float32.
    package func boxBlurred(_ s: RenderSurface, radius: Double) throws -> PixelBuffer {
        guard radius.isFinite, radius >= 0, radius <= 1_000 else {
            throw RenderError.raster("box blur radius \(radius): must be finite and in 0...1000")
        }
        let (image, queue) = try styleSource(s)
        guard radius > 0 else { return image }
        let (w, h) = (image.width, image.height)
        let commands = try styleCommands(queue)
        let pixels = try styleBuffer(image.components)
        try encodeBoxBlur(commands, pixels, scratch: styleBuffer(count: w * h * 4), width: w, height: h, radius: radius)
        try styleFinish(commands, label: "box blur")
        return try stylePixels(styleFloats(pixels, w * h * 4), width: w, height: h)
    }

    /// `values` (`width` x `height` float4s) as a pixel buffer.
    func stylePixels(_ values: [Float], width w: Int, height h: Int) throws -> PixelBuffer {
        var out = try RenderError.mapping { try PixelBuffer(width: w, height: h) }
        for y in 0..<h {
            for x in 0..<w {
                let at = (y * w + x) * 4
                let p = RGBA(r: values[at], g: values[at + 1], b: values[at + 2], a: values[at + 3])
                try RenderError.mapping { try out.setPixel(x: x, y: y, p) }
            }
        }
        return out
    }

    /// Encodes the jump-flood field of `pixels` (`width` x `height` float4s) at `level` into `commands` and
    /// returns its outside and inside float buffers, filled once `commands` completes.
    func encodeDistanceField(_ commands: any MTLCommandBuffer, pixels: any MTLBuffer, width w: Int, height h: Int,
                             level: Float) throws -> (outside: any MTLBuffer, inside: any MTLBuffer) {
        let (seed, distance) = try withLock { () throws -> (any MTLComputePipelineState, any MTLComputePipelineState) in
            (try pipelines.pipeline(for: DistanceShader.seed, source: DistanceShader.source),
             try pipelines.pipeline(for: DistanceShader.distance, source: DistanceShader.source))
        }
        let seeds = try styleBuffer(count: w * h * 4)
        try styleDispatch(commands, seed, [pixels, seeds], ints: [w, h], level: level, width: w, height: h)
        let front = try encodeFlood(commands, seeds, scratch: styleBuffer(count: w * h * 4), width: w, height: h)
        let outside = try styleBuffer(count: w * h), inside = try styleBuffer(count: w * h)
        try styleDispatch(commands, distance, [front, outside, inside], ints: [w, h], width: w, height: h)
        return (outside, inside)
    }

    /// Encodes the jump-flood steps over `seeds` (`width` x `height` int4s, as `style_jfa_seed` writes them) with
    /// `scratch` beside it, and returns whichever of the two holds the flooded seeds once `commands` completes.
    func encodeFlood(_ commands: any MTLCommandBuffer, _ seeds: any MTLBuffer, scratch: any MTLBuffer,
                     width w: Int, height h: Int) throws -> any MTLBuffer {
        let step = try withLock { try pipelines.pipeline(for: DistanceShader.step, source: DistanceShader.source) }
        var front = seeds, back = scratch
        var size = 1
        while size < max(w, h) { size *= 2 }
        var jumps: [Int] = []
        var k = size / 2
        while k >= 1 { jumps.append(k); k /= 2 }
        for jump in jumps + [1] {
            try styleDispatch(commands, step, [front, back], ints: [w, h, jump], width: w, height: h)
            swap(&front, &back)
        }
        return front
    }

    /// Encodes `boxBlurred(radius:)` of `pixels` (`width` x `height` float4s) in place: six `blur_pass` passes
    /// alternating into `scratch` and back, so the result lands in `pixels`. `radius` is in (0, 1,000].
    func encodeBoxBlur(_ commands: any MTLCommandBuffer, _ pixels: any MTLBuffer, scratch: any MTLBuffer,
                       width w: Int, height h: Int, radius: Double) throws {
        let pass = try withLock { try pipelines.pipeline(for: BlurShader.pass, source: BlurShader.source) }
        let n = Int(radius), fraction = radius - Double(n), scale = 1 / (2 * radius + 1)
        let ones = [Float](repeating: Float(scale), count: 2 * n + 1)
        let taps = fraction > 0 ? [Float(fraction * scale)] + ones + [Float(fraction * scale)] : ones
        let weights = try styleBuffer(taps)
        let r = (taps.count - 1) / 2
        for _ in 0..<3 {
            try styleDispatch(commands, pass, [pixels, scratch, weights], ints: [h, w, r, 1, w], width: w, height: h)
            try styleDispatch(commands, pass, [scratch, pixels, weights], ints: [w, h, r, w, 1], width: h, height: w)
        }
    }

    /// `s`'s pixels, read like `read`, and the queue, checking the backend is healthy and the whole-image float4
    /// buffer fits this GPU.
    func styleSource(_ s: RenderSurface) throws -> (PixelBuffer, any MTLCommandQueue) {
        let (image, queue) = try withLock { () throws -> (PixelBuffer, any MTLCommandQueue) in
            guard state.healthy else { throw RenderError.unsupported(.style) }
            let stored = try lookup(s)
            stored.touch(tick())
            return (try stored.read(queue: commandQueue), commandQueue)
        }
        guard SurfaceTiling.wholeImageFits(width: image.width, height: image.height, bytesPerPixel: 16,
                                          maxBufferLength: device.maxBufferLength) else {
            throw RenderError.unsupported(.style)
        }
        return (image, queue)
    }

    /// Encodes `pipeline` over `width` x `height` threads with `buffers` at 0, 1, 2, then 6, 7, ... (int4 or float
    /// data), `ints` as Int32s (clamped) at buffer 3, `level`, when given, as a float at buffer 4 and `floats`, when
    /// any, at buffer 5.
    func styleDispatch(_ commands: any MTLCommandBuffer, _ pipeline: any MTLComputePipelineState,
                       _ buffers: [any MTLBuffer], ints: [Int], level: Float? = nil, floats: [Float] = [],
                       width: Int, height: Int) throws {
        guard let encoder = commands.makeComputeCommandEncoder() else { throw styleLost("style: no compute encoder on \(device.name)") }
        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() { encoder.setBuffer(buffer, offset: 0, index: index < 3 ? index : index + 3) }
        let packed = ints.map { Int32(clamping: $0) }
        packed.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: 3) }
        }
        if var level { encoder.setBytes(&level, length: MemoryLayout<Float>.size, index: 4) }
        floats.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: 5) }
        }
        let across = max(pipeline.threadExecutionWidth, 1), down = max(pipeline.maxTotalThreadsPerThreadgroup / across, 1)
        encoder.dispatchThreadgroups(MTLSize(width: (width + across - 1) / across, height: (height + down - 1) / down, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: across, height: down, depth: 1))
        encoder.endEncoding()
    }

    /// A new command buffer on `queue`.
    func styleCommands(_ queue: any MTLCommandQueue) throws -> any MTLCommandBuffer {
        guard let commands = queue.makeCommandBuffer() else { throw styleLost("style: no command buffer on \(device.name)") }
        return commands
    }

    /// Commits `commands`, waits with the lock free and records a failure under `label`.
    func styleFinish(_ commands: any MTLCommandBuffer, label: String) throws {
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: label)
    }

    /// A shared buffer holding `values`, or `count` zero floats when `values` is nil; never empty here.
    func styleBuffer(_ values: [Float]? = nil, count: Int = 0) throws -> any MTLBuffer {
        let floats = values ?? [Float](repeating: 0, count: max(count, 1))
        let made = floats.withUnsafeBytes { raw -> (any MTLBuffer)? in
            raw.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: raw.count, options: .storageModeShared) }
        }
        guard let made else { throw styleLost("style: buffer allocation failed for \(floats.count) floats") }
        return made
    }

    /// The first `count` floats of shared `buffer`.
    func styleFloats(_ buffer: any MTLBuffer, _ count: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: Float.self, capacity: count), count: count))
    }

    /// Marks the backend failed with `reason` (lock free) and returns the `deviceLost` error to throw.
    func styleLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}
#endif
