// MetalBackend+Affine.swift: the `.affine` family on Metal (#829). The composite through a matrix runs
// `affine_<mode>` (Shaders/AffineShader.swift) on the backdrop's tiles inside `m.writeBounds`, in place, one
// dispatch per backdrop tile, with no readback. `transformed` and `flipped` run CoreRaster's op on the read
// pixels into a new surface, as the dispatcher's CPU fallback did; their kernels come later.
// Invariants: the CPU's checks in its order (unsupported while unhealthy, surfaces, opacity, matrix, bounds)
// before any pixel changes; pixels outside `m.writeBounds` are never written; no GPU wait under the lock; a
// backdrop tile evicted while the GPU wrote it gets its shadow from the written texture; the GPU path runs only
// for `.bilinear` at stretch 1 with every needed tile resident, a source that is not the backdrop and each
// tile's preimage inside a 4 x 4 block of source tiles; anything else takes the CPU path (`compositeOnCPU`).
#if canImport(Metal)
import CoreRaster
import CoreRender
import Foundation
import Metal

extension MetalBackend {
    public func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int,
                            filter: ResampleFilter) throws -> RenderSurface {
        try surface(RenderError.mapping { try affineInput(s).transformed(m, width: width, height: height, filter: filter) })
    }

    public func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface {
        try surface(try affineInput(s).flipped(axis))
    }

    public func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
                          opacity: Float, filter: ResampleFilter) throws {
        let planned = try withLock { () throws -> AffinePlan? in
            guard state.effectiveSupports.contains(.affine) else { throw RenderError.unsupported(.affine) }
            let (source, backdrop) = (try lookup(s), try lookup(b))
            try CompositeMap.validate(opacity: opacity)
            guard [m.a, m.b, m.c, m.d, m.tx, m.ty].allSatisfy(\.isFinite), let inv = m.inverse else {
                throw RenderError.raster("composite through \(m): matrix is non-finite or singular")
            }
            guard let wide = m.writeBounds(of: s.width, s.height, filter: filter) else {
                throw RenderError.raster("composite through \(m): the layer's corners map outside the finite range")
            }
            // ponytail: other filters, downscales, a source that is the backdrop and evicted tiles take the CPU path.
            guard filter == .bilinear, source !== backdrop, (inv.a * inv.a + inv.c * inv.c) <= 1,
                  (inv.b * inv.b + inv.d * inv.d) <= 1 else { return nil }
            let side = SurfaceTiling.tileSize
            let (x0, x1) = (max(wide.x, 0), min(wide.x + wide.width, b.width))
            let (y0, y1) = (max(wide.y, 0), min(wide.y + wide.height, b.height))
            guard x0 < x1, y0 < y1 else { return AffinePlan(backdrop: backdrop, steps: [], pipeline: nil, queue: commandQueue) }
            var steps: [AffineStep] = []
            for index in backdrop.tiling.tiles(touching: x0, y: y0, width: x1 - x0, height: y1 - y0) {
                let rect = try backdrop.tiling.rect(index)
                let (rx0, rx1) = (max(rect.x, x0), min(rect.x + rect.width, x1))
                let (ry0, ry1) = (max(rect.y, y0), min(rect.y + rect.height, y1))
                guard rx0 < rx1, ry0 < ry1 else { continue }
                // The source taps the region can reach: its corner centres through `inv`, one tap past either way.
                let corners = [(rx0, ry0), (rx1 - 1, ry0), (rx0, ry1 - 1), (rx1 - 1, ry1 - 1)].map { centre(inv, $0.0, $0.1) }
                let us = corners.map { $0.x - 0.5 }, vs = corners.map { $0.y - 0.5 }
                guard let umin = us.min(), let umax = us.max(), let vmin = vs.min(), let vmax = vs.max() else { continue }
                let (sx0, sx1) = (max(Int((umin - 1).rounded(.up)), 0), min(Int((umax + 1).rounded(.down)), s.width - 1))
                let (sy0, sy1) = (max(Int((vmin - 1).rounded(.up)), 0), min(Int((vmax + 1).rounded(.down)), s.height - 1))
                guard sx0 <= sx1, sy0 <= sy1 else { continue }  // no source tap: the CPU leaves these pixels as they are
                let (bc, br) = (sx0 / side, sy0 / side)
                guard sx1 / side - bc < 4, sy1 / side - br < 4, let target = backdrop.tiles[index] else { return nil }
                var block = [(any MTLTexture)?](repeating: nil, count: 16)
                for row in br...(sy1 / side) {
                    for column in bc...(sx1 / side) {
                        guard let tile = source.tiles[row * source.tiling.columns + column] else { return nil }
                        block[(row - br) * 4 + column - bc] = tile
                    }
                }
                let first = centre(inv, rx0, ry0)
                let parameters = AffineParameters(
                    region: (Int32(rx0 - rect.x), Int32(ry0 - rect.y), Int32(rx1 - rx0), Int32(ry1 - ry0)),
                    limits: (Int32(s.width - bc * side), Int32(s.height - br * side), Int32(bc * side), Int32(br * side)),
                    inverse: (Float(inv.a), Float(inv.b), Float(inv.c), Float(inv.d)),
                    start: (Float(first.x - 0.5 - Double(bc * side)), Float(first.y - 0.5 - Double(br * side)), 0, 0),
                    opacity: opacity)
                steps.append(AffineStep(index: index, block: block, target: target, parameters: parameters))
            }
            let clock = tick()
            for surface in [source, backdrop] { surface.touch(clock) }
            return AffinePlan(backdrop: backdrop, steps: steps,
                              pipeline: try pipelines.pipeline(for: AffineShader.key(mode), source: AffineShader.source), queue: commandQueue)
        }
        guard let plan = planned else {
            return try compositeOnCPU(s, onto: b, through: m, mode: mode, opacity: opacity, filter: filter)
        }
        guard let pipeline = plan.pipeline, !plan.steps.isEmpty else { return }
        try encodeAffine(plan, pipeline: pipeline)
    }

    /// Runs every step's dispatch in one command buffer and waits; call with the lock free.
    private func encodeAffine(_ plan: AffinePlan, pipeline: any MTLComputePipelineState) throws {
        guard let commands = plan.queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
            throw affineLost("composite through a matrix: no command buffer or encoder on \(device.name)")
        }
        encoder.setComputePipelineState(pipeline)
        let width = max(pipeline.threadExecutionWidth, 1)
        let group = MTLSize(width: width, height: max(pipeline.maxTotalThreadsPerThreadgroup / width, 1), depth: 1)
        for step in plan.steps {
            var parameters = step.parameters
            encoder.setTextures(step.block, range: 0..<16)
            encoder.setTexture(step.target, index: 16)
            encoder.setBytes(&parameters, length: MemoryLayout<AffineParameters>.stride, index: 0)
            let (w, h) = (Int(parameters.region.2), Int(parameters.region.3))
            encoder.dispatchThreadgroups(MTLSize(width: (w + group.width - 1) / group.width, height: (h + group.height - 1) / group.height, depth: 1),
                                         threadsPerThreadgroup: group)
        }
        encoder.endEncoding()
        #if os(macOS)
        let managed = plan.steps.map(\.target).filter { $0.storageMode == .managed }
        if !managed.isEmpty {
            guard let blitter = commands.makeBlitCommandEncoder() else { throw affineLost("composite through a matrix: no blit encoder") }
            for tile in managed { blitter.synchronize(resource: tile) }
            blitter.endEncoding()
        }
        #endif
        commands.commit()
        commands.waitUntilCompleted()
        try recordCompletion(status: commands.status, error: commands.error, label: "composite through a matrix")
        try withLock {  // a tile evicted while the GPU wrote it: its shadow is the written texture
            for step in plan.steps where plan.backdrop.tiles[step.index] == nil {
                plan.backdrop.shadows[step.index] = try MetalSurface.download(step.target, rect: plan.backdrop.tiling.rect(step.index),
                                                                              index: step.index, queue: plan.queue)
            }
        }
    }

    /// CoreRaster's composite through `m` on the read pixels, stored back under `b`'s id.
    private func compositeOnCPU(_ s: RenderSurface, onto b: RenderSurface, through m: AffineMatrix, mode: BlendMode,
                                opacity: Float, filter: ResampleFilter) throws {
        var backdrop = try read(b)
        let source = s == b ? backdrop : try read(s)
        try RenderError.mapping { try backdrop.composite(source, through: m, mode: mode, opacity: opacity, filter: filter) }
        let stored = try MetalSurface(device: device, buffer: backdrop, clock: withLock { tick() })
        try withLock {
            _ = try lookup(b)
            surfaces[b.id] = stored
        }
        evictIfNeeded()
    }

    /// `s`'s pixels for `transformed` and `flipped`, gated by `.affine` like the CPU.
    private func affineInput(_ s: RenderSurface) throws -> PixelBuffer {
        guard supports.contains(.affine) else { throw RenderError.unsupported(.affine) }
        return try read(s)
    }

    /// Where pixel (`x`, `y`)'s centre lands under `m`, as CoreRaster's `centre` (internal there).
    private func centre(_ m: AffineMatrix, _ x: Int, _ y: Int) -> (x: Double, y: Double) {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        return (m.a * px + m.c * py + m.tx, m.b * px + m.d * py + m.ty)
    }

    private func affineLost(_ reason: String) -> RenderError { fail(reason); return RenderError.deviceLost(reason) }
}

/// MSL's `AffineParams`: four int4, two float4 and the opacity.
private struct AffineParameters {
    var region: (Int32, Int32, Int32, Int32)
    var limits: (Int32, Int32, Int32, Int32)
    var inverse: (Float, Float, Float, Float)
    var start: (Float, Float, Float, Float)
    var opacity: Float
}

private struct AffineStep {
    let index: Int
    let block: [(any MTLTexture)?]
    let target: any MTLTexture
    let parameters: AffineParameters
}

private struct AffinePlan {
    let backdrop: MetalSurface
    let steps: [AffineStep]
    let pipeline: (any MTLComputePipelineState)?
    let queue: any MTLCommandQueue
}
#endif
