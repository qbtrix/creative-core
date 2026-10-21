// MetalBackend+Style.swift: a layer style entry's light layers on the GPU (layer-style-engine LE-9a), CoreRaster
// `styleLayers` with the same modes, opacities and placements: shadows and glows spread on the distance field,
// padded and box blurred; the stroke from anti-aliased edge points, nearest by the exact transform (LE-9a2); the bevel's height,
// normal and lean (LE-9a2); the overlay is its fill, drawn on the CPU. Each call is one command buffer over
// whole-image buffers.
// The distance field at level 0.5 is cached per surface with the alpha it came from: a call whose surface alpha is
// unchanged reuses it, a new upload re-encodes it, `release` drops it. Invariants: every parameter is checked by
// CoreRaster's own code first, so a bad entry throws the CPU's error before any GPU work; a padded work buffer over
// CoreRaster's cap throws its error, and over `maxBufferLength` throws `unsupported(.style)`, backend healthy;
// a failed command buffer marks the backend failed and throws `deviceLost`; the source and the cache of a released
// surface are untouched.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

/// A surface's distance field at level 0.5 and the alpha channel it was computed from.
struct StyleField {
    let alpha: [Float]
    let width: Int
    let outside: any MTLBuffer, inside: any MTLBuffer
}

/// One style encode: the surface's pixels on the CPU and the GPU, and its field once fetched or encoded.
struct StyleJob {
    let surface: UUID
    let image: PixelBuffer
    let pixels: any MTLBuffer
    var field: (outside: any MTLBuffer, inside: any MTLBuffer)?
    var fresh: StyleField?
}

extension MetalBackend {
    /// How many distance fields the style path has encoded, and how many surfaces hold one, for the cache tests.
    package var styleFieldEncodeCount: Int { withLock { styleFieldEncodes } }
    package var cachedStyleFieldCount: Int { withLock { styleFields.count } }

    /// CoreRaster `styleLayers(entry)` of `s`'s pixels, each layer drawn on the GPU in Float32 (an overlay on the CPU).
    package func styleLayers(_ s: RenderSurface, _ entry: StyleEntry) throws -> [StyleLayer] {
        let (image, queue) = try styleSource(s)
        // CoreRaster's checks and the layers' modes and placements, on one pixel.
        let shape = try RenderError.mapping { try PixelBuffer(width: 1, height: 1).styleLayers(entry) }
        let (w, h) = (image.width, image.height)
        if case .overlay(let fill) = entry.op {
            let paint = try RenderError.mapping { try image.fillLayer(fill) }
            return shape.map { var layer = $0; layer.source = paint; return layer }
        }
        let commands = try styleCommands(queue)
        var job = StyleJob(surface: s.id, image: image, pixels: try styleBuffer(image.components))
        let outputs = try encodeStyleLayers(commands, &job, entry.op)
        try styleFinish(commands, label: "style layers")
        if let fresh = job.fresh {
            withLock { if surfaces[s.id] != nil { styleFields[s.id] = fresh } }
        }
        var layers = shape
        for (index, output) in outputs.enumerated() where index < layers.count {
            layers[index].source = try stylePixels(styleFloats(output, w * h * 4), width: w, height: h)
        }
        return layers
    }

    /// Encodes `op`'s layers (in `styleLayers` order) and returns their float4 buffers.
    func encodeStyleLayers(_ commands: any MTLCommandBuffer, _ job: inout StyleJob, _ op: StyleOp) throws -> [any MTLBuffer] {
        switch op {
        case let .dropShadow(color, dx, dy, spread, blur):
            return [try encodeLight(commands, &job, color, dx, dy, spread, blur, inner: false, effect: "drop shadow")]
        case let .innerShadow(color, dx, dy, spread, blur):
            return [try encodeLight(commands, &job, color, dx, dy, spread, blur, inner: true, effect: "inner shadow")]
        case let .outerGlow(color, spread, size):
            return [try encodeLight(commands, &job, color, 0, 0, spread, size, inner: false, effect: "outer glow")]
        case let .innerGlow(color, spread, size):
            return [try encodeLight(commands, &job, color, 0, 0, spread, size, inner: true, effect: "inner glow")]
        case let .stroke(fill, width, position):
            return [try encodeStroke(commands, job, fill, width: width, position: position)]
        case let .bevel(bevel):
            return try encodeBevel(commands, &job, bevel)
        case .overlay:
            throw RenderError.unsupported(.style)
        }
    }

    /// The job's distance field: the cached one when the surface's alpha is unchanged, else encoded into `commands`.
    func styleField(_ commands: any MTLCommandBuffer, _ job: inout StyleJob) throws -> (outside: any MTLBuffer, inside: any MTLBuffer) {
        if let field = job.field { return field }
        let (w, h) = (job.image.width, job.image.height), data = job.image.components
        let alpha = (0..<(w * h)).map { data[$0 * 4 + 3] }
        if let cached = withLock({ styleFields[job.surface] }), cached.width == w, cached.alpha == alpha {
            job.field = (cached.outside, cached.inside)
            return (cached.outside, cached.inside)
        }
        let made = try encodeDistanceField(commands, pixels: job.pixels, width: w, height: h, level: 0.5)
        withLock { styleFieldEncodes += 1 }
        job.field = made
        job.fresh = StyleField(alpha: alpha, width: w, outside: made.outside, inside: made.inside)
        return made
    }

    /// A shadow or glow: CoreRaster `lightLayer`.
    func encodeLight(_ commands: any MTLCommandBuffer, _ job: inout StyleJob, _ color: RGBA, _ dx: Double, _ dy: Double,
                     _ spread: Double, _ size: Double, inner: Bool, effect: String) throws -> any MTLBuffer {
        let (w, h) = (job.image.width, job.image.height)
        let choke = spread * size, blur = size - choke
        let work = PixelBuffer.lightWork(effect: effect, reachName: "size", reach: blur, dx: dx, dy: dy)
        let (pw, ph) = try RenderError.mapping {
            try PixelBuffer.paddedWorkSize(width: w, height: h, pad: work.pad, cause: work.cause, remedy: work.remedy)
        }
        guard SurfaceTiling.wholeImageFits(width: pw, height: ph, bytesPerPixel: 16, maxBufferLength: device.maxBufferLength) else {
            throw RenderError.unsupported(.style)
        }
        var field = job.pixels
        if choke > 0 {
            let both = try styleField(commands, &job)
            field = inner ? both.inside : both.outside
        }
        let padded = try styleBuffer(count: pw * ph * 4), out = try styleBuffer(count: w * h * 4)
        let ints = [w, h, work.pad, inner ? 1 : 0, choke > 0 ? 1 : 0]
        try styleDispatch(commands, styleKernel("pad"), [job.pixels, field, padded], ints: ints, level: Float(choke),
                          width: pw, height: ph)
        if blur > 0 {
            try encodeBoxBlur(commands, padded, scratch: styleBuffer(count: pw * ph * 4), width: pw, height: ph, radius: blur / 3)
        }
        try styleDispatch(commands, styleKernel("light"), [job.pixels, padded, out], ints: ints,
                          floats: [Float(dx), Float(dy), color.r, color.g, color.b, color.a], width: w, height: h)
        return out
    }

    /// A stroke: CoreRaster `strokeLayer`, its fill drawn on the CPU and covered on the GPU.
    func encodeStroke(_ commands: any MTLCommandBuffer, _ job: StyleJob, _ fill: StyleFill, width strokeWidth: Double,
                      position: StrokePosition) throws -> any MTLBuffer {
        let (w, h) = (job.image.width, job.image.height)
        let paint = try RenderError.mapping { try job.image.fillLayer(fill) }
        guard strokeWidth > 0 else { return try styleBuffer(count: w * h * 4) }
        let (pw, ph) = try RenderError.mapping {
            try PixelBuffer.paddedWorkSize(width: w, height: h, pad: 1, cause: "stroke", remedy: nil)
        }
        // The exact transform's scratch is 5 int64s a pixel; int64 holds its cross-products for sides up to 2^20.
        guard max(pw, ph) <= 1 << 20,
              SurfaceTiling.wholeImageFits(width: pw, height: ph, bytesPerPixel: 40, maxBufferLength: device.maxBufferLength) else {
            throw RenderError.unsupported(.style)
        }
        let out = try styleBuffer(paint.components), n = pw * ph
        let squared = try styleBuffer(count: n * 2), nearest = try styleBuffer(count: n), points = try styleBuffer(count: n * 4)
        try styleDispatch(commands, styleKernel("edge_seed"), [job.pixels, squared, points, nearest], ints: [w, h],
                          width: pw, height: ph)
        let edt = try styleKernel("edt_pass"), scratch = try styleBuffer(count: n * 10)
        let squared2 = try styleBuffer(count: n * 2), nearest2 = try styleBuffer(count: n)
        try styleDispatch(commands, edt, [squared, nearest, squared2, nearest2, scratch], ints: [pw, ph, pw, 1], width: pw, height: 1)
        try styleDispatch(commands, edt, [squared2, nearest2, squared, nearest, scratch], ints: [ph, pw, 1, pw], width: ph, height: 1)
        let code = position == .outside ? 0 : position == .inside ? 1 : 2
        try styleDispatch(commands, styleKernel("stroke"), [nearest, points, out, job.pixels], ints: [w, h, code],
                          level: Float(strokeWidth), width: w, height: h)
        return out
    }

    /// A bevel: CoreRaster `beveled`, as [shadow, highlight].
    func encodeBevel(_ commands: any MTLCommandBuffer, _ job: inout StyleJob, _ bevel: Bevel) throws -> [any MTLBuffer] {
        let (w, h) = (job.image.width, job.image.height), n = w * h
        let highlight = try styleBuffer(count: n * 4), shadow = try styleBuffer(count: n * 4)
        guard bevel.size > 0 else { return [shadow, highlight] }
        let field = try styleField(commands, &job)
        let heights = try styleBuffer(count: n * 4), signed = try styleBuffer(count: n), scratch = try styleBuffer(count: n * 4)
        let shapes: [BevelShape] = [.innerBevel, .outerBevel, .emboss, .pillowEmboss]
        let shape = shapes.firstIndex(of: bevel.shape) ?? 0
        try styleDispatch(commands, styleKernel("bevel_height"), [field.outside, field.inside, heights, signed],
                          ints: [w, h, shape, bevel.technique == .smooth ? 0 : 1, bevel.up ? 1 : 0],
                          level: Float(bevel.size), width: w, height: h)
        if bevel.technique == .chiselSoft {
            try encodeBoxBlur(commands, heights, scratch: scratch, width: w, height: h, radius: 1.0 / 3)
        }
        if bevel.soften > 0 {
            try encodeBoxBlur(commands, heights, scratch: scratch, width: w, height: h, radius: bevel.soften / 3)
        }
        let theta = bevel.angle * .pi / 180, alt = bevel.altitude * .pi / 180
        let cosA = abs(cos(alt)) < 1e-12 ? 0 : cos(alt)
        let (lit, dark) = (bevel.highlight, bevel.shadow), (ko, kd) = (bevel.highlightOpacity, bevel.shadowOpacity)
        let floats = [Float(bevel.size), Float(bevel.depth * bevel.size), Float(cosA * cos(theta)), Float(cosA * sin(theta)),
                      lit.r * ko, lit.g * ko, lit.b * ko, lit.a * ko, dark.r * kd, dark.g * kd, dark.b * kd, dark.a * kd]
        try styleDispatch(commands, styleKernel("bevel_light"), [job.pixels, heights, highlight, shadow, signed],
                          ints: [w, h, shape], floats: floats, width: w, height: h)
        return [shadow, highlight]
    }

    /// The style pipeline `variant` of `StyleShader`.
    func styleKernel(_ variant: String) throws -> any MTLComputePipelineState {
        try withLock { try pipelines.pipeline(for: StyleShader.key(variant), source: StyleShader.source) }
    }
}
#endif
