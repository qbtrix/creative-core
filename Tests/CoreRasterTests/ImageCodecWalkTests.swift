// ImageCodecWalkTests.swift: KJ-IC, the image-codecs walk (IC-9), over the
// spec-built fixtures only (PNGFixtures, JPEGFixtures; no decoder made any of
// them). Every PNG colour type and depth pair the spec allows, plain and
// Adam7, decodes to its reference pixels and, re-encoded as RGBA (16-bit for
// a 16-bit source, else 8-bit), reopens `==`; three of those pictures saved as
// an ORA through `PNGCodec` reopen as the same layers; every JPEG fixture
// (grey, 4:4:4, 4:2:2, 4:2:0, restarts, progressive) decodes within a mean of
// 1/255 and a maximum of 4/255 of its A.3.3 reference and, re-encoded at
// quality 90, reopens the same size within a mean of 3/255 (grey and 4:2:0;
// the writer is 4:2:0 only, so 4:4:4 and 4:2:2 chroma texture is lost by
// design and they hold a measured 8/255); an EXIF-rotated fixture reports
// orientation 6.
@testable import CoreRaster
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct ImageCodecWalkTests {
    typealias P = PNGFixtures
    typealias J = JPEGFixtures

    /// The mean difference of two buffers' sRGB-encoded colour, in levels of 255; infinite for different sizes.
    func meanLevels(_ a: PixelBuffer, _ b: PixelBuffer) throws -> Double {
        guard a.width == b.width, a.height == b.height else { return .infinity }
        var total = 0.0
        for i in 0..<(a.width * a.height) {
            let p = try a.pixel(x: i % a.width, y: i / a.width), q = try b.pixel(x: i % a.width, y: i / a.width)
            for (u, v) in [(p.r, q.r), (p.g, q.g), (p.b, q.b)] { total += abs(TransferCurve.encode(Double(u)) - TransferCurve.encode(Double(v))) * 255 }
        }
        return total / Double(3 * a.width * a.height)
    }

    @Test func walk() throws {
        // PNG: 9 x 9 fills every Adam7 pass and leaves pad bits in each 1-, 2- and 4-bit row.
        let png = PNGReadTests()
        var decoded: [String: PixelBuffer] = [:]
        for (colorType, depth) in PNGReadTests.pairs {
            for interlaced in [false, true] {
                let note = "type \(colorType) depth \(depth)\(interlaced ? " Adam7" : "")"
                let pixels = P.ramp(9, 9, channels: P.channels(colorType), depth: depth)
                let read = try PNG.read(png.file(pixels, colorType, depth, interlaced: interlaced))
                #expect(try P.maxDifference(read, png.expected(pixels, colorType, depth)) <= 1e-6, "\(note) decodes")
                let again = try PNG.read(PNG.write(read, bitsPerChannel: depth == 16 ? 16 : 8))
                #expect(again == read, "\(note) re-encoded as RGBA reopens equal")
                decoded[note] = read
            }
        }
        #expect(decoded.count == 30)

        // ORA: three decoded fixtures as layers, written and reread through PNGCodec.
        let names = ["type 0 depth 8", "type 2 depth 8 Adam7", "type 3 depth 8"]
        let layers = try names.enumerated().map { i, name in
            PixelLayer(name: name, pixels: try #require(decoded[name]), x: i, y: -i)
        }
        let image = LayeredImage(width: 9, height: 9, nodes: layers.map { .pixels($0) }, composite: try #require(decoded["type 6 depth 8"]))
        let reopened = try OpenRaster.read(OpenRaster.write(image, pixels: PNGCodec()), pixels: PNGCodec())
        #expect(reopened.nodes.count == 3 && reopened.nodes == image.nodes, "the ORA reopens with the same layers")

        // JPEG: each fixture within 1/255 mean and 4/255 max of its reference, then quality 90 within 3/255 mean.
        // JPEG.write is 4:2:0 only, so the 4:4:4 and 4:2:2 fixtures' full-resolution chroma texture (seeded chroma AC)
        // is averaged away by design: they hold 8/255 (measured 4.1 to 6.8), and 3/255 holds for what 4:2:0 carries.
        let s = JPEGReadTests.samplings
        let frames: [(String, J.Frame, (J.Frame) -> Data)] = [
            ("grey", J.Frame(width: 21, height: 9, block: J.seeded(0x91)), { J.baseline($0) }),
            ("4:4:4", J.Frame(width: 37, height: 21, sampling: s[0], block: J.seeded(0x92)), { J.baseline($0) }),
            ("4:2:2", J.Frame(width: 37, height: 21, sampling: s[1], block: J.seeded(0x93)), { J.baseline($0) }),
            ("4:2:0", J.Frame(width: 37, height: 21, sampling: s[2], block: J.seeded(0x94)), { J.baseline($0) }),
            ("4:2:0 restart 2", J.Frame(width: 48, height: 40, sampling: s[2], block: J.seeded(0x95)), { J.baseline($0, restart: 2) }),
            ("progressive 4:2:0", J.Frame(width: 37, height: 21, sampling: s[2], block: J.seeded(0x96)), { J.progressive($0) }),
            ("progressive 4:2:2 restart 3", J.Frame(width: 48, height: 40, sampling: s[1], block: J.seeded(0x97)), { J.progressive($0, restart: 3) }),
        ]
        for (note, frame, coded) in frames {
            let data = coded(frame), e = try J.error(data, frame)
            #expect(e.mean <= 1 && e.max <= 4, "\(note): mean \(e.mean), max \(e.max) levels")
            let read = try JPEG.read(data), again = try JPEG.read(JPEG.write(read, quality: 90))
            let mean = try meanLevels(read, again)
            let carried = frame.sampling.count == 1 || frame.sampling[0] == (2, 2)
            print("walk \(note) at quality 90: mean \(mean) levels\(carried ? "" : " (finer chroma than 4:2:0)")")
            #expect(again.width == read.width && again.height == read.height, "\(note) at quality 90 reopens the same size")
            #expect(mean.isFinite && mean <= (carried ? 3 : 8), "\(note) at quality 90: mean \(mean) levels")
        }

        // EXIF: orientation 6 is reported, not applied.
        let turned = J.Frame(width: 13, height: 7, sampling: s[1], block: J.seeded(0x98))
        let rotated = J.baseline(turned, orientation: 6)
        #expect(try JPEG.info(rotated).orientation == 6)
        #expect(try JPEG.read(rotated) == JPEG.read(J.baseline(turned)))
    }
}
