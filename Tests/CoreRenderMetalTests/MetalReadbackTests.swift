// MetalReadbackTests.swift: a tile a kernel just wrote reads back with the kernel's pixels, the first time it is
// read. The real `resample_scatter` pipeline writes a constant into the 1563 shared tiles of a 400000x16 surface (the
// output of the resample parity strip), the command buffer completes, and `MetalSurface.readback` must return that constant
// for every tile, 40 times over. On the paravirtual GPU of the macOS runners a `getBytes` straight after completion
// returned the old contents of about one tile in seven runs (#453); a real Apple GPU never shows it, so only the
// runners can fail this. Skipped without a device; compiled out on Linux.
#if canImport(Metal)
import CoreRaster
import CoreRender
@testable import CoreRenderMetal
import Foundation
import Metal
import Testing

@Suite struct MetalReadbackTests {
    @Test(.enabled(if: MetalBackend.defaultDevice != nil)) func kernelWrittenTilesReadBackFirstTime() throws {
        let metal = try MetalBackend.onDefaultDevice()
        let (device, queue) = (metal.device, metal.commandQueue)
        let scatter = try metal.pipelines.pipeline(for: ResampleShader.scatter, source: ResampleShader.source)
        let (width, height) = (400_000, 16)
        let fill: [Float] = [0.25, 0.5, 0.125, 0.75]
        let tiling = try SurfaceTiling(width: width, height: height)
        let rects = try (0..<tiling.tileCount).map { try tiling.rect($0) }
        let halves = fill.map { HalfFloat.encode($0) }
        let expected = rects.map { rect in (0..<(rect.width * rect.height)).flatMap { _ in halves } }
        for run in 0..<40 {
            // Fresh buffers every run, as each resample allocates its own: a CPU-filled input and a GPU-filled one
            // the size of the tiles. The stale reads only showed up with this allocation churn on the GPU.
            let input = try #require(device.makeBuffer(length: width * height * 16, options: .storageModeShared))
            input.contents().bindMemory(to: SIMD4<Float>.self, capacity: width * height)
                .initialize(repeating: SIMD4(fill[0], fill[1], fill[2], fill[3]), count: width * height)
            let churn = try #require(device.makeBuffer(length: width * height * 8, options: .storageModeShared))
            let tiles = try rects.map { rect -> any MTLTexture in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba16Float, width: rect.width, height: rect.height, mipmapped: false)
                descriptor.storageMode = MetalBackend.tileStorageMode(unifiedMemory: device.hasUnifiedMemory)
                descriptor.usage = [.shaderRead, .shaderWrite]
                return try #require(device.makeTexture(descriptor: descriptor))
            }
            let commands = try #require(queue.makeCommandBuffer())
            let blit = try #require(commands.makeBlitCommandEncoder())
            blit.fill(buffer: churn, range: 0..<churn.length, value: 0x3C)
            blit.endEncoding()
            let encoder = try #require(commands.makeComputeCommandEncoder())
            encoder.setComputePipelineState(scatter)
            encoder.setBuffer(input, offset: 0, index: 0)
            let group = MTLSize(width: scatter.threadExecutionWidth,
                                height: max(scatter.maxTotalThreadsPerThreadgroup / scatter.threadExecutionWidth, 1), depth: 1)
            for (tile, rect) in zip(tiles, rects) {
                encoder.setTexture(tile, index: 0)
                [rect.x, rect.y, rect.width, rect.height, width].map { Int32($0) }.withUnsafeBytes { raw in
                    if let base = raw.baseAddress { encoder.setBytes(base, length: raw.count, index: 1) }
                }
                encoder.dispatchThreadgroups(MTLSize(width: (rect.width + group.width - 1) / group.width,
                                                     height: (rect.height + group.height - 1) / group.height, depth: 1),
                                             threadsPerThreadgroup: group)
            }
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            #expect(commands.status == .completed)
            let read = try MetalSurface.readback(Array(zip(tiles, rects)), queue: queue)
            let stale = read.indices.filter { read[$0] != expected[$0] }
            #expect(stale.isEmpty, "run \(run): tiles \(stale) read back other pixels than the kernel wrote")
        }
    }
}
#endif
