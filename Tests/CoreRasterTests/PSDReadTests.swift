// PSDReadTests.swift: PSD read (LC-4) of PSDBytes' fixtures, and a named CodecError for each bad file.
import CoreColor
import CoreRaster
import Foundation
import Testing

@Suite struct PSDReadTests {
    func layers() throws -> LayeredImage { try PSD.read(loadCodecFixture("layers.psd")) }
    @Test(.disabled("waits on LC-4")) func layersOpenInPlace() throws {
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
    @Test(.disabled("waits on LC-4")) func groupsNest() throws {
        let group = try #require(layerGroup(try layers().nodes[1]))
        #expect(group.name == "Group" && group.blendMode == nil && group.isOpen && !group.isHidden)
        #expect(group.children.map { pixelLayer($0)?.name } == ["Masked", "Multiply"])
        let nested = try PSD.read(loadCodecFixture("nested.psd"))
        let outer = try #require(layerGroup(nested.nodes.first)), inner = try #require(layerGroup(outer.children.last))
        #expect(nested.nodes.count == 2 && pixelLayer(nested.nodes.last)?.name == "C" && pixelLayer(outer.children.first)?.name == "A")
        #expect(inner.name == "Inner" && !inner.isOpen && inner.blendMode == .normal && inner.children.map { pixelLayer($0)?.name } == ["B"])
    }
    @Test(.disabled("waits on LC-4")) func maskAtOffset() throws {
        let masked = try #require(pixelLayer(layerGroup(try layers().nodes[1])?.children.first)), mask = try #require(masked.mask)
        #expect(masked.x == 200 && masked.y == 100 && mask.x == 190 && mask.y == 90 && mask.defaultCoverage == 0 && !mask.isDisabled)
        #expect(mask.mask.width == 40 && mask.mask.height == 20)
        #expect(abs(try mask.mask.coverage(x: 5, y: 7) - Float(PSDFile.sample(5, 7, -2)) / 255) < 1e-6)
    }
    @Test(.disabled("waits on LC-4")) func hiddenFlag() throws {
        let nodes = try layers().nodes
        #expect(pixelLayer(nodes[2])?.isHidden == true && pixelLayer(nodes[0])?.isHidden == false && pixelLayer(nodes[3])?.isHidden == false)
    }
    @Test(.disabled("waits on LC-4")) func negativeCountHasAlpha() throws {
        let composite = try #require(try layers().composite), decode = { (v: Int) in Float(TransferCurve.decode(Double(v) / 255)) }
        #expect(try composite.width == 1200 && composite.height == 800 && composite.pixel(x: 10, y: 10).a == 0)
        #expect(near(try composite.pixel(x: 600, y: 300), RGBA(r: decode(44), g: decode(0x80), b: decode(0x40), a: 1)))
    }
    @Test(.disabled("waits on LC-4")) func grayscaleOpensAsGrey() throws {
        let gray = try #require(pixelLayer(try PSD.read(loadCodecFixture("gray.psd")).nodes.first))
        let p = try gray.pixels.pixel(x: 4, y: 3), a = Float(PSDFile.sample(4, 3, -1)) / 255
        #expect(gray.x == 3 && gray.y == 2 && p.r == p.g && p.g == p.b && abs(p.a - a) < 1e-6)
        #expect(abs(p.r - Float(TransferCurve.decode(Double(PSDFile.sample(4, 3, 0)) / 255)) * a) < 1e-5)
    }
    @Test(.disabled("waits on LC-4")) func unsupportedFilesThrowNamedErrors() {
        var file = PSDFile.layers(width: 120, height: 80)
        #expect(psdError(Data("8BPX".utf8) + file.data.dropFirst(4)) == .notThisFormat)
        file.version = 2; #expect(psdError(file.data) == .unsupported("large document format"))
        #expect([(4, 8), (3, 16), (9, 8)].allSatisfy { kind(psdError(PSDFile(depth: $0.1, mode: $0.0, records: PSDFile.gray.records).data)) == "unsupported" })
        var zipped = PSDFile.gray.records[0]; zipped.compression = 2
        #expect(psdError(PSDFile(records: [zipped]).data) == .unsupported("zip-compressed channel"))
    }
    @Test(.disabled("waits on LC-4")) func refusesHuge() {
        #expect(kind(psdError(PSDFile(width: PSD.maxSide + 1).data)) == "tooLarge")
        #expect(kind(psdError(PSDFile(height: PSD.maxSide + 1).data)) == "tooLarge")
        var count = [UInt8](PSDFile.nested.data), long = count
        count.replaceSubrange(42..<44, with: [0x1F, 0x41]) // 8_001 layers
        long.replaceSubrange(34..<38, with: [0x7F, 0xFF, 0xFF, 0xFF]) // a section past the end
        #expect(kind(psdError(Data(count))) == "tooLarge" && kind(psdError(Data(long))) == "damaged")
    }
}
