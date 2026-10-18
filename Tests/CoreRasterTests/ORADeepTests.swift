// ORA 16-bit layers and the profile.icc entry (colour-profiles CP-8): 16-bit
// layers round-trip exactly through the raw PixelCodec at 16 bits, the profile
// reads back, an 8-bit file without a profile is byte-for-byte what it was
// before, a profile ICC read refuses is dropped and an oversized entry throws.
import CoreColor
import CoreRaster
import Foundation
import Testing

@Suite struct ORADeepTests {
    /// Seeded samples on the 16-bit grid (k / 65535), so only a 16-bit file holds them.
    func deepPixels(_ seed: UInt64, _ width: Int = 5, _ height: Int = 3) throws -> PixelBuffer {
        var rng = SplitMix64(seed: seed), buffer = try PixelBuffer(width: width, height: height)
        func sample() -> Float { Float(UInt16.random(in: 0...65535, using: &rng)) / 65535 }
        for y in 0..<height { for x in 0..<width { try buffer.setPixel(x: x, y: y, RGBA(r: sample(), g: sample(), b: sample(), a: sample())) } }
        return buffer
    }
    func image(bits: Int, profile: ColorProfile?) throws -> LayeredImage {
        let top = PixelLayer(name: "Top", pixels: try deepPixels(1), x: 3, y: -2, opacity: 0.5, blendMode: .screen)
        let inner = PixelLayer(name: "Inner", pixels: try deepPixels(2, 4, 4), x: 1, y: 1)
        return LayeredImage(width: 8, height: 6, nodes: [.group(LayerGroup(name: "G", children: [.pixels(inner)])), .pixels(top)],
                            composite: try deepPixels(3, 8, 6), bitsPerChannel: bits, profile: profile)
    }
    /// IHDR bit depth (byte 24, PNG spec 11.2.2) of each PNG entry.
    func depths(_ ora: Data) throws -> [String: UInt8] {
        try ZipStore.entries(ora).filter { $0.key.hasSuffix(".png") }.mapValues { [UInt8]($0)[24] }
    }

    @Test func sixteenBitsKept() throws {
        let deep = try image(bits: 16, profile: nil)
        let ora = try OpenRaster.write(deep, pixels: RawPixelCodec())
        let layerDepths = try depths(ora).filter { $0.key != "Thumbnails/thumbnail.png" }
        #expect(layerDepths.count == 3 && layerDepths.values.allSatisfy { $0 == 16 }, "\(layerDepths)")
        let back = try OpenRaster.read(ora, pixels: RawPixelCodec())
        #expect(back.bitsPerChannel == 16 && back.profile == nil)
        #expect(back == deep)
    }

    @Test func profileEntry() throws {
        for (bits, profile) in [(8, ColorProfile.displayP3), (16, ColorProfile.sRGB)] {
            let tagged = try image(bits: bits, profile: profile)
            let ora = try OpenRaster.write(tagged, pixels: RawPixelCodec())
            #expect(try ZipStore.entries(ora)[OpenRaster.profilePath] == profile.iccData())
            let back = try OpenRaster.read(ora, pixels: RawPixelCodec())
            #expect(back.profile == profile && back.bitsPerChannel == bits)
            #expect(back == tagged)
        }
        #expect(throws: CodecError.unsupported("extra entry profile.icc collides with a standard entry")) {
            try OpenRaster.write(image(bits: 8, profile: nil), pixels: RawPixelCodec(), extra: [OpenRaster.profilePath: Data([1])])
        }
    }

    @Test func eightBitFileUnchanged() throws {
        let plain = try image(bits: 8, profile: nil)
        let ora = try OpenRaster.write(plain, pixels: RawPixelCodec())
        // FNV-1a 64 of the bytes the writer produced before 16-bit and profiles (dev at 168c73d).
        let hash = ora.reduce(0xCBF2_9CE4_8422_2325 as UInt64) { ($0 ^ UInt64($1)) &* 0x0100_0000_01B3 }
        #expect(ora.count == 3_190 && hash == 0x0C0A_65DE_1C16_9D81,"\(ora.count) bytes, hash \(String(hash, radix: 16))")
        #expect(try ZipStore.entries(ora)[OpenRaster.profilePath] == nil && depths(ora).values.allSatisfy { $0 == 8 })
        let back = try OpenRaster.read(ora, pixels: RawPixelCodec())
        #expect(back.bitsPerChannel == 8 && back.profile == nil && back == plain)
    }

    @Test func damagedProfileThrows() throws {
        var files = try ZipStore.entries(OpenRaster.write(image(bits: 16, profile: .displayP3), pixels: RawPixelCodec()))
        let icc = try #require(files[OpenRaster.profilePath])
        func ora(_ profile: Data) throws -> Data {
            files[OpenRaster.profilePath] = profile
            return try ZipStore.archive(files, first: "mimetype")
        }
        let plain = try OpenRaster.read(ora(Data()), pixels: RawPixelCodec())
        for refused in try [icc.prefix(100)] + refusedProfiles().map({ Data($0) }) {
            let back = try OpenRaster.read(ora(Data(refused)), pixels: RawPixelCodec())
            #expect(back.profile == nil && back.nodes == plain.nodes, "a profile ICC read refuses is dropped, as PSD drops it")
        }
        #expect(throws: CodecError.tooLarge("profile.icc is \(OpenRaster.maxProfileBytes + 1) bytes")) {
            try OpenRaster.read(ora(icc + Data(count: OpenRaster.maxProfileBytes + 1 - icc.count)), pixels: RawPixelCodec())
        }
        fuzz(try mutations(of: [icc], count: 500, seed: 0x0EA8).map(ora)) { _ = try OpenRaster.read($0, pixels: RawPixelCodec()) }
        // A profile iccData cannot write, and a depth other than 8 or 16, throw before anything is encoded.
        let unwritable = ColorProfile(name: "bad", isGray: false, toXYZD50: [1, 2], curves: [])
        #expect(throws: CodecError.self) { try OpenRaster.write(image(bits: 8, profile: unwritable), pixels: RawPixelCodec()) }
        #expect(throws: CodecError.unsupported("12 bits per channel")) { try OpenRaster.write(image(bits: 12, profile: nil), pixels: RawPixelCodec()) }
    }
}
