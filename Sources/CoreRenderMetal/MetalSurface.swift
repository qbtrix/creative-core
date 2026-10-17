// MetalSurface.swift: one RenderSurface's storage: a SurfaceTiling grid of rgba16Float
// textures (linear, premultiplied, one per tile, row-major) filled from a PixelBuffer
// through HalfFloat. Invariants: `tiles.count == tiling.tileCount`, tile `i` has the size
// of `tiling.rect(i)`, `residentBytes` is the sum of width x height x `bytesPerPixel`. No
// GPU work touches the textures yet (MB-1), so `replace` and `getBytes` need no synchronisation.
#if canImport(Metal)
import CoreRaster
import CoreRender
import Metal

/// One tiled rgba16Float surface on a device. Internal: the backend hands
/// callers a `RenderSurface` id and keeps the textures here behind its lock.
final class MetalSurface {
    /// Bytes per rgba16Float pixel: four 16-bit components.
    static let bytesPerPixel = 8
    /// Half floats per pixel (R, G, B, A).
    private static let channels = 4

    /// The 256 px tile grid over the surface, row-major.
    let tiling: SurfaceTiling
    /// One texture per tile, in `tiling` index order, sized to `tiling.rect(i)`.
    var tiles: [any MTLTexture]
    /// Bytes the tile textures hold: width x height x `bytesPerPixel` summed over `tiles`. Eviction (MB-16) lowers it.
    var residentBytes: Int

    /// Uploads `buffer` tile by tile as binary16. Throws `RenderError.raster` for a size the tiling
    /// rejects, `RenderError.deviceLost` when the device returns no texture.
    init(device: any MTLDevice, buffer: PixelBuffer) throws {
        let tiling = try SurfaceTiling(width: buffer.width, height: buffer.height)
        var tiles: [any MTLTexture] = []
        tiles.reserveCapacity(tiling.tileCount)
        var bytes = 0
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            let halves = try Self.halves(of: buffer, in: rect)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: rect.width, height: rect.height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RenderError.deviceLost("texture allocation failed for \(rect.width)x\(rect.height)")
            }
            let region = MTLRegionMake2D(0, 0, rect.width, rect.height)
            let bytesPerRow = rect.width * Self.bytesPerPixel
            try halves.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else {
                    throw RenderError.raster("empty upload for tile \(index), \(rect.width)x\(rect.height)")
                }
                texture.replace(region: region, mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
            }
            tiles.append(texture)
            bytes += rect.width * rect.height * Self.bytesPerPixel
        }
        self.tiling = tiling
        self.tiles = tiles
        self.residentBytes = bytes
    }

    /// Downloads every tile into a new `PixelBuffer` of the surface's size. Throws `RenderError.raster`
    /// when the buffer rejects the size or a decoded component is not finite: a component at or above
    /// 65520 in magnitude was encoded as a binary16 infinity on upload, and buffers hold finite values only.
    func read() throws -> PixelBuffer {
        var buffer = try Self.rethrown { try PixelBuffer(width: tiling.width, height: tiling.height) }
        for (index, texture) in tiles.enumerated() {
            let rect = try tiling.rect(index)
            var halves = [UInt16](repeating: 0, count: rect.width * rect.height * Self.channels)
            let region = MTLRegionMake2D(0, 0, rect.width, rect.height)
            let bytesPerRow = rect.width * Self.bytesPerPixel
            try halves.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else {
                    throw RenderError.raster("empty download for tile \(index), \(rect.width)x\(rect.height)")
                }
                texture.getBytes(base, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            }
            // `halves` holds exactly `channels` values per pixel of `rect`, so
            // `offset` stays inside it over the rect's pixels.
            var offset = 0
            for y in rect.y..<(rect.y + rect.height) {
                for x in rect.x..<(rect.x + rect.width) {
                    let pixel = RGBA(
                        r: HalfFloat.decode(halves[offset]), g: HalfFloat.decode(halves[offset + 1]),
                        b: HalfFloat.decode(halves[offset + 2]), a: HalfFloat.decode(halves[offset + 3]))
                    offset += Self.channels
                    try Self.rethrown { try buffer.setPixel(x: x, y: y, pixel) }
                }
            }
        }
        return buffer
    }

    /// The premultiplied pixels of `rect` in `buffer` as row-major RGBA binary16, `rect.width * rect.height
    /// * channels` values. Throws `RenderError.raster` for a coordinate outside `buffer` (the tiling never does).
    private static func halves(of buffer: PixelBuffer, in rect: TileRect) throws -> [UInt16] {
        var halves: [UInt16] = []
        halves.reserveCapacity(rect.width * rect.height * channels)
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                let pixel = try rethrown { try buffer.pixel(x: x, y: y) }
                halves.append(HalfFloat.encode(pixel.r))
                halves.append(HalfFloat.encode(pixel.g))
                halves.append(HalfFloat.encode(pixel.b))
                halves.append(HalfFloat.encode(pixel.a))
            }
        }
        return halves
    }

    /// Runs `body`, mapping a CoreRaster error to `RenderError.raster` with its message.
    private static func rethrown<R>(_ body: () throws -> R) throws -> R {
        do { return try body() } catch RasterError.invalid(let message) { throw RenderError.raster(message) }
    }
}
#endif
