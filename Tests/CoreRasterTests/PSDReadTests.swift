// PSDReadTests.swift: PSD read (LC-4) of PSDBytes' fixtures, and a named CodecError for each bad file.
import CoreColor
import CoreRaster
import Foundation
import Testing

@Suite struct PSDReadTests {
    func layers() throws -> LayeredImage { try PSD.read(loadCodecFixture("layers.psd")) }
    @Test func layersOpenInPlace() throws {
        let image = try layers(), base = try #require(pixelLayer(image.nodes.first))
        #expect(image.width == 1200 && image.height == 800 && image.bitsPerChannel == 8 && image.profile == nil && image.nodes.count == 5)
        #expect(base.name == "Base" && base.x == 20 && base.y == 10 && base.pixels.width == 64 && base.pixels.height == 48)
        #expect(base.opacity == 1 && base.blendMode == .normal && !base.clipsToBelow && base.mask == nil)
        #expect(near(try base.pixels.pixel(x: 3, y: 5), PSDFile.expected(3, 5)))
        let multiply = try #require(pixelLayer(layerGroup(image.nodes[1])?.children.last))
        #expect(abs(multiply.opacity - 0.6) < 1e-6 && multiply.blendMode == .multiply && multiply.x == 400)
        #expect(near(try multiply.pixels.pixel(x: 15, y: 2), PSDFile.expected(15, 2)), "raw channels")
        #expect(pixelLayer(image.nodes[3])?.clipsToBelow == true && pixelLayer(image.nodes[2])?.clipsToBelow == false)
        #expect(pixelLayer(image.nodes[4])?.name == "Ünïcode 层")
    }
    @Test func groupsNest() throws {
        let group = try #require(layerGroup(try layers().nodes[1]))
        #expect(group.name == "Group" && group.blendMode == nil && group.isOpen && !group.isHidden)
        #expect(group.children.map { pixelLayer($0)?.name } == ["Masked", "Multiply"])
        let nested = try PSD.read(loadCodecFixture("nested.psd"))
        let outer = try #require(layerGroup(nested.nodes.first)), inner = try #require(layerGroup(outer.children.last))
        #expect(nested.nodes.count == 2 && pixelLayer(nested.nodes.last)?.name == "C" && pixelLayer(outer.children.first)?.name == "A")
        #expect(inner.name == "Inner" && !inner.isOpen && inner.blendMode == .normal && inner.children.map { pixelLayer($0)?.name } == ["B"])
    }
    @Test func maskAtOffset() throws {
        let masked = try #require(pixelLayer(layerGroup(try layers().nodes[1])?.children.first)), mask = try #require(masked.mask)
        #expect(masked.x == 200 && masked.y == 100 && mask.x == 190 && mask.y == 90 && mask.defaultCoverage == 0 && !mask.isDisabled)
        #expect(mask.mask.width == 40 && mask.mask.height == 20)
        #expect(abs(try mask.mask.coverage(x: 5, y: 7) - Float(PSDFile.sample(5, 7, -2)) / 255) < 1e-6)
    }
    @Test func hiddenFlag() throws {
        let nodes = try layers().nodes
        #expect(pixelLayer(nodes[2])?.isHidden == true && pixelLayer(nodes[0])?.isHidden == false && pixelLayer(nodes[3])?.isHidden == false)
    }
    @Test func negativeCountHasAlpha() throws {
        let composite = try #require(try layers().composite), decode = { (v: Int) in Float(TransferCurve.decode(Double(v) / 255)) }
        #expect(try composite.width == 1200 && composite.height == 800 && composite.pixel(x: 10, y: 10).a == 0)
        #expect(near(try composite.pixel(x: 600, y: 300), RGBA(r: decode(44), g: decode(0x80), b: decode(0x40), a: 1)))
    }
    @Test func grayscaleOpensAsGrey() throws {
        let gray = try #require(pixelLayer(try PSD.read(loadCodecFixture("gray.psd")).nodes.first))
        let p = try gray.pixels.pixel(x: 4, y: 3), a = Float(PSDFile.sample(4, 3, -1)) / 255
        #expect(gray.x == 3 && gray.y == 2 && p.r == p.g && p.g == p.b && abs(p.a - a) < 1e-6)
        #expect(abs(p.r - Float(TransferCurve.decode(Double(PSDFile.sample(4, 3, 0)) / 255)) * a) < 1e-5)
    }
    @Test func unsupportedFilesThrowNamedErrors() {
        var file = PSDFile.layers(width: 120, height: 80)
        #expect(psdError(Data("8BPX".utf8) + file.data.dropFirst(4)) == .notThisFormat)
        file.version = 2; #expect(psdError(file.data) == .unsupported("large document format"))
        #expect([(4, 8), (3, 32), (9, 8)].allSatisfy { kind(psdError(PSDFile(depth: $0.1, mode: $0.0, records: PSDFile.gray.records).data)) == "unsupported" })
        var zipped = PSDFile.gray.records[0]
        for compression in [2, 3] {
            zipped.compression = compression
            #expect(psdError(PSDFile(records: [zipped]).data) == .unsupported("zip-compressed channel"))
        }
    }
    @Test func unbalancedDividersThrow() {
        let layer = PSDRecord.layer("A", top: 0, left: 0, height: 4, width: 4)
        for records in [[.divider, layer], [layer, .folder("Lone")], [.divider, .divider, layer, .folder("Inner")]] {
            #expect(kind(psdError(PSDFile(records: records).data)) == "damaged")
        }
    }
    @Test func refusesHuge() throws {
        #expect(kind(psdError(PSDFile(width: PSD.maxSide + 1).data)) == "tooLarge")
        #expect(kind(psdError(PSDFile(height: PSD.maxSide + 1).data)) == "tooLarge")
        var count = [UInt8](PSDFile.nested.data), long = count
        count.replaceSubrange(42..<44, with: [0x1F, 0x41]) // 8_001 layers
        long.replaceSubrange(34..<38, with: [0x7F, 0xFF, 0xFF, 0xFF]) // a section past the end
        #expect(kind(psdError(Data(count))) == "tooLarge" && kind(psdError(Data(long))) == "damaged")
        let gray = [UInt8](PSDFile.gray.data)
        func patched(_ at: Int, _ bytes: [UInt8]) -> Data { var b = gray; b.replaceSubrange(at..<(at + bytes.count), with: bytes); return Data(b) }
        #expect(kind(psdError(patched(42, [0x80, 0x00]))) == "tooLarge", "count 0x8000")
        #expect(kind(psdError(patched(14, [0, 0, 0x4E, 0x20, 0, 0, 0x4E, 0x20]))) == "tooLarge", "20000 x 20000 canvas")
        #expect(kind(psdError(patched(52, [0, 0, 0x40, 0x02, 0, 0, 0x40, 0x03]))) == "tooLarge", "16384 x 16384 layer")
        let wide = patched(44, [0x80, 0, 0, 0, 0, 0, 0, 0, 0x7F, 0xFF, 0xFF, 0xFF])
        #expect(["tooLarge", "damaged"].contains(kind(psdError(wide))), "Int32.min to Int32.max bounds")
        #expect(kind(psdError(PSDFile(width: PSD.maxSide, height: 1).data.prefix(26))) == "damaged", "maxSide passes the size check")
        let empty = PSDRecord(name: "e", channels: [], compression: 0)
        #expect(kind(psdError(PSDFile(records: Array(repeating: empty, count: PSD.maxLayers + 1)).data)) == "tooLarge")
        #expect(try PSD.read(PSDFile(records: Array(repeating: empty, count: PSD.maxLayers)).data).nodes.count == PSD.maxLayers)
        // No channel data: without the budget these open as `damaged` for the missing planes, not `tooLarge`.
        var masked = PSDRecord(name: "m", channels: [])
        masked.mask = (0, 0, 16_384, 16_384, 0, 0)
        #expect(psdError(PSDFile(records: [masked]).data) == .tooLarge("268438528 pixels over \(PSD.maxTotalPixels)"), "the mask alone fills the budget")
        let quarter = PSDRecord(name: "q", bottom: 8_000, right: 10_000, channels: [])
        #expect(kind(psdError(PSDFile(records: Array(repeating: quarter, count: 4)).data)) == "tooLarge", "four layers each under the budget")
        #expect(kind(psdError(PSDFile(records: Array(repeating: quarter, count: 3)).data)) == "damaged", "three fit, then lack channels")
    }
    @Test func layerSideBoundary() throws {
        for (h, w) in [(1, PSD.maxSide), (PSD.maxSide, 1)] {
            var edge = PSDRecord.layer("E", top: 0, left: 0, height: h, width: w)
            edge.compression = 0
            let layer = try #require(pixelLayer(try PSD.read(PSDFile(records: [edge]).data).nodes.first))
            let corner = try layer.pixels.pixel(x: w - 1, y: h - 1)
            #expect(layer.pixels.width == w && layer.pixels.height == h && near(corner, PSDFile.expected(w - 1, h - 1)))
            (edge.bottom, edge.right) = (edge.bottom + h / PSD.maxSide, edge.right + w / PSD.maxSide)
            #expect(kind(psdError(PSDFile(records: [edge]).data)) == "tooLarge", "\(edge.right) x \(edge.bottom)")
        }
    }
    @Test func groupDepthLimit() throws {
        func nest(_ depth: Int) -> Data {
            PSDFile(records: Array(repeating: .divider, count: depth) + [.layer("L", top: 0, left: 0, height: 1, width: 1)]
                    + Array(repeating: .folder("g"), count: depth)).data
        }
        var node = try PSD.read(nest(PSD.maxDepth)).nodes.first, depth = 0
        while let group = layerGroup(node) { depth += 1; node = group.children.first }
        #expect(depth == PSD.maxDepth && pixelLayer(node)?.name == "L" && PSD.maxDepth == OpenRaster.maxDepth)
        #expect(kind(psdError(nest(PSD.maxDepth + 1))) == "tooLarge")
    }
    @Test func repeatedChannelIdThrows() {
        var twice = PSDRecord.layer("T", top: 0, left: 0, height: 2, width: 2)
        twice.channels = [-1, 0, 0, 1, 2]
        #expect(psdError(PSDFile(records: [twice]).data) == .damaged("a channel id repeats in one layer"))
    }
    /// `file` with a merged image of colour and alpha from `PSDFile.sample`, then extra channels. Each extra RLE row is
    /// a run of 128 bytes in a narrower row, so decoding any of them throws `damaged`.
    func merged(_ file: PSDFile, rle: Bool) -> Data {
        let kept = (0..<4).flatMap { c in (0..<file.height).map { y in (0..<file.width).map { PSDFile.sample($0, y, c == 3 ? -1 : Int16(c)) } } }
        let extra = (file.channels - 4) * file.height
        var w = BigEndian(); w.u16(rle ? 1 : 0)
        if rle {
            let packed = kept.map(PSDFile.packBits)
            packed.forEach { w.u16($0.count) }; (0..<extra).forEach { _ in w.u16(2) }
            packed.forEach { w.out += $0 }; (0..<extra).forEach { _ in w.out += [0x81, 9] }
        } else {
            kept.forEach { w.out += $0 }; w.out += Array(repeating: 7, count: extra * file.width)
        }
        return file.data.dropLast(file.mergedImage.count) + w.out
    }
    @Test func mergedImageSkipsExtraChannels() throws {
        var file = PSDFile(channels: 56, width: 8, height: 4, records: [.layer("A", top: 0, left: 0, height: 2, width: 2)], negativeCount: true)
        for rle in [true, false] {
            let composite = try #require(try PSD.read(merged(file, rle: rle)).composite)
            for y in 0..<4 { for x in 0..<8 { #expect(near(try composite.pixel(x: x, y: y), PSDFile.expected(x, y)), "rle \(rle)") } }
        }
        let truncated = merged(file, rle: false).dropLast()
        #expect(kind(psdError(truncated)) == "damaged", "skipped raw planes must still be in the file")
        file.negativeCount = false
        let opaque = try #require(try PSD.read(merged(file, rle: true)).composite), decode = { (v: UInt8) in Float(TransferCurve.decode(Double(v) / 255)) }
        let p = try opaque.pixel(x: 5, y: 3)
        #expect(near(p, RGBA(r: decode(PSDFile.sample(5, 3, 0)), g: decode(PSDFile.sample(5, 3, 1)),
                             b: decode(PSDFile.sample(5, 3, 2)), a: 1)), "a positive count skips the alpha too")
    }
    @Test func maskDefaultAndDisabled() throws {
        var masked = PSDRecord.layer("M", top: 0, left: 0, height: 4, width: 4)
        (masked.mask, masked.channels, masked.blendKey) = ((1, 1, 3, 3, 255, 0x02), [-1, 0, 1, 2, -2], "scrn")
        let layer = try #require(pixelLayer(try PSD.read(PSDFile(records: [masked]).data).nodes.first))
        let mask = try #require(layer.mask)
        #expect(mask.defaultCoverage == 1 && mask.isDisabled && mask.x == 1 && mask.mask.width == 2 && layer.blendMode == .screen)
        masked.mask?.color = 128
        let odd = try #require(pixelLayer(try PSD.read(PSDFile(records: [masked]).data).nodes.first)?.mask)
        #expect(odd.defaultCoverage == Float(128) / 255, "any default colour byte reads as byte / 255")
    }
    @Test func unknownBlendKeyIsNormal() throws {
        var odd = PSDRecord.layer("O", top: 0, left: 0, height: 4, width: 4)
        odd.blendKey = "zzzz"
        #expect(pixelLayer(try PSD.read(PSDFile(records: [odd]).data).nodes.first)?.blendMode == .normal)
    }
}
