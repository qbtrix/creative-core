// CodecShapeTests.swift: the layered-codec contract exists with its exact
// signatures, the PSD and OpenRaster stubs throw `unsupported("not built")`,
// and RawPixelCodec round-trips exactly and refuses bad bytes.
import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

private func sampleImage() throws -> LayeredImage {
    var pixels = try PixelBuffer(width: 3, height: 2, fill: RGBA(r: 0.2, g: 0.1, b: 0, a: 0.5))
    try pixels.setPixel(x: 2, y: 1, RGBA(r: 1, g: 0.5, b: 0.25, a: 1))
    let mask = PlacedMask(mask: try Mask(width: 2, height: 2, fill: 0.5), x: 1, y: -1,
                          defaultCoverage: 1, isDisabled: true)
    let layer = PixelLayer(name: "Ünïcode 层", pixels: pixels, x: -4, y: 7, opacity: 0.6,
                           blendMode: .multiply, isHidden: true, clipsToBelow: true, mask: mask)
    let group = LayerGroup(name: "Group", children: [.pixels(layer)], opacity: 0.5,
                           blendMode: nil, isHidden: false, isOpen: false)
    return LayeredImage(width: 10, height: 8, nodes: [.pixels(layer), .group(group)],
                        composite: pixels, bitsPerChannel: 8)
}

@Test func valuesKeepEveryAttribute() throws {
    let image = try sampleImage()
    #expect(image.width == 10 && image.height == 8 && image.bitsPerChannel == 8)
    guard case .pixels(let layer) = image.nodes.first, case .group(let group) = image.nodes.last else {
        Issue.record("nodes lost their order or kind")
        return
    }
    #expect(layer.name == "Ünïcode 层" && layer.x == -4 && layer.y == 7)
    #expect(layer.opacity == 0.6 && layer.blendMode == .multiply)
    #expect(layer.isHidden && layer.clipsToBelow)
    #expect(layer.mask?.x == 1 && layer.mask?.y == -1)
    #expect(layer.mask?.defaultCoverage == 1 && layer.mask?.isDisabled == true)
    #expect(group.blendMode == nil && !group.isOpen && group.opacity == 0.5)
    #expect(group.children == [.pixels(layer)])
    var changed = image
    changed.nodes.removeLast()
    #expect(changed != image)
}

@Test func defaultsAreNormalVisibleAndPassThrough() throws {
    let layer = PixelLayer(name: "a", pixels: try PixelBuffer(width: 1, height: 1))
    #expect(layer.x == 0 && layer.y == 0 && layer.opacity == 1 && layer.blendMode == .normal)
    #expect(!layer.isHidden && !layer.clipsToBelow && layer.mask == nil)
    let group = LayerGroup(name: "g")
    #expect(group.blendMode == nil && group.isOpen && group.children.isEmpty)
    #expect(LayeredImage(width: 1, height: 1).bitsPerChannel == 8)
}

@Test func stubsThrowNotBuilt() throws {
    let image = try sampleImage()
    let notBuilt = CodecError.unsupported("not built")
    let raw: any PixelCodec = RawPixelCodec()
    #expect(throws: notBuilt) { try PSD.read(Data([0x38, 0x42, 0x50, 0x53])) }
    #expect(throws: notBuilt) { try PSD.write(image) }
    #expect(throws: notBuilt) { try OpenRaster.read(Data(), pixels: raw) }
    #expect(throws: notBuilt) { try OpenRaster.write(image, pixels: raw) }
    #expect(throws: notBuilt) { try OpenRaster.write(image, pixels: raw, extra: ["photo/document.json": Data()]) }
    #expect(PSD.maxSide == 30_000 && PSD.maxLayers == 8_000)
}

@Test func codecErrorCasesAreDistinct() {
    let all: [CodecError] = [.notThisFormat, .damaged("x"), .unsupported("x"), .tooLarge("x"),
                             .compressedEntry("x"), .pixelCodec("x")]
    #expect(Set(all.map { "\($0)" }).count == all.count)
    #expect(CodecError.damaged("a") != CodecError.damaged("b"))
}

@Test func rawPixelCodecRoundTrips() throws {
    var rng = SplitMix64(seed: 0x4C43_0001)
    let codec = RawPixelCodec()
    for _ in 0..<20 {
        let width = Int.random(in: 1...9, using: &rng), height = Int.random(in: 1...9, using: &rng)
        var buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) }
        }
        let bits = Bool.random(using: &rng) ? 8 : 16
        let data = try codec.encodePNG(buffer, bitsPerChannel: bits)
        #expect(data.count == 13 + width * height * 16)
        #expect(try codec.decodePNG(data) == buffer)
    }
}

@Test func rawPixelCodecRefusesBadBytes() throws {
    let codec = RawPixelCodec()
    let buffer = try PixelBuffer(width: 2, height: 1, fill: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1))
    #expect(throws: CodecError.self) { try codec.encodePNG(buffer, bitsPerChannel: 12) }
    let good = [UInt8](try codec.encodePNG(buffer, bitsPerChannel: 8))
    // Every truncation, and one extra byte, throws instead of crashing.
    for cut in 0..<good.count {
        #expect(throws: CodecError.self) { try codec.decodePNG(Data(good[0..<cut])) }
    }
    #expect(throws: CodecError.self) { try codec.decodePNG(Data(good + [0])) }
    var badMagic = good
    badMagic[0] = 0
    #expect(throws: CodecError.self) { try codec.decodePNG(Data(badMagic)) }
    var badBits = good
    badBits[4] = 7
    #expect(throws: CodecError.self) { try codec.decodePNG(Data(badBits)) }
    var zeroWidth = good
    zeroWidth.replaceSubrange(5..<9, with: [0, 0, 0, 0])
    #expect(throws: CodecError.self) { try codec.decodePNG(Data(zeroWidth)) }
    var huge = good
    huge.replaceSubrange(5..<13, with: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
    #expect(throws: CodecError.self) { try codec.decodePNG(Data(huge)) }
    var nan = good
    nan.replaceSubrange(13..<17, with: [0x7F, 0xC0, 0, 0])
    #expect(throws: CodecError.pixelCodec("component 0 is not finite")) { try codec.decodePNG(Data(nan)) }
}
