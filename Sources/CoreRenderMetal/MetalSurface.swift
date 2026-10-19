// MetalSurface.swift: one RenderSurface's storage: a SurfaceTiling grid of rgba16Float
// textures (linear, premultiplied, one per tile, row-major) filled from a PixelBuffer's components
// a row at a time (Float16 on arm64, HalfFloat elsewhere, bit for bit the same), or from zeros for a
// blank surface; a tile can leave the GPU for a CPU shadow (MB-16, MetalSurface+Eviction.swift).
// Invariants: `tiles`, `shadows` and `lastUse` have `tiling.tileCount` entries; tile `i` is resident
// (`tiles[i]` set, `shadows[i]` nil) or shadowed (`tiles[i]` nil, `shadows[i]` sized to `tiling.rect(i)`),
// never neither; `residentBytes` is width x height x `bytesPerPixel` over the resident tiles; textures use
// `MetalBackend.tileStorageMode` (shared on unified memory, managed on a discrete GPU); upload clamps every
// component to the finite half range. GPU kernels write tiles: composite in place on the backdrop's, the
// other ops into new surfaces' tiles. Each op synchronizes a managed tile it writes, and waits for its
// command buffer before any `download`, except the batched composite, which leaves the wait to the readback
// queued after it. Every CPU read of a tile (`read`, `download`, eviction) goes through `readback`: one
// blit into shared staging buffers on the backend's queue, waited for, never `getBytes`, which returned stale
// pixels right after a kernel's write on the macOS runners' paravirtual GPU (#453). A tile evicted while
// composite writes it in place can be shadowed mid-write, so composite downloads it again once the GPU is
// done (MetalBackend+Composite.swift).
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
    static let channels = 4
    /// The largest finite binary16: upload clamps each component to plus or minus this.
    static let halfMax: Float = 65504

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
    convenience init(device: any MTLDevice, buffer: PixelBuffer, clock: UInt64) throws {
        let components = buffer.components
        try self.init(device: device, width: buffer.width, height: buffer.height, clock: clock) { rect in
            try Self.halves(of: components, width: buffer.width, in: rect)
        }
    }

    /// A `width` x `height` surface with every pixel clear: each tile filled from zeros, no conversion.
    /// Throws as `init(device:buffer:clock:)` does.
    convenience init(device: any MTLDevice, width: Int, height: Int, clock: UInt64) throws {
        var zeros: [UInt16] = []
        try self.init(device: device, width: width, height: height, clock: clock) { rect in
            let count = rect.width * rect.height * Self.channels
            if zeros.count != count { zeros = [UInt16](repeating: 0, count: count) }
            return zeros
        }
    }

    /// Allocates each tile of a `width` x `height` tiling and fills it with `halves(rect)`, that tile's
    /// row-major RGBA binary16 values; stamps every tile's `lastUse` with `clock`.
    private init(device: any MTLDevice, width: Int, height: Int, clock: UInt64,
                 halves: (TileRect) throws -> [UInt16]) throws {
        let tiling = try SurfaceTiling(width: width, height: height)
        var tiles: [(any MTLTexture)?] = []
        tiles.reserveCapacity(tiling.tileCount)
        var bytes = 0
        for index in 0..<tiling.tileCount {
            let rect = try tiling.rect(index)
            let values = try halves(rect)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: rect.width, height: rect.height, mipmapped: false)
            descriptor.storageMode = MetalBackend.tileStorageMode(unifiedMemory: device.hasUnifiedMemory)
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RenderError.deviceLost("texture allocation failed for \(rect.width)x\(rect.height) (device out of memory; release surfaces or lower budgetBytes)")
            }
            let region = MTLRegionMake2D(0, 0, rect.width, rect.height)
            let bytesPerRow = rect.width * Self.bytesPerPixel
            try values.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, raw.count == bytesPerRow * rect.height else {
                    throw RenderError.raster("upload of \(raw.count) bytes for tile \(index), \(rect.width)x\(rect.height)")
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
    /// can be, and buffers hold finite values only.
    func read(queue: any MTLCommandQueue) throws -> PixelBuffer {
        var buffer = try RenderError.mapping { try PixelBuffer(width: tiling.width, height: tiling.height) }
        // `rect` throws for an index outside the tiling and both arrays have `tileCount` entries,
        // so the subscripts are in range.
        let rects = try (0..<tiling.tileCount).map { try tiling.rect($0) }
        let resident = tiles.indices.compactMap { index in tiles[index].map { (index: index, texture: $0) } }
        let halves = try Self.readback(resident.map { ($0.texture, rects[$0.index]) }, queue: queue)
        var downloaded: [Int: PixelBuffer] = [:]
        for (tile, values) in zip(resident, halves) {
            downloaded[tile.index] = try Self.decode(values, rect: rects[tile.index])
        }
        for index in 0..<tiling.tileCount {
            guard let tile = downloaded[index] ?? shadows[index] else {
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

    /// `texture` (a tile of `rect`'s size) as a new `rect.width` x `rect.height` `PixelBuffer`, read on `queue`.
    /// Throws `RenderError.raster` when a decoded component is not finite (see `read`) or the readback fails.
    static func download(_ texture: any MTLTexture, rect: TileRect, index: Int,
                         queue: any MTLCommandQueue) throws -> PixelBuffer {
        guard let halves = try readback([(texture, rect)], queue: queue).first else {
            throw RenderError.raster("empty download for tile \(index), \(rect.width)x\(rect.height)")
        }
        return try decode(halves, rect: rect)
    }

    /// Each tile's pixels (a texture and its tile's rect) as row-major RGBA binary16, `rect.width *
    /// rect.height * channels` values per tile, copied by one blit into shared staging buffers on `queue` and
    /// waited for. Never `getBytes`: on the macOS runners' paravirtual GPU it returned a tile's old pixels
    /// straight after the kernel that wrote it completed (#453); a blit queued after that kernel cannot.
    /// Throws `RenderError.raster` when a buffer or command buffer is unavailable or the blit fails.
    static func readback(_ tiles: [(texture: any MTLTexture, rect: TileRect)],
                         queue: any MTLCommandQueue) throws -> [[UInt16]] {
        guard !tiles.isEmpty else { return [] }
        let device = queue.device
        let staging = try tiles.map { tile -> any MTLBuffer in
            guard let buffer = device.makeBuffer(length: bytes(of: tile.rect), options: .storageModeShared) else {
                throw RenderError.raster("tile readback: no \(bytes(of: tile.rect))-byte buffer on \(device.name)")
            }
            return buffer
        }
        guard let commands = queue.makeCommandBuffer(), let blit = commands.makeBlitCommandEncoder() else {
            throw RenderError.raster("tile readback: no blit command buffer on \(device.name)")
        }
        for (tile, buffer) in zip(tiles, staging) {
            let rowBytes = tile.rect.width * bytesPerPixel
            blit.copy(from: tile.texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: tile.rect.width, height: tile.rect.height, depth: 1), to: buffer,
                      destinationOffset: 0, destinationBytesPerRow: rowBytes,
                      destinationBytesPerImage: rowBytes * tile.rect.height)
        }
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed, commands.error == nil else {
            throw RenderError.raster("tile readback failed on \(device.name): \(commands.error.map { "\($0)" } ?? "status \(commands.status.rawValue)")")
        }
        return zip(tiles, staging).map { tile, buffer in
            let count = tile.rect.width * tile.rect.height * channels
            return Array(UnsafeBufferPointer(start: buffer.contents().bindMemory(to: UInt16.self, capacity: count), count: count))
        }
    }

    /// `halves` (a tile of `rect`'s size, as `readback` returns it) decoded into a new `PixelBuffer`.
    /// Throws `RenderError.raster` for a short array or a component that is not finite (see `read`).
    static func decode(_ halves: [UInt16], rect: TileRect) throws -> PixelBuffer {
        guard halves.count == rect.width * rect.height * channels else {
            throw RenderError.raster("tile readback of \(halves.count) values for \(rect.width)x\(rect.height)")
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

    /// The premultiplied pixels of `rect` in a `width`-wide buffer's `components` as row-major RGBA binary16,
    /// `rect.width * rect.height * channels` values, each clamped to +-`halfMax` first (65520 and up would
    /// encode as infinity). Whole rows at a time through `half`. Throws `RenderError.raster` for a rect
    /// outside the buffer (the tiling never gives one).
    static func halves(of components: [Float], width: Int, in rect: TileRect) throws -> [UInt16] {
        let rowCount = rect.width * channels
        guard rect.x >= 0, rect.y >= 0, rect.x + rect.width <= width,
              (rect.y + rect.height) * width * channels <= components.count else {
            throw RenderError.raster("tile \(rect.x),\(rect.y) \(rect.width)x\(rect.height) is outside a \(width)-wide buffer")
        }
        var halves = [UInt16](repeating: 0, count: rowCount * rect.height)
        components.withUnsafeBufferPointer { source in
            halves.withUnsafeMutableBufferPointer { out in
                for row in 0..<rect.height {
                    let from = ((rect.y + row) * width + rect.x) * channels, to = row * rowCount
                    for i in 0..<rowCount { out[to + i] = half(source[from + i]) }
                }
            }
        }
        return halves
    }

    /// `value` (finite, as buffers hold) clamped to +-`halfMax`, then encoded as binary16: the hardware
    /// conversion where Float16 exists (arm64), else `HalfFloat.encode`; both round to nearest, ties to even.
    /// Always inlined: `halves`' loop then vectorizes, about 8x faster per tile than a call per value.
    @inline(__always)
    static func half(_ value: Float) -> UInt16 {
        let clamped = min(max(value, -halfMax), halfMax)
        #if arch(arm64)
        return Float16(clamped).bitPattern
        #else
        return HalfFloat.encode(clamped)
        #endif
    }
}
#endif
