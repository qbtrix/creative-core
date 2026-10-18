// PSD write (LC-7): what it writes reopens equal, and every channel is RLE.
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
            return .pixels(PixelLayer(name: "p\(k())", pixels: pixels, x: k() % 24 - 4, y: 1, opacity: Float(k()) / 255,
                                      blendMode: BlendMode.allCases[k() % BlendMode.allCases.count], isHidden: k() < 64))
        }
        return LayeredImage(width: 24, height: 16, nodes: try (0..<4).map { _ in try node(0) }, composite: try PixelBuffer(width: 24, height: 16, fill: RGBA(r: 0, g: 0, b: 0, a: 1)), profile: nil)
    }
    @Test(.disabled("waits on LC-7")) func fixtureAndSeededStacksRoundTrip() throws {
        let fixture = try PSD.read(loadCodecFixture("layers.psd"))
        #expect(try reopened(fixture) == fixture)
        for seed in UInt64(0)..<50 { let image = try randomImage(seed); #expect(try reopened(image) == image, "seed \(seed)") }
    }
    @Test(.disabled("waits on LC-7")) func everyChannelIsRLE() throws {
        let solid = try PixelBuffer(width: 2000, height: 2000, fill: RGBA(r: 0, g: 0, b: 0, a: 1))
        let image = LayeredImage(width: 2000, height: 2000, nodes: [.pixels(PixelLayer(name: "s", pixels: solid))], composite: solid, profile: nil)
        #expect(try PSD.write(image).count < 1_000_000, "raw, the planes are over 28 MB; RLE rows of one value are about 34 bytes")
    }
    @Test(.disabled("waits on LC-7")) func groupsRoundTrip() throws {
        let nested = try PSD.read(loadCodecFixture("nested.psd"))
        #expect(try reopened(nested).nodes == nested.nodes)
    }
    @Test(.disabled("waits on LC-7")) func opacityRoundTrips() throws {
        var image = try randomImage(1)
        for k in [1, 127, 153, 254] {
            image.nodes = [.pixels(PixelLayer(name: "k", pixels: try PixelBuffer(width: 1, height: 1), opacity: Float(k) / 255))]
            #expect(pixelLayer(try reopened(image).nodes.first)?.opacity == Float(k) / 255, "k \(k)")
        }
    }
}
