// PSD write (LC-7): what it writes reopens equal, every channel is RLE, and an
// image the format cannot hold throws a CodecError before any byte is written.
import CoreColor
import CoreRaster
import Foundation
import Testing

@Suite struct PSDWriteTests {
    func reopened(_ image: LayeredImage) throws -> LayeredImage { try PSD.read(PSD.write(image)) }
    func randomImage(_ seed: UInt64) throws -> LayeredImage {
        var rng = SplitMix64(seed: seed)
        func k() -> Int { Int.random(in: 0...255, using: &rng) }
        func node(_ depth: Int) throws -> LayerNode {
            if depth < 2, Bool.random(using: &rng) {
                return .group(LayerGroup(name: "g\(k())", children: try (0...depth).map { _ in try node(depth + 1) },
                                         opacity: Float(k()) / 255, isHidden: k() < 64, isOpen: k() < 128))
            }
            let v = Float(TransferCurve.decode(Double(k()) / 255)), pixels = try PixelBuffer(width: 3, height: 2, fill: RGBA(r: v, g: v, b: v, a: 1))
            let mask = k() < 128 ? PlacedMask(mask: try Mask(width: 2, height: 3, fill: Float(k()) / 255), x: k() % 30 - 6, y: k() % 20 - 4,
                                              defaultCoverage: k() < 128 ? 1 : 0, isDisabled: k() < 128) : nil
            return .pixels(PixelLayer(name: "p\(k())", pixels: pixels, x: k() % 24 - 4, y: 1, opacity: Float(k()) / 255,
                                      blendMode: BlendMode.allCases[k() % BlendMode.allCases.count], isHidden: k() < 64,
                                      clipsToBelow: k() < 64, mask: mask))
        }
        return LayeredImage(width: 24, height: 16, nodes: try (0..<4).map { _ in try node(0) }, composite: try PixelBuffer(width: 24, height: 16, fill: RGBA(r: 0, g: 0, b: 0, a: 1)), profile: nil)
    }
    @Test func fixtureAndSeededStacksRoundTrip() throws {
        let fixture = try PSD.read(loadCodecFixture("layers.psd"))
        #expect(try reopened(fixture) == fixture)
        var masks = (covered: 0, disabled: 0)
        for seed in UInt64(0)..<50 {
            let image = try randomImage(seed)
            #expect(try reopened(image) == image, "seed \(seed)")
            func walk(_ nodes: [LayerNode]) {
                for node in nodes {
                    if let m = pixelLayer(node)?.mask { masks.covered += m.defaultCoverage == 1 ? 1 : 0; masks.disabled += m.isDisabled ? 1 : 0 }
                    walk(layerGroup(node)?.children ?? [])
                }
            }
            walk(image.nodes)
        }
        #expect(masks.covered > 5 && masks.disabled > 5, "the seeded stacks carry masks with coverage 1 and disabled masks")
    }
    @Test func everyChannelIsRLE() throws {
        let solid = try PixelBuffer(width: 2000, height: 2000, fill: RGBA(r: 0, g: 0, b: 0, a: 1))
        let image = LayeredImage(width: 2000, height: 2000, nodes: [.pixels(PixelLayer(name: "s", pixels: solid))], composite: solid, profile: nil)
        #expect(try PSD.write(image).count < 1_000_000, "raw, the planes are over 28 MB; RLE rows of one value are about 34 bytes")
        let mask = PlacedMask(mask: try Mask(width: 1000, height: 1000, fill: 1))
        let masked = LayeredImage(width: 1, height: 1, nodes: [.pixels(PixelLayer(name: "m", pixels: try PixelBuffer(width: 1, height: 1), mask: mask))],
                                  composite: try PixelBuffer(width: 1, height: 1), profile: nil)
        #expect(try PSD.write(masked).count < 100_000, "a raw 1000 x 1000 mask channel is 1 MB")
        #expect(try reopened(masked) == masked)
    }
    @Test func headerMatchesTheSpecLayout() throws {
        let bytes = [UInt8](try PSD.write(try randomImage(3)))
        func u16(_ at: Int) -> Int { Int(bytes[at]) << 8 | Int(bytes[at + 1]) }
        #expect(Array(bytes.prefix(4)) == Array("8BPS".utf8) && u16(4) == 1 && bytes[6..<12].allSatisfy { $0 == 0 })
        #expect(u16(12) == 4 && u16(16) == 16 && u16(20) == 24 && u16(22) == 8 && u16(24) == 3, "4 channels, 16 x 24, 8-bit RGB")
        #expect(bytes[26..<34].allSatisfy { $0 == 0 }, "no colour mode data and no image resources")
        let empty = [UInt8](try PSD.write(LayeredImage(width: 2, height: 2, composite: try PixelBuffer(width: 2, height: 2))))
        #expect(Int(empty[12]) << 8 | Int(empty[13]) == 3, "no layers: RGB only")
    }
    @Test func groupsRoundTrip() throws {
        let nested = try PSD.read(loadCodecFixture("nested.psd"))
        #expect(try reopened(nested).nodes == nested.nodes)
    }
    @Test func opacityRoundTrips() throws {
        var image = try randomImage(1)
        for k in [1, 127, 153, 254] {
            image.nodes = [.pixels(PixelLayer(name: "k", pixels: try PixelBuffer(width: 1, height: 1), opacity: Float(k) / 255))]
            #expect(pixelLayer(try reopened(image).nodes.first)?.opacity == Float(k) / 255, "k \(k)")
            image.nodes = [.pixels(PixelLayer(name: "n", pixels: try PixelBuffer(width: 1, height: 1), opacity: (Float(k) - 0.3) / 255))]
            #expect(pixelLayer(try reopened(image).nodes.first)?.opacity == Float(k) / 255, "k - 0.3 rounds to the nearest byte, k \(k)")
        }
    }
    @Test func invalidValuesThrow() throws {
        let pixels = try PixelBuffer(width: 2, height: 2)
        func image(_ layer: PixelLayer, bits: Int = 8, width: Int = 4) -> LayeredImage {
            LayeredImage(width: width, height: 4, nodes: [.pixels(layer)], bitsPerChannel: bits)
        }
        let layer = PixelLayer(name: "v", pixels: pixels)
        var cases: [(String, LayeredImage)] = [Float.nan, -0.1, 1.5].map { o in
            var l = layer; l.opacity = o; return ("opacity \(o)", image(l))
        }
        var past = layer; past.x = Int(Int32.max) + 1
        var edge = layer; edge.x = Int(Int32.max)
        var huge = layer; huge.x = Int.max
        cases += [("x past Int32", image(past)), ("right edge past Int32", image(edge)), ("x Int.max", image(huge)),
                  ("12 bits", image(layer, bits: 12)), ("32 bits", image(layer, bits: 32)), ("width 0", image(layer, width: 0)),
                  ("width over maxSide", image(layer, width: PSD.maxSide + 1)),
                  ("group opacity NaN", LayeredImage(width: 4, height: 4, nodes: [.group(LayerGroup(name: "g", opacity: .nan))])),
                  ("a colour layer under a gray profile", LayeredImage(width: 4, height: 4, nodes: [.pixels(PixelLayer(name: "red",
                      pixels: try PixelBuffer(width: 1, height: 1, fill: RGBA(r: 1, g: 0, b: 0, a: 1))))], profile: grayProfile))]
        var masked = layer; masked.mask = PlacedMask(mask: try Mask(width: 1, height: 1), y: Int(Int32.min) - 1)
        cases.append(("mask y past Int32", image(masked)))
        for (what, bad) in cases { #expect(throws: CodecError.self, "\(what)") { try PSD.write(bad) } }
    }
}
