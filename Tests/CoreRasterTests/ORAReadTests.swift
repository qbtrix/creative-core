// OpenRaster read (LC-6) of third-party-style files: stored zip (PKWARE APPNOTE) and the OpenRaster stack.xml spec.
import CoreRaster
import Foundation
import Testing

enum StoredZip {
    static func archive(_ entries: [(String, Data)]) -> Data {
        func le(_ v: Int, _ n: Int) -> [UInt8] { (0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) } }
        var out: [UInt8] = [], central: [UInt8] = []
        for (name, data) in entries {
            let crc = data.reduce(~UInt32(0)) { c, byte in (0..<8).reduce(c ^ UInt32(byte)) { c, _ in c & 1 == 1 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 } }
            let common = le(10, 2) + le(0, 6) + le(0x5A21, 2) + le(Int(~crc), 4) + le(data.count, 4) + le(data.count, 4) + le(name.utf8.count, 4)
            central += le(0x0201_4B50, 4) + le(20, 2) + common + le(0, 10) + le(out.count, 4) + Array(name.utf8)
            out += le(0x0403_4B50, 4) + common + Array(name.utf8) + data
        }
        return Data(out + central + le(0x0605_4B50, 4) + le(0, 4) + le(entries.count, 2) + le(entries.count, 2) + le(central.count, 4) + le(out.count, 4) + le(0, 2))
    }
    static func entry(_ name: String, in data: Data) -> Data? {
        let b = [UInt8](data), key = Array(name.utf8)
        let local = { (at: Int) in Array(b[(at - 30)..<(at - 26)]) == [0x50, 0x4B, 3, 4] && Array(b[at..<(at + key.count)]) == key }
        guard let at = (30..<max(30, b.count - key.count + 1)).first(where: local) else { return nil }
        let u = { (o: Int) in (0..<4).reduce(0) { $0 | Int(b[at - 30 + o + $1]) << (8 * $1) } }
        let start = at + key.count + (u(28) & 0xFFFF), size = u(18)
        return start + size <= b.count ? Data(b[start..<(start + size)]) : nil
    }
}

enum ORAFixtures {
    static let stackA = """
        <?xml version="1.0" encoding="UTF-8"?><image version="0.0.5" w="64" h="48"><stack><layer name="Ink" src="data/ink.png" x="12" y="-3" opacity="0.5" composite-op="svg:multiply"/>
        <stack name="Group" opacity="0.75"><layer name="Hidden" src="data/hidden.png" x="5" y="7" visibility="hidden"/><layer name="Inner" src="data/inner.png" x="0" y="20" composite-op="svg:screen"/></stack>
        <layer name="Paper" src="data/paper.png" x="0" y="0" opacity="1.0" visibility="visible" composite-op="svg:src-over"/></stack></image>
        """
    static func pixels(_ seed: UInt64, _ width: Int = 6, _ height: Int = 4) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed), buffer = try PixelBuffer(width: width, height: height)
        for y in 0..<height { for x in 0..<width { try buffer.setPixel(x: x, y: y, randomPixel(&rng).premultiplied()) } }
        return buffer
    }
    static func zip(_ stack: String, _ layers: [(String, UInt64)]) throws -> Data {
        StoredZip.archive([("mimetype", Data("image/openraster".utf8)), ("stack.xml", Data(stack.utf8))]
            + (try layers.map { ($0.0, try RawPixelCodec().encodePNG(pixels($0.1), bitsPerChannel: 8)) }))
    }
    /// Every entry another app writes: the layers, a merged image and a thumbnail.
    static func a(stack: String = stackA) throws -> Data {
        try zip(stack, [("data/ink.png", 1), ("data/hidden.png", 2), ("data/inner.png", 3), ("data/paper.png", 4), ("mergedimage.png", 5), ("Thumbnails/thumbnail.png", 6)])
    }
    /// The least a file holds: single quotes, no optional attributes, an unknown element.
    static func b() throws -> Data {
        try zip("<?xml version='1.0'?><image w='16' h='16'><stack><text>skip</text><layer src='layer0.png' name='Only' x='3' y='4'/></stack></image>", [("layer0.png", 7)])
    }
}

@Suite struct ORAReadTests {
    func open(_ name: String) throws -> LayeredImage { try OpenRaster.read(loadCodecFixture(name), pixels: RawPixelCodec()) }
    @Test(.disabled("waits on LC-6")) func offsetsKept() throws {
        let image = try open("third-party-a.ora"), ink = try #require(pixelLayer(image.nodes.last))
        #expect(image.width == 64 && image.height == 48 && image.profile == nil && image.nodes.count == 3)
        #expect(ink.name == "Ink" && ink.x == 12 && ink.y == -3 && ink.opacity == 0.5 && ink.blendMode == .multiply)
        #expect(try ink.pixels == ORAFixtures.pixels(1) && pixelLayer(image.nodes.first)?.name == "Paper")
        let group = try #require(layerGroup(image.nodes[1])), hidden = try #require(pixelLayer(group.children.last))
        #expect(group.name == "Group" && group.opacity == 0.75 && hidden.isHidden && hidden.x == 5 && hidden.y == 7)
        #expect(pixelLayer(group.children.first).map { $0.blendMode == .screen && !$0.isHidden && $0.y == 20 } == true)
    }
    @Test(.disabled("waits on LC-6")) func visibleByDefault() throws {
        let image = try open("third-party-b.ora"), only = try #require(pixelLayer(image.nodes.first))
        #expect(try only.pixels == ORAFixtures.pixels(7) && image.nodes.count == 1 && only.name == "Only" && only.x == 3 && only.y == 4)
        #expect(!only.isHidden && only.opacity == 1 && only.blendMode == .normal)
    }
    @Test(.disabled("waits on LC-6")) func missingSourceIsDamagedNamingIt() throws {
        let data = try ORAFixtures.a(stack: ORAFixtures.stackA.replacingOccurrences(of: "data/ink.png", with: "data/gone.png"))
        let error = #expect(throws: CodecError.self) { try OpenRaster.read(data, pixels: RawPixelCodec()) }
        #expect(kind(error) == "damaged" && String(describing: error).contains("data/gone.png"))
    }
}
