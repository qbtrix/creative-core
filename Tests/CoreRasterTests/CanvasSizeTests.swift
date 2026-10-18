// CanvasSizeTests.swift: affine-composite AC-4's acceptance for `padded`:
// growing 100 x 50 to 200 x 100 places the image at each of the nine anchors'
// offsets with clear around it, shrinking crops by the same rule, the middle
// of an odd change rounds down, the right anchor keeps the right edge, and a
// size `validatedSize` rejects throws.
import CoreRaster
import Testing

@Suite struct CanvasSizeTests {
    /// Each anchor with its place on x and y in halves (0, 1 or 2).
    static let anchors: [(CanvasAnchor, Int, Int)] = [
        (.topLeft, 0, 0), (.top, 1, 0), (.topRight, 2, 0),
        (.left, 0, 1), (.center, 1, 1), (.right, 2, 1),
        (.bottomLeft, 0, 2), (.bottom, 1, 2), (.bottomRight, 2, 2),
    ]

    /// `layer` on a clear `width` x `height` canvas with its top left at
    /// (`dx`, `dy`), built pixel by pixel; whatever falls outside is dropped.
    private func placed(_ layer: PixelBuffer, width: Int, height: Int, dx: Int, dy: Int) throws -> PixelBuffer {
        var expected = try PixelBuffer(width: width, height: height)
        for y in 0..<layer.height where (0..<height).contains(y + dy) {
            for x in 0..<layer.width where (0..<width).contains(x + dx) {
                try expected.setPixel(x: x + dx, y: y + dy, layer.pixel(x: x, y: y))
            }
        }
        return expected
    }

    @Test
    func nineAnchorsPlaceTheImage() throws {
        let layer = try AffineFixtures.layer(seed: 401, width: 100, height: 50, border: 0, block: 7)
        for (anchor, hx, hy) in Self.anchors {
            let out = try layer.padded(width: 200, height: 100, anchor: anchor)
            let expected = try placed(layer, width: 200, height: 100, dx: 50 * hx, dy: 25 * hy)
            #expect(out == expected, "\(anchor)")
        }
    }

    @Test
    func shrinkingCropsByTheSameRule() throws {
        let layer = try AffineFixtures.layer(seed: 402, width: 100, height: 50, border: 0, block: 7)
        for (anchor, hx, hy) in Self.anchors {
            let out = try layer.padded(width: 60, height: 30, anchor: anchor)
            #expect(out == (try layer.cropped(x: 20 * hx, y: 10 * hy, width: 60, height: 30)), "\(anchor)")
        }
    }

    @Test
    func sameSizeIsTheImage() throws {
        let layer = try AffineFixtures.layer(seed: 403, width: 13, height: 9)
        for (anchor, _, _) in Self.anchors {
            #expect(try layer.padded(width: 13, height: 9, anchor: anchor) == layer, "\(anchor)")
        }
    }

    @Test
    func centreRoundsDown() throws {
        // Growing by 3 puts the image 1 in, not 2; shrinking by 3 crops 2, not 1.
        let layer = try AffineFixtures.layer(seed: 404, width: 5, height: 5, border: 0, block: 1)
        let grown = try layer.padded(width: 8, height: 8, anchor: .center)
        #expect(grown == (try placed(layer, width: 8, height: 8, dx: 1, dy: 1)))
        let shrunk = try layer.padded(width: 2, height: 2, anchor: .center)
        #expect(shrunk == (try layer.cropped(x: 2, y: 2, width: 2, height: 2)))
        let wide = try layer.padded(width: 8, height: 2, anchor: .top)
        #expect(wide == (try placed(layer, width: 8, height: 2, dx: 1, dy: 0)))
    }

    @Test
    func rightAnchorKeepsRightEdge() throws {
        let layer = try AffineFixtures.layer(seed: 405, width: 100, height: 50, border: 0, block: 7)
        let grown = try layer.padded(width: 300, height: 51, anchor: .right)
        #expect(try grown.pixel(x: 299, y: 0) == layer.pixel(x: 99, y: 0))
        #expect(try grown.pixel(x: 200, y: 49) == layer.pixel(x: 0, y: 49))
        #expect(try grown.pixel(x: 199, y: 10) == .clear)
        let shrunk = try layer.padded(width: 30, height: 50, anchor: .right)
        #expect(shrunk == (try layer.cropped(x: 70, y: 0, width: 30, height: 50)))
    }

    @Test
    func badSizesThrow() throws {
        let layer = try AffineFixtures.layer(seed: 406, width: 6, height: 4)
        let sizes = [(0, 4), (6, 0), (0, 0), (-1, 4), (6, -7), (Int.max, 2), (Int.min, Int.min),
                     (PixelBuffer.maxPixels, 2), (Int.max, Int.max)]
        for (w, h) in sizes {
            for anchor: CanvasAnchor in [.topLeft, .center, .bottomRight] {
                #expect(throws: RasterError.self, "\(w)x\(h) at \(anchor)") {
                    try layer.padded(width: w, height: h, anchor: anchor)
                }
            }
        }
    }
}
