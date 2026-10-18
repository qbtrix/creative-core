// ORA write then read (LC-8): layers, extra app entries, and a thumbnail 256 on its longest side.
import CoreRaster
import Foundation
import Testing

@Suite struct CodecRoundTripTests {
    // A tall canvas holding only what an ORA keeps (no masks or clipping).
    func written(extra: [String: Data] = [:]) throws -> Data {
        let ink = PixelLayer(name: "Ink", pixels: try ORAFixtures.pixels(1), x: 12, y: -3, opacity: 0.5, blendMode: .multiply)
        let hidden = PixelLayer(name: "Hidden", pixels: try ORAFixtures.pixels(2), x: 5, y: 900, isHidden: true)
        let image = LayeredImage(width: 300, height: 1000, nodes: [.group(LayerGroup(name: "Group", children: [.pixels(hidden)], opacity: 0.75)),
                                                                   .pixels(ink)], composite: try ORAFixtures.pixels(3, 300, 1000), profile: nil)
        return try OpenRaster.write(image, pixels: RawPixelCodec(), extra: extra)
    }
    @Test(.disabled("waits on LC-8")) func oraRoundTripsWithinOneStep() throws {
        let back = try OpenRaster.read(written(), pixels: RawPixelCodec())
        let ink = try #require(pixelLayer(back.nodes.last)), group = try #require(layerGroup(back.nodes.first))
        #expect(back.width == 300 && back.height == 1000 && back.profile == nil && back.nodes.count == 2)
        #expect(try ink.pixels == ORAFixtures.pixels(1) && ink.x == 12 && ink.y == -3 && abs(ink.opacity - 0.5) <= 1 / 255)
        #expect(ink.blendMode == .multiply && abs(group.opacity - 0.75) <= 1 / 255)
        #expect(pixelLayer(group.children.first).map { $0.isHidden && $0.x == 5 && $0.y == 900 } == true)
    }
    @Test(.disabled("waits on LC-8")) func extraEntriesKept() throws {
        let json = Data("{\"layers\":2}".utf8)
        #expect(StoredZip.entry("photo/document.json", in: try written(extra: ["photo/document.json": json])) == json)
    }
    @Test(.disabled("waits on LC-8")) func thumbnailLongestSide() throws {
        let thumbnail = try RawPixelCodec().decodePNG(try #require(StoredZip.entry("Thumbnails/thumbnail.png", in: try written())))
        #expect(thumbnail.height == 256 && thumbnail.width == 77, "300 x 1000 scaled by its longest side, the height")
    }
}
