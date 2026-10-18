// OpenRaster read (LC-6) of third-party-style files: stored zip (PKWARE APPNOTE) and the OpenRaster stack.xml spec.
// StoredZip writes them independently of ZipStore (insertion order, another date), as another app would.
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
}

enum ORAFixtures {
    static let stackA = """
        <?xml version="1.0" encoding="UTF-8"?><image version="0.0.5" w="6" h="4"><stack><layer name="Ink" src="data/ink.png" x="12" y="-3" opacity="0.5" composite-op="svg:multiply"/>
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
    // stack.xml lists top first; nodes are bottom to top.
    @Test func offsetsKept() throws {
        let image = try open("third-party-a.ora"), ink = try #require(pixelLayer(image.nodes.last))
        #expect(image.width == 6 && image.height == 4 && image.profile == nil && image.nodes.count == 3)
        #expect(try image.composite == ORAFixtures.pixels(5))
        #expect(ink.name == "Ink" && ink.x == 12 && ink.y == -3 && ink.opacity == 0.5 && ink.blendMode == .multiply)
        #expect(try ink.pixels == ORAFixtures.pixels(1) && pixelLayer(image.nodes.first)?.name == "Paper")
        let group = try #require(layerGroup(image.nodes[1])), hidden = try #require(pixelLayer(group.children.last))
        #expect(group.name == "Group" && group.opacity == 0.75 && hidden.isHidden && hidden.x == 5 && hidden.y == 7)
        #expect(pixelLayer(group.children.first).map { $0.blendMode == .screen && !$0.isHidden && $0.y == 20 } == true)
    }
    @Test func visibleByDefault() throws {
        let image = try open("third-party-b.ora"), only = try #require(pixelLayer(image.nodes.first))
        #expect(try only.pixels == ORAFixtures.pixels(7) && image.nodes.count == 1 && only.name == "Only" && only.x == 3 && only.y == 4)
        #expect(!only.isHidden && only.opacity == 1 && only.blendMode == .normal && image.composite == nil)
    }
    @Test func missingSourceIsDamagedNamingIt() throws {
        let data = try ORAFixtures.a(stack: ORAFixtures.stackA.replacingOccurrences(of: "data/ink.png", with: "data/gone.png"))
        let error = #expect(throws: CodecError.self) { try OpenRaster.read(data, pixels: RawPixelCodec()) }
        #expect(kind(error) == "damaged" && String(describing: error).contains("data/gone.png"))
    }
    @Test func namesDecodeEntitiesAndDepthIsCapped() throws {
        let named = "<image w='2' h='2'><stack><layer src='a.png' name='Ink &amp; &lt;Wash&gt; &#233;&#x41;'/></stack></image>"
        let image = try OpenRaster.read(try ORAFixtures.zip(named, [("a.png", 8)]), pixels: RawPixelCodec())
        #expect(pixelLayer(image.nodes.first)?.name == "Ink & <Wash> \u{E9}A")
        func nested(_ depth: Int, closed: Bool = true) throws -> LayeredImage {
            let stacks = String(repeating: "<stack>", count: depth) + String(repeating: "</stack>", count: closed ? depth : 0)
            return try OpenRaster.read(try ORAFixtures.zip("<image w='2' h='2'>\(stacks)</image>", []), pixels: RawPixelCodec())
        }
        #expect(layerGroup(try nested(OpenRaster.maxDepth).nodes.first) != nil)
        for (depth, closed) in [(OpenRaster.maxDepth + 1, true), (100_000, false)] {
            let error = #expect(throws: CodecError.self) { try nested(depth, closed: closed) }
            #expect(kind(error) == "tooLarge")
        }
        for mimetype in [[("mimetype", Data("image/png".utf8))], []] {
            let wrong = StoredZip.archive(mimetype + [("stack.xml", Data(named.utf8))])
            #expect(throws: CodecError.notThisFormat) { try OpenRaster.read(wrong, pixels: RawPixelCodec()) }
        }
    }
    func read(_ stack: String, _ entries: [(String, Data)] = [("a.png", Data())]) throws -> LayeredImage {
        let layers = try entries.map { ($0.0, $0.1.isEmpty ? try RawPixelCodec().encodePNG(ORAFixtures.pixels(8), bitsPerChannel: 8) : $0.1) }
        return try OpenRaster.read(StoredZip.archive([("mimetype", Data("image/openraster".utf8)), ("stack.xml", Data(stack.utf8))] + layers),
                                   pixels: RawPixelCodec())
    }
    func failure(_ stack: String, _ entries: [(String, Data)] = [("a.png", Data())]) -> String {
        let error = #expect(throws: CodecError.self) { try read(stack, entries) }
        return kind(error).map { "\($0) \(String(describing: error))" } ?? "none"
    }
    @Test func refusesHuge() throws {
        let one = "<layer src='a.png'/>"
        for size in ["w='0' h='2'", "w='30001' h='2'", "w='-4' h='2'", "w='30000' h='30000'"] {
            #expect(failure("<image \(size)><stack>\(one)</stack></image>").hasPrefix("tooLarge"))
        }
        #expect(failure("<image w='2' h='2'><stack>\(String(repeating: one, count: 8_001))</stack></image>").hasPrefix("tooLarge"))
        let ihdr: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13] + Array("IHDR".utf8) + [0, 0, 0x9C, 0x40, 0, 0, 0, 10]
        #expect(failure("<image w='2' h='2'><stack>\(one)</stack></image>", [("a.png", Data(ihdr))]).hasPrefix("tooLarge"))
    }
    @Test func repeatedSourceThrows() {
        #expect(failure("<image w='2' h='2'><stack><layer src='a.png'/><layer src='a.png'/></stack></image>").contains("a.png repeats"))
    }
    @Test func compositeMatchesTheCanvas() throws {
        let merged = [("a.png", Data()), ("mergedimage.png", try RawPixelCodec().encodePNG(ORAFixtures.pixels(9, 2, 2), bitsPerChannel: 8))]
        #expect(try read("<image w='2' h='2'><stack><layer src='a.png'/></stack></image>", merged).composite == ORAFixtures.pixels(9, 2, 2))
        #expect(failure("<image w='3' h='2'><stack><layer src='a.png'/></stack></image>", merged).contains("canvas size"))
    }
    /// 1,000 central entries, each a different name, all pointing at one 64 KiB body.
    @Test func overlappingEntriesThrow() throws {
        let one = [UInt8](try ZipStore.archive(["0000": Data(repeating: 7, count: 1 << 16)], first: nil))
        let localCount = 30 + 4 + (1 << 16), entry = Array(one[localCount..<(localCount + 50)])
        let le = { (value: Int, count: Int) in (0..<count).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) } }
        var bytes = Array(one[..<localCount])
        for index in 0..<1_000 { bytes += entry[..<46] + Array(String(1_000 + index).suffix(4).utf8) }
        bytes += [0x50, 0x4B, 5, 6] + le(0, 4) + le(1_000, 2) + le(1_000, 2) + le(50_000, 4) + le(localCount, 4) + le(0, 2)
        #expect(throws: CodecError.damaged("entries overlap at 1001")) { try ZipStore.entries(Data(bytes)) }
    }
    @Test func attributesBounded() throws {
        func opacity(_ text: String) throws -> Float? {
            pixelLayer(try read("<image w='2' h='2'><stack><layer src='a.png' opacity='\(text)'/></stack></image>").nodes.first)?.opacity
        }
        #expect(try opacity("-1") == 0 && opacity("2") == 1 && opacity("0.25") == 0.25)
        for text in ["nan", "inf", "-inf", "half"] { #expect(failure("<image w='2' h='2'><stack><layer src='a.png' opacity='\(text)'/></stack></image>").hasPrefix("damaged")) }
        for x in ["99999999999999999999", "1073741825", "1.5"] { #expect(failure("<image w='2' h='2'><stack><layer src='a.png' x='\(x)'/></stack></image>").hasPrefix("damaged")) }
        let group = layerGroup(try read("<image w='2' h='2'><stack><stack x='1073741824'><layer src='a.png' x='-1073741823'/></stack></stack></image>").nodes.first)
        #expect(pixelLayer(group?.children.first)?.x == 1, "stack offsets add to their layers'")
    }
}
