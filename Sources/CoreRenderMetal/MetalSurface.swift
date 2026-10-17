// MetalSurface.swift: one RenderSurface's storage: a SurfaceTiling grid of rgba16Float
// textures (linear, premultiplied, one per tile, row-major) filled from a PixelBuffer
// through HalfFloat; a tile can leave the GPU for a CPU shadow (MB-16, MetalSurface+Eviction.swift).
// Invariants: `tiles`, `shadows` and `lastUse` have `tiling.tileCount` entries; tile `i` is resident
// (`tiles[i]` set, `shadows[i]` nil) or shadowed (`tiles[i]` nil, `shadows[i]` sized to `tiling.rect(i)`),
// never neither; `residentBytes` is width x height x `bytesPerPixel` over the resident tiles; textures use
// `MetalBackend.tileStorageMode` (shared on unified memory, managed on a discrete GPU); upload clamps every
// component to the finite half range, so a tile read back is always finite. No GPU work writes the textures
// yet, so `replace` and `getBytes` need no synchronisation and a shadow taken on eviction is current; a slice
// that encodes GPU work must wait for its command buffer (and synchronize a managed tile) before `download`.
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
    /// The largest finite binary16: upload clamps each component to plus or minus this.
    private static let halfMax: Float = 65504

    /// The 256 px tile grid over the surface, row-major.
    let tiling: SurfaceTiling
    /// The backend's use clock when this surface was uploaded: breaks `lastUse` ties, older first.
    let created: UInt64
    /// One texture per tile, in `tiling` index order, sized to `tiling.rect(i)`; nil once evicted.
    var tiles: [(any MTLTexture)?]
    /// One tile-sized CPU copy per evicted tile, taken on eviction; nil while the texture is resident.
    var shadows: [PixelBuffer?]
    /// Per tile, the backend's use clock at its last upload or read; the LRU key.
    var lastUse: [UInt64]
    /// Bytes the resident tile textures hold: width x height x `bytesPerPixel` summed over `tiles`.
    var residentBytes: Int

    /// Uploads `buffer` tile by tile as binary16 (components clamped to +-65504, so no tile holds an
    /// infinity) and stamps every tile's `lastUse` with `clock`. Throws `RenderError.raster` for a size
    /// the tiling rejects, `RenderError.deviceLost` when the device returns no texture (the backend
    /// marks itself failed before passing it on).
    init(device: any MTLDevice, buffer: PixelBuffer, clock: UInt64) throws {
        let tiling = try SurfaceTiling(width: buffer.width, height: buffer.height)
        var tiles: [(any MTLTexture)?] = []
        tiles.reserveCapacity(tiling.tileCount)
        var bytes = 0
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            let halves = try Self.halves(of: buffer, in: rect)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: rect.width, height: rect.height, mipmapped: false)
            descriptor.storageMode = MetalBackend.tileStorageMode(unifiedMemory: device.hasUnifiedMemory)
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RenderError.deviceLost("texture allocation failed for \(rect.width)x\(rect.height) (device out of memory; release surfaces or lower budgetBytes)")
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
            bytes += Self.bytes(of: rect)
        }
        self.tiling = tiling
        self.created = clock
        self.tiles = tiles
        self.shadows = Array(repeating: nil, count: tiling.tileCount)
        self.lastUse = Array(repeating: clock, count: tiling.tileCount)
        self.residentBytes = bytes
    }

    /// Every tile into a new `PixelBuffer` of the surface's size: a resident tile is downloaded, an
    /// evicted one copied from its shadow. Throws `RenderError.raster` when the buffer rejects the
    /// size or a decoded component is not finite: upload clamps, so only a value a GPU kernel wrote
    /// (none yet) can be, and buffers hold finite values only.
    func read() throws -> PixelBuffer {
        var buffer = try RenderError.mapping { try PixelBuffer(width: tiling.width, height: tiling.height) }
        // `rect` throws for an index outside the tiling and both arrays have `tileCount` entries,
        // so the subscripts are in range.
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            guard let tile = try tiles[index].map({ try Self.download($0, rect: rect, index: index) }) ?? shadows[index] else {
                throw RenderError.raster("tile \(index) has neither a texture nor a shadow")
            }
            try RenderError.mapping {
                try buffer.replaceTile(column: index % tiling.columns, row: index / tiling.columns, with: tile)
            }
        }
        return buffer
    }

    /// The texture bytes of a tile of `rect`'s size.
    static func bytes(of rect: TileRect) -> Int { rect.width * rect.height * bytesPerPixel }

    /// `texture` (a tile of `rect`'s size) as a new `rect.width` x `rect.height` `PixelBuffer`.
    /// Throws `RenderError.raster` when a decoded component is not finite (see `read`).
    static func download(_ texture: any MTLTexture, rect: TileRect, index: Int) throws -> PixelBuffer {
        var halves = [UInt16](repeating: 0, count: rect.width * rect.height * channels)
        try halves.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else {
                throw RenderError.raster("empty download for tile \(index), \(rect.width)x\(rect.height)")
            }
            texture.getBytes(base, bytesPerRow: rect.width * bytesPerPixel,
                             from: MTLRegionMake2D(0, 0, rect.width, rect.height), mipmapLevel: 0)
        }
        var tile = try RenderError.mapping { try PixelBuffer(width: rect.width, height: rect.height) }
        // `halves` holds exactly `channels` values per pixel of `rect`, so `offset` stays inside it.
        var offset = 0
        for y in 0..<rect.height {
            for x in 0..<rect.width {
                let pixel = RGBA(
                    r: HalfFloat.decode(halves[offset]), g: HalfFloat.decode(halves[offset + 1]),
                    b: HalfFloat.decode(halves[offset + 2]), a: HalfFloat.decode(halves[offset + 3]))
                offset += channels
                try RenderError.mapping { try tile.setPixel(x: x, y: y, pixel) }
            }
        }
        return tile
    }

    /// The premultiplied pixels of `rect` in `buffer` as row-major RGBA binary16, `rect.width * rect.height
    /// * channels` values, each clamped to +-`halfMax` first (65520 and up would encode as infinity).
    /// Throws `RenderError.raster` for a coordinate outside `buffer` (the tiling never does).
    private static func halves(of buffer: PixelBuffer, in rect: TileRect) throws -> [UInt16] {
        var halves: [UInt16] = []
        halves.reserveCapacity(rect.width * rect.height * channels)
        for y in rect.y..<(rect.y + rect.height) {
            for x in rect.x..<(rect.x + rect.width) {
                let pixel = try RenderError.mapping { try buffer.pixel(x: x, y: y) }
                halves.append(half(pixel.r))
                halves.append(half(pixel.g))
                halves.append(half(pixel.b))
                halves.append(half(pixel.a))
            }
        }
        return halves
    }

    /// `value` (finite, as buffers hold) clamped to +-`halfMax`, then encoded as binary16.
    private static func half(_ value: Float) -> UInt16 { HalfFloat.encode(min(max(value, -halfMax), halfMax)) }
}
#endif
