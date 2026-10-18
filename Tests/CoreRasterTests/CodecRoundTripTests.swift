// ORA write then read (LC-8): layers, the composite, extra app entries and
// their collisions, a thumbnail 256 on its longest side, and what ORA cannot hold.
import CoreRaster
import Foundation
import Testing

@Suite struct CodecRoundTripTests {
    // A tall canvas holding only what an ORA keeps (no masks or clipping).
    func image() throws -> LayeredImage {
        let ink = PixelLayer(name: "Ink", pixels: try ORAFixtures.pixels(1), x: 12, y: -3, opacity: 0.5, blendMode: .multiply)
        let hidden = PixelLayer(name: "Hidden", pixels: try ORAFixtures.pixels(2), x: 5, y: 900, isHidden: true)
        return LayeredImage(width: 300, height: 1000, nodes: [.group(LayerGroup(name: "Group", children: [.pixels(hidden)], opacity: 0.75)),
                                                              .pixels(ink)], composite: try ORAFixtures.pixels(3, 300, 1000), profile: nil)
    }
    func written(extra: [String: Data] = [:]) throws -> Data {
        try OpenRaster.write(image(), pixels: RawPixelCodec(), extra: extra)
    }
    @Test func oraRoundTripsWithinOneStep() throws {
        let back = try OpenRaster.read(written(), pixels: RawPixelCodec())
        let ink = try #require(pixelLayer(back.nodes.last)), group = try #require(layerGroup(back.nodes.first))
        #expect(back.width == 300 && back.height == 1000 && back.profile == nil && back.nodes.count == 2)
        #expect(try ink.pixels == ORAFixtures.pixels(1) && ink.x == 12 && ink.y == -3 && abs(ink.opacity - 0.5) <= 1 / 255)
        #expect(ink.blendMode == .multiply && abs(group.opacity - 0.75) <= 1 / 255)
        #expect(pixelLayer(group.children.first).map { $0.isHidden && $0.x == 5 && $0.y == 900 } == true)
        #expect(try back.composite == ORAFixtures.pixels(3, 300, 1000) && back == image())
    }
    @Test func seededStacksRoundTripExactly() throws {
        var rng = SplitMix64(seed: 0x4C43_0008)
        let modes = BlendMode.allCases
        func node(_ depth: Int, _ i: Int) throws -> LayerNode {
            let name = "a&<>\"'\t\n层 \(i)", opacity = Float.random(in: 0...1, using: &rng), hidden = Bool.random(using: &rng)
            guard depth < 3, Int.random(in: 0..<3, using: &rng) == 0 else {
                return .pixels(PixelLayer(name: name, pixels: try ORAFixtures.pixels(rng.next(), Int.random(in: 1...5, using: &rng), 3),
                                          x: Int.random(in: -9...9, using: &rng), y: Int.random(in: -9...9, using: &rng), opacity: opacity,
                                          blendMode: modes[Int.random(in: 0..<modes.count, using: &rng)], isHidden: hidden))
            }
            return .group(LayerGroup(name: name, children: try (0..<Int.random(in: 0...3, using: &rng)).map { try node(depth + 1, $0) },
                                     opacity: opacity, blendMode: Bool.random(using: &rng) ? nil : .screen, isHidden: hidden))
        }
        for i in 0..<20 {
            let image = LayeredImage(width: 8, height: 6, nodes: try (0..<4).map { try node(0, $0) }, composite: try ORAFixtures.pixels(UInt64(i), 8, 6))
            #expect(try OpenRaster.read(OpenRaster.write(image, pixels: RawPixelCodec()), pixels: RawPixelCodec()) == image)
        }
    }
    @Test func extraEntriesKept() throws {
        let json = Data("{\"layers\":2}".utf8)
        #expect(try ZipStore.entries(written(extra: ["photo/document.json": json]))["photo/document.json"] == json)
    }
    @Test func extraKeyCollisionsThrow() throws {
        for path in ["mimetype", "stack.xml", "mergedimage.png", "Thumbnails/thumbnail.png", "data/0.png", "data/1.png"] {
            #expect(throws: CodecError.unsupported("extra entry \(path) collides with a standard entry")) { try written(extra: [path: Data()]) }
        }
    }
    @Test func thumbnailLongestSide() throws {
        let thumbnail = try RawPixelCodec().decodePNG(try #require(ZipStore.entries(written())["Thumbnails/thumbnail.png"]))
        #expect(thumbnail.height == 256 && thumbnail.width == 77, "300 x 1000 scaled by its longest side, the height")
    }
    @Test func refusesWhatOraCannotHold() throws {
        let base = try image(), pixels = try ORAFixtures.pixels(4)
        func with(_ layer: PixelLayer) -> LayeredImage { var i = base; i.nodes = [.pixels(layer)]; return i }
        var cases: [LayeredImage] = [Float.nan, -0.1, 1.5].map { with(PixelLayer(name: "o", pixels: pixels, opacity: $0)) }
        cases += [with(PixelLayer(name: "m", pixels: pixels, mask: PlacedMask(mask: try Mask(width: 1, height: 1)))),
                  with(PixelLayer(name: "c", pixels: pixels, clipsToBelow: true)), with(PixelLayer(name: "n\0", pixels: pixels)),
                  with(PixelLayer(name: "x", pixels: pixels, x: (1 << 30) + 1)), with(PixelLayer(name: "y", pixels: pixels, y: Int.min))]
        var other = base; other.profile = .displayP3; cases.append(other)
        other = base; other.bitsPerChannel = 16; cases.append(other)
        other = base; other.composite = nil; cases.append(other)
        for image in cases { #expect(throws: CodecError.self) { try OpenRaster.write(image, pixels: RawPixelCodec()) } }
    }
    @Test func nestingStopsWhereTheReaderDoes() throws {
        func nested(_ levels: Int) throws -> LayeredImage {
            var node = LayerNode.pixels(PixelLayer(name: "deep", pixels: try ORAFixtures.pixels(5)))
            for _ in 0..<levels { node = .group(LayerGroup(name: "g", children: [node])) }
            var image = try image(); image.nodes = [node]; return image
        }
        // The root stack and maxDepth - 1 groups make maxDepth stacks; the layer sits one below.
        let deepest = try nested(OpenRaster.maxDepth - 1)
        #expect(try OpenRaster.read(OpenRaster.write(deepest, pixels: RawPixelCodec()), pixels: RawPixelCodec()) == deepest)
        #expect(throws: CodecError.tooLarge("an element under \(OpenRaster.maxDepth - 1) groups")) {
            try OpenRaster.write(nested(OpenRaster.maxDepth), pixels: RawPixelCodec())
        }
    }
}
