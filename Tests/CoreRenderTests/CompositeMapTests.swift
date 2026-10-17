// CompositeMapTests.swift: the pieces the Metal composite runs over (MB-4) cover exactly the overlap of a
// source at any offset, each pixel once and read from the right source pixel, so compositing piece by
// piece gives CoreRaster's in-place composite bit for bit; the opacity check throws the CPU backend's error.
import CoreRaster
import CoreRender
import Testing

@Suite struct CompositeMapTests {
    /// A seeded premultiplied buffer: alpha in [0, 1], each colour at most alpha.
    private static func seeded(_ width: Int, _ height: Int, seed: UInt64) throws -> PixelBuffer {
        var (rng, buffer) = (ParityRandom(seed: seed), try PixelBuffer(width: width, height: height))
        for y in 0..<height { for x in 0..<width {
            let a = Float.random(in: 0...1, using: &rng)
            try buffer.setPixel(x: x, y: y, RGBA(r: .random(in: 0...a, using: &rng), g: a / 2, b: a * 0.9, a: a))
        } }
        return buffer
    }

    /// `source` composited onto `backdrop` one piece at a time, as the kernel does, counting writes per pixel.
    private static func apply(_ source: PixelBuffer, onto backdrop: PixelBuffer, x: Int, y: Int,
                              opacity: Float) throws -> (PixelBuffer, [Int]) {
        let from = try SurfaceTiling(width: source.width, height: source.height)
        let to = try SurfaceTiling(width: backdrop.width, height: backdrop.height)
        var out = backdrop
        var writes = [Int](repeating: 0, count: backdrop.width * backdrop.height)
        for piece in try CompositeMap.pieces(source: from, onto: to, x: x, y: y) {
            let s = try from.rect(piece.sourceTile), d = try to.rect(piece.destinationTile)
            #expect(piece.width >= 1 && piece.height >= 1 && min(piece.sourceX, piece.sourceY, piece.destinationX, piece.destinationY) >= 0)
            #expect(piece.sourceX + piece.width <= s.width && piece.sourceY + piece.height <= s.height
                    && piece.destinationX + piece.width <= d.width && piece.destinationY + piece.height <= d.height, "inside both tiles")
            let (bx, by) = (d.x + piece.destinationX, d.y + piece.destinationY)
            #expect(bx - x == s.x + piece.sourceX && by - y == s.y + piece.sourceY, "the piece reads the pixel at the offset")
            let part = try source.cropped(x: s.x + piece.sourceX, y: s.y + piece.sourceY, width: piece.width, height: piece.height)
            try out.composite(part, x: bx, y: by, mode: .normal, opacity: opacity)
            for gy in 0..<piece.height { for gx in 0..<piece.width { writes[(by + gy) * backdrop.width + bx + gx] += 1 } }
        }
        return (out, writes)
    }

    @Test func piecesCompositeLikeCoreRasterAtEveryEdgeAndCorner() throws {
        let backdrop = try Self.seeded(300, 270, seed: 0xBAC0), source = try Self.seeded(260, 200, seed: 0x5A11)
        let offsets = [-130, 20, 170].flatMap { x in [-100, 35, 170].map { (x, $0) } } + [(-259, -199), (299, 269), (0, 0)]
        for (x, y) in offsets {
            let (got, writes) = try Self.apply(source, onto: backdrop, x: x, y: y, opacity: 0.37)
            #expect(got == (try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 0.37)), "at (\(x), \(y))")
            let once = (0..<writes.count).allSatisfy { i in
                let (bx, by) = (i % backdrop.width - x, i / backdrop.width - y)
                return writes[i] == (bx >= 0 && bx < source.width && by >= 0 && by < source.height ? 1 : 0)
            }
            #expect(once, "at (\(x), \(y)): every overlap pixel is written once, no other")
        }
    }

    @Test func aSourceWhollyOutsideGivesNoPiece() throws {
        let (s, b) = (try SurfaceTiling(width: 260, height: 200), try SurfaceTiling(width: 300, height: 270))
        for (x, y) in [(300, 0), (-260, 0), (0, 270), (0, -200), (Int.min, 0), (0, Int.max), (Int.max, Int.min)] {
            #expect(try CompositeMap.pieces(source: s, onto: b, x: x, y: y).isEmpty, "at (\(x), \(y))")
        }
        #expect(try CompositeMap.pieces(source: s, onto: b, x: 299, y: 269).count == 1, "one corner pixel inside")
    }

    @Test func opacityOutsideTheUnitRangeThrowsTheCPUError() throws {
        let pixel = try PixelBuffer(width: 1, height: 1)
        for opacity: Float in [-0.01, 1.01, .nan, .infinity, -.infinity] {
            var backdrop = pixel
            do {
                try backdrop.composite(pixel, x: 0, y: 0, mode: .normal, opacity: opacity)
                Issue.record("CoreRaster accepts opacity \(opacity)")
            } catch let error as RasterError {
                #expect(throws: RenderError(error)) { try CompositeMap.validate(opacity: opacity) }
            }
        }
        for opacity: Float in [0, 0.37, 1] { try CompositeMap.validate(opacity: opacity) }
    }
}
