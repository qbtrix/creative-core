// PSD decoded pixels, bit for bit: every layer and merged sample opens as
// table[sample] * (alpha / maxSample), with alpha itself as the stored float,
// at 8 and 16 bits, grey and RGB, with and without alpha; and FNV-1a hashes
// of every decoded float's bits, pinned before the pointer-based decode loop,
// so the fast open returns exactly the pixels the per-sample loop did.
@testable import CoreRaster
import Foundation
import Testing

/// The bits of every float a file decodes to: each pixel layer's pixels and mask, then the merged image.
private func decodedBits(_ image: LayeredImage) -> [UInt32] {
    func walk(_ nodes: [LayerNode]) -> [UInt32] {
        nodes.flatMap { node -> [UInt32] in
            switch node {
            case .pixels(let l):
                l.pixels.components.map(\.bitPattern) + (l.mask.map { m in
                    (0..<m.mask.width * m.mask.height).map { (try? m.mask.coverage(x: $0 % m.mask.width, y: $0 / m.mask.width))?.bitPattern ?? 0 }
                } ?? [])
            case .group(let g): walk(g.children)
            }
        }
    }
    return walk(image.nodes) + (image.composite?.components.map(\.bitPattern) ?? [])
}

private func hash(_ bits: [UInt32]) -> UInt64 {
    fnv1a(Data(bits.flatMap { b in (0..<4).map { UInt8(truncatingIfNeeded: b >> ($0 * 8)) } }))
}

/// Seeded 8-bit pixels with alpha, saved and read back, as the budget fixture is built.
private func seeded8() throws -> Data {
    var rng = SplitMix64(seed: 0x50_5344_0D)
    var pixels = try PixelBuffer(width: 23, height: 17)
    for y in 0..<17 { for x in 0..<23 {
        let p = RGBA(r: .random(in: 0...1, using: &rng), g: .random(in: 0...1, using: &rng),
                     b: .random(in: 0...1, using: &rng), a: .random(in: 0...1, using: &rng))
        try pixels.setPixel(x: x, y: y, p.premultiplied())
    } }
    return try PSD.write(LayeredImage(width: 30, height: 20, nodes: [.pixels(PixelLayer(name: "S", pixels: pixels, x: 3, y: 2))]))
}

@Suite struct PSDDecodeTests {
    @Test func layerSamplesDecodeExactly() throws {
        for gray in [false, true] {
            let sample = seededSamples(gray ? 0xD1 : 0xD2)
            let layer = try #require(pixelLayer(try PSD.read(deepPSD(gray: gray, rle: true, sample: sample)).nodes.first))
            let c = layer.pixels.components
            for y in 0..<4 { for x in 0..<6 {
                let i = (y * 6 + x) * 4, a = Float(sample(-1, x, y)) / 65_535
                let want = (0..<3).map { PSD.linear16[Int(sample(gray ? 0 : Int16($0), x, y))] * a } + [a]
                #expect(c[i..<i + 4].map(\.bitPattern) == want.map(\.bitPattern), "16-bit gray \(gray) at \(x), \(y)")
            } }
        }
        let base = try #require(pixelLayer(try PSD.read(PSDFile.layers().data).nodes.first))
        let c = base.pixels.components
        for y in 0..<48 { for x in 0..<64 {
            let i = (y * 64 + x) * 4, a = Float(PSDFile.sample(x, y, -1)) / 255
            let want = (0..<3).map { PSD.linear[Int(PSDFile.sample(x, y, Int16($0)))] * a } + [a]
            #expect(c[i..<i + 4].map(\.bitPattern) == want.map(\.bitPattern), "8-bit at \(x), \(y)")
        } }
    }

    @Test func decodedBitsArePinned() throws {
        let files: [(String, Data, UInt64)] = [
            ("layers", PSDFile.layers().data, 0x2538_1fee_fbc8_cdd8),
            ("gray", PSDFile.gray.data, 0xdf5e_23de_c0e8_079f),
            ("nested", PSDFile.nested.data, 0xb2ac_e9ec_c915_39c5),
            ("seeded 8-bit", try seeded8(), 0x1365_cc17_7d06_bd65),
            ("16-bit RGB raw", deepPSD(sample: seededSamples(0xD3)), 0x26e6_c03d_78a4_5df3),
            ("16-bit RGB RLE", deepPSD(rle: true, sample: seededSamples(0xD4)), 0xefb0_7089_8315_ed5b),
            ("16-bit gray RLE", deepPSD(gray: true, rle: true, sample: seededSamples(0xD5)), 0xda63_ca47_ad2e_dfe3),
        ]
        for (name, data, pinned) in files {
            let got = hash(decodedBits(try PSD.read(data)))
            #expect(got == pinned, "\(name)")
        }
    }
}
