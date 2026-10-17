// OpaqueRowsTests.swift: the opaque-row split the Metal composite blits by (MB-6). Only `.normal` at opacity
// exactly 1 copies; a row is opaque only when every alpha in the piece's columns is exactly 1 (0.999 is not);
// the runs cover every row of every piece once, and CoreRaster's composite leaves exactly the source in the
// rows marked opaque, so a blit of them equals the CPU bit for bit.
import CoreRaster
import CoreRender
import Testing

@Suite struct OpaqueRowsTests {
    /// A seeded premultiplied buffer with alpha 1 on even rows, except one 0.999 pixel on row 2.
    private static func striped(_ width: Int, _ height: Int, seed: UInt64) throws -> PixelBuffer {
        var (rng, buffer) = (ParityRandom(seed: seed), try PixelBuffer(width: width, height: height))
        for y in 0..<height { for x in 0..<width {
            var a: Float = y % 2 == 0 ? 1 : .random(in: 0...1, using: &rng)
            if y == 2 && x == width / 3 { a = 0.999 }
            try buffer.setPixel(x: x, y: y, RGBA(r: .random(in: 0...a, using: &rng), g: a / 2, b: a * 0.9, a: a))
        } }
        return buffer
    }

    /// The single piece of a small source placed at the origin of a larger backdrop.
    private static func wholePiece(width: Int, height: Int) throws -> TilePiece {
        let pieces = try CompositeMap.pieces(source: SurfaceTiling(width: width, height: height),
                                             onto: SurfaceTiling(width: 32, height: 32), x: 0, y: 0)
        #expect(pieces.count == 1)
        return try #require(pieces.first)
    }

    @Test func onlyNormalAtExactlyFullOpacityCopies() {
        #expect(OpaqueRows.applies(mode: .normal, opacity: 1))
        #expect(!OpaqueRows.applies(mode: .normal, opacity: 0.37))
        #expect(!OpaqueRows.applies(mode: .normal, opacity: Float(1).nextDown))
        #expect(!OpaqueRows.applies(mode: .multiply, opacity: 1))
    }

    @Test func aRowIsOpaqueOnlyWhenEveryAlphaInItsColumnsIsOne() throws {
        var tile = try PixelBuffer(width: 6, height: 4, fill: RGBA(r: 0.2, g: 0.3, b: 0.4, a: 1))
        try tile.setPixel(x: 3, y: 1, RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.999))
        try tile.setPixel(x: 0, y: 2, RGBA(r: 0, g: 0, b: 0, a: 0.5))  // outside the piece's columns 1..<6
        try tile.setPixel(x: 5, y: 3, RGBA(r: 0, g: 0, b: 0, a: 0))
        let all = try Self.wholePiece(width: 6, height: 4)
        #expect(try OpaqueRows.flags(of: all, in: tile) == [true, false, false, false])
        let shifted = try #require(try CompositeMap.pieces(source: SurfaceTiling(width: 6, height: 4),
                                                           onto: SurfaceTiling(width: 5, height: 4), x: -1, y: 0).first)
        #expect(shifted.sourceX == 1 && shifted.width == 5)
        #expect(try OpaqueRows.flags(of: shifted, in: tile) == [true, false, true, false])
        #expect(throws: RenderError.self) { try OpaqueRows.flags(of: all, in: try PixelBuffer(width: 5, height: 4)) }
    }

    @Test func runsSplitAPieceIntoMaximalBandsInOrder() throws {
        let piece = try Self.wholePiece(width: 7, height: 6)
        let runs = try OpaqueRows.runs(of: piece, opaque: [true, true, false, true, false, false])
        #expect(runs.map(\.opaque) == [true, false, true, false])
        #expect(runs.map(\.piece.height) == [2, 1, 1, 2])
        #expect(runs.map(\.piece.sourceY) == [0, 2, 3, 4] && runs.map(\.piece.destinationY) == [0, 2, 3, 4])
        #expect(runs.allSatisfy { $0.piece.width == 7 && $0.piece.sourceX == 0 })
        #expect(try OpaqueRows.runs(of: piece, opaque: Array(repeating: false, count: 6)).map(\.piece.height) == [6])
        #expect(throws: RenderError.self) { try OpaqueRows.runs(of: piece, opaque: [true]) }
    }

    /// Across tiles and offsets: the runs cover the overlap once, and the opaque rows of CoreRaster's result
    /// are the source pixels exactly while every kernel row holds an alpha below 1.
    @Test(arguments: [(-40, -30), (20, 10), (150, 140)])
    func opaqueRunsAreExactlyTheSourceInTheCPUResult(x: Int, y: Int) throws {
        let source = try Self.striped(300, 270, seed: 0x0FA6), backdrop = try Self.striped(320, 300, seed: 0xBAC6)
        let (from, to) = (try SurfaceTiling(width: 300, height: 270), try SurfaceTiling(width: 320, height: 300))
        let expected = try composite(source, onto: backdrop, x: x, y: y, mode: .normal, opacity: 1)
        var writes = [Int](repeating: 0, count: 320 * 300)
        var copied = 0
        for piece in try CompositeMap.pieces(source: from, onto: to, x: x, y: y) {
            let (s, d) = (try from.rect(piece.sourceTile), try to.rect(piece.destinationTile))
            let tile = try source.cropped(x: s.x, y: s.y, width: s.width, height: s.height)
            for run in try OpaqueRows.runs(of: piece, opaque: OpaqueRows.flags(of: piece, in: tile)) {
                let p = run.piece
                for r in 0..<p.height {
                    var below = false
                    for c in 0..<p.width {
                        let (bx, by) = (d.x + p.destinationX + c, d.y + p.destinationY + r)
                        writes[by * 320 + bx] += 1
                        let pixel = try tile.pixel(x: p.sourceX + c, y: p.sourceY + r)
                        below = below || pixel.a < 1
                        if run.opaque { #expect(try expected.pixel(x: bx, y: by) == pixel) }
                    }
                    #expect(below != run.opaque, "row \(p.sourceY + r) of tile \(piece.sourceTile)")
                }
                if run.opaque { copied += p.height }
            }
        }
        let covered = (max(y, 0)..<min(y + 270, 300)).count * (max(x, 0)..<min(x + 300, 320)).count
        #expect(writes.reduce(0, +) == covered && writes.allSatisfy { $0 <= 1 })
        #expect(copied > 0)
    }
}
