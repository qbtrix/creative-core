// CodecWalkTests.swift: KJ-LC, the layered-codecs walk (LC-9). A fixture
// opens, nothing is edited, it is saved as PSD and as ORA (through the raw
// test `PixelCodec`, which keeps every Float, so "equal" is `==`, tighter
// than 1/255), and each save reopens equal to what opened.
// What ORA cannot hold is part of the walk, so a loss is never silent:
// `layers.psd` has a mask and a clipped layer, which ORA has no way to store,
// so its ORA save throws a named error (OpenRasterWrite.swift); and ORA keeps
// no open or closed state, so `nested.psd`'s closed group reopens open.
// `gray.psd` holds only what both formats keep and reopens equal from both,
// and a third-party-style `.ora` reopens with its offsets.
import CoreRaster
import Foundation
import Testing

@Suite struct CodecWalkTests {
    func savedAsPSD(_ image: LayeredImage) throws -> LayeredImage { try PSD.read(PSD.write(image)) }
    func savedAsORA(_ image: LayeredImage) throws -> LayeredImage {
        try OpenRaster.read(OpenRaster.write(image, pixels: RawPixelCodec()), pixels: RawPixelCodec())
    }

    /// `nodes` with every group open: what ORA reopens, as it keeps no `isOpen`.
    func opened(_ nodes: [LayerNode]) -> [LayerNode] {
        nodes.map { node in
            guard case .group(var group) = node else { return node }
            group.isOpen = true
            group.children = opened(group.children)
            return .group(group)
        }
    }

    @Test func walk() throws {
        // layers.psd opens with every attribute PSDReadTests pins.
        let layers = try PSD.read(loadCodecFixture("layers.psd"))
        let group = try #require(layerGroup(layers.nodes[1]))
        let multiply = try #require(pixelLayer(group.children.last)), masked = try #require(pixelLayer(group.children.first))
        #expect(layers.width == 1200 && layers.height == 800 && layers.nodes.count == 5 && layers.composite != nil)
        #expect(masked.mask?.x == 190 && multiply.blendMode == .multiply && abs(multiply.opacity - 0.6) < 1e-6)
        #expect(pixelLayer(layers.nodes[2])?.isHidden == true && pixelLayer(layers.nodes[3])?.clipsToBelow == true)
        #expect(pixelLayer(layers.nodes[4])?.name == "Ünïcode 层")
        #expect(try savedAsPSD(layers) == layers)
        #expect(throws: CodecError.unsupported("a mask or clipping on \"Clipped\"")) { try savedAsORA(layers) }

        // gray.psd: both saves reopen equal, unedited.
        let gray = try PSD.read(loadCodecFixture("gray.psd"))
        #expect(gray.nodes.count == 1 && gray.composite != nil)
        #expect(try savedAsPSD(gray) == gray)
        #expect(try savedAsORA(gray) == gray)

        // nested.psd: PSD keeps the closed group; ORA reopens it open and keeps the rest.
        let nested = try PSD.read(loadCodecFixture("nested.psd"))
        var open = nested
        open.nodes = opened(nested.nodes)
        #expect(open != nested, "the fixture has a closed group")
        #expect(try savedAsPSD(nested) == nested)
        #expect(try savedAsORA(nested) == open)

        // A third-party-style ORA reopens from its own format with its offsets.
        let ora = try OpenRaster.read(loadCodecFixture("third-party-a.ora"), pixels: RawPixelCodec())
        #expect(pixelLayer(ora.nodes.last).map { $0.x == 12 && $0.y == -3 } == true)
        #expect(try savedAsORA(ora) == ora)
    }
}
