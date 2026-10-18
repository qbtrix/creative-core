// PSD 16-bit channels and the ICC profile (resource 1039): big-endian samples, == round trips,
// unchanged 8-bit output, and damaged 16-bit files and resources throw a CodecError.
import CoreColor
import CoreRaster
import Foundation
import Testing

/// One image resource block from the spec: `8BIM`, id, padded Pascal name, length, data padded to even.
func psdResource(_ id: Int, _ data: [UInt8], name: String = "") -> [UInt8] {
    var w = BigEndian()
    let n = Array(name.utf8)
    w.ascii("8BIM"); w.u16(id)
    w.out += [UInt8(n.count)] + n + ((n.count + 1) % 2 == 1 ? [0] : [])
    w.u32(data.count); w.out += data + (data.count % 2 == 1 ? [0] : [])
    return w.out
}

/// A 16-bit PSD: one canvas-sized layer (transparency, colour and a 3 x 2 mask at (1, 1)) and
/// the merged image, every sample `sample(channel, x, y)` stored big-endian, raw or RLE.
func deepPSD(width: Int = 6, height: Int = 4, gray: Bool = false, rle: Bool = false, resources: [UInt8] = [],
             sample: (Int16, Int, Int) -> UInt16) -> Data {
    let colour: [Int16] = gray ? [0] : [0, 1, 2]
    func rows(_ id: Int16, _ w: Int, _ h: Int) -> [[UInt8]] { (0..<h).map { y in (0..<w).flatMap { x in
        let v = sample(id, x, y); return [UInt8(v >> 8), UInt8(v & 0xFF)] } } }
    func channel(_ id: Int16, _ w: Int, _ h: Int) -> [UInt8] {
        var b = BigEndian(); b.u16(rle ? 1 : 0); PSDFile.rows(rows(id, w, h), rle: rle, into: &b); return b.out
    }
    var record = PSDRecord(name: "Deep", bottom: height, right: width, channels: [-1] + colour + [-2])
    record.mask = (1, 1, 3, 4, 255, 0)
    let channels = record.channels.map { id in (id: id, bytes: id == -2 ? channel(id, 3, 2) : channel(id, width, height)) }
    var w = BigEndian()
    w.ascii("8BPS"); w.u16(1); w.out += [0, 0, 0, 0, 0, 0]
    for v in [colour.count + 1, 0, height, 0, width, 16, gray ? 1 : 3] { w.u16(v) }
    w.u32(0) // colour mode data
    w.u32(resources.count); w.out += resources
    w.sized { section in
        section.sized(pad: 2) { info in
            info.u16(-1); PSDFile.record(record, channels, into: &info) // one layer; the merged alpha is transparency
            channels.forEach { info.out += $0.bytes }
        }
        section.u32(0)
    }
    w.u16(rle ? 1 : 0)
    PSDFile.rows((colour + [-1]).flatMap { rows($0, width, height) }, rle: rle, into: &w)
    return Data(w.out)
}

/// Seeded 16-bit samples, with some transparent pixels.
func seededSamples(_ seed: UInt64) -> (Int16, Int, Int) -> UInt16 {
    var rng = SplitMix64(seed: seed)
    let table = (0..<64).map { _ in UInt16.random(in: 0...UInt16.max, using: &rng) }
    return { id, x, y in id == -1 && (x + y) % 5 == 0 ? 0 : table[((Int(id) + 2) * 13 + x * 5 + y * 3) & 63] }
}

/// FNV-1a, 64-bit: a fingerprint of bytes this suite pins.
func fnv1a(_ data: Data) -> UInt64 { data.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 } }

/// A gray profile: the D50 white and one gamma curve.
let grayProfile = ColorProfile(name: "g", isGray: true, toXYZD50: [0.9642, 1, 0.8249], curves: [.gamma(2.2)])

/// ICC bytes `ColorProfile(iccData:)` refuses: a printer-class gray profile, an RGB one whose
/// colourant tags are renamed to LUT tags (so it has A2B0 and no rXYZ, gXYZ or bXYZ), and junk.
func refusedProfiles() throws -> [[UInt8]] {
    var printer = [UInt8](try grayProfile.iccData())
    printer.replaceSubrange(12..<16, with: Array("prtr".utf8))
    var lut = [UInt8](try ColorProfile.displayP3.iccData())
    let tags = Int(lut[128]) << 24 | Int(lut[129]) << 16 | Int(lut[130]) << 8 | Int(lut[131])
    let renames = ["rXYZ": "A2B0", "gXYZ": "B2A0", "bXYZ": "zzzz"]
    for t in 0..<tags {
        let at = 132 + t * 12
        if let new = renames[String(decoding: lut[at..<at + 4], as: UTF8.self)] { lut.replaceSubrange(at..<at + 4, with: Array(new.utf8)) }
    }
    return [printer, lut, Array(repeating: 0x41, count: 200)]
}

@Suite struct PSDDeepTests {
    @Test func bigEndianSamples() throws {
        let file = deepPSD { id, x, _ in id == -1 ? 0xFFFF : id == -2 ? 0x8001 : [0x1234, 0xFE01, 0x00FF][Int(id)] &+ UInt16(x) }
        let image = try PSD.read(file)
        #expect(image.bitsPerChannel == 16)
        let layer = try #require(pixelLayer(image.nodes.first))
        let p = try layer.pixels.pixel(x: 2, y: 1)
        func linear(_ v: Int) -> Float { Float(TransferCurve.decode(Double(v) / 65535)) }
        #expect(p == RGBA(r: linear(0x1236), g: linear(0xFE03), b: linear(0x0101), a: 1), "big-endian: high byte first")
        #expect(try layer.mask?.mask.coverage(x: 0, y: 0) == Float(0x8001) / 65535)
        #expect(try image.composite?.pixel(x: 5, y: 3) == RGBA(r: linear(0x1239), g: linear(0xFE06), b: linear(0x0104), a: 1))
        #expect(try PSD.read(PSD.write(image)) == image, "the writer stores the same order")
    }

    @Test func sixteenBitRoundTrips() throws {
        for gray in [false, true] {
            for seed in UInt64(1)...4 {
                let raw = try PSD.read(deepPSD(gray: gray, sample: seededSamples(seed)))
                #expect(try PSD.read(deepPSD(gray: gray, rle: true, sample: seededSamples(seed))) == raw, "RLE rows over the samples' bytes")
                let written = try PSD.write(raw)
                #expect([UInt8](written)[22...23] == [0, 16], "the header says 16 bits")
                let back = try PSD.read(written)
                #expect(back == raw && back.bitsPerChannel == 16, "gray \(gray), seed \(seed): == at 16 bits")
            }
        }
        let gray = try PSD.read(deepPSD(gray: true, sample: seededSamples(9)))
        let p = try gray.composite?.pixel(x: 1, y: 2)
        #expect(p?.r == p?.g && p?.g == p?.b, "gray opens as grey")
    }

    @Test func profileRoundTrips() throws {
        let black = try PixelBuffer(width: 3, height: 2, fill: RGBA(r: 0, g: 0, b: 0, a: 1))
        for bits in [8, 16] {
            for profile in [ColorProfile.displayP3, .sRGB, .linearSRGB] {
                let image = LayeredImage(width: 3, height: 2, composite: black, bitsPerChannel: bits, profile: profile)
                let back = try PSD.read(PSD.write(image))
                #expect(back.profile == profile && back == image, "\(bits) bits, \(profile.name)")
            }
        }
        let icc = [UInt8](try ColorProfile.displayP3.iccData())
        let tagged = psdResource(1005, [1, 2, 3], name: "ab") + psdResource(1039, icc) + psdResource(1036, [9])
        #expect(try PSD.read(deepPSD(resources: tagged, sample: seededSamples(2))).profile == .displayP3)
        #expect(try PSD.read(deepPSD(resources: psdResource(1005, [1]), sample: seededSamples(2))).profile == nil)
    }

    @Test func grayProfileRoundTrips() throws {
        let icc = try grayProfile.iccData()
        let image = try PSD.read(deepPSD(gray: true, resources: psdResource(1039, [UInt8](icc)), sample: seededSamples(8)))
        #expect(try image.profile == ColorProfile(iccData: icc) && image.profile?.isGray == true)
        let written = try PSD.write(image)
        #expect([UInt8](written)[24...25] == [0, 1], "a gray profile writes a grayscale file")
        #expect(try PSD.read(written) == image)
        var tinted = image
        tinted.composite = try PixelBuffer(width: 6, height: 4, fill: RGBA(r: 0.5, g: 0.25, b: 0.5, a: 1))
        #expect(throws: CodecError.unsupported("the composite is not grey, so it cannot be saved with a gray colour profile")) {
            try PSD.write(tinted)
        }
    }

    @Test func unreadableProfileStillOpens() throws {
        for gray in [false, true] {
            let plain = try PSD.read(deepPSD(gray: gray, sample: seededSamples(10)))
            for icc in try refusedProfiles() {
                let image = try PSD.read(deepPSD(gray: gray, resources: psdResource(1039, icc), sample: seededSamples(10)))
                #expect(image == plain && image.profile == nil, "gray \(gray): the refused profile is dropped")
            }
        }
    }

    @Test func eightBitFilesUnchanged() throws {
        // Fingerprints of `PSD.write(PSD.read(fixture))` taken before 16-bit and profiles landed.
        let pinned: [String: UInt64] = ["layers.psd": 11_087_232_683_054_317_720, "gray.psd": 6_822_470_606_584_803_039,
                                        "nested.psd": 17_320_462_466_766_672_390]
        for (name, hash) in pinned {
            let image = try PSD.read(loadCodecFixture(name))
            #expect(image.bitsPerChannel == 8 && image.profile == nil, "\(name)")
            let written = try PSD.write(image)
            #expect(fnv1a(written) == hash, "\(name) writes \(fnv1a(written))")
            #expect([UInt8](written)[26..<34].allSatisfy { $0 == 0 }, "\(name): no colour mode data, no image resources")
        }
    }

    @Test func damagedDeepFilesThrow() throws {
        for file in [deepPSD(sample: seededSamples(3)), deepPSD(gray: true, rle: true, sample: seededSamples(4))] {
            for end in stride(from: 26, to: file.count - 1, by: 7) {
                #expect(psdError(file.prefix(end)) != nil, "truncated at \(end) throws a CodecError")
            }
        }
        var long = psdResource(1039, [1, 2, 3, 4])
        long.replaceSubrange(8..<12, with: [0x7F, 0xFF, 0xFF, 0xFF])
        #expect(kind(psdError(deepPSD(resources: long, sample: seededSamples(5)))) == "damaged", "a resource longer than its section")
        #expect(kind(psdError(deepPSD(resources: [0x38, 0x42, 0x49, 0x4D, 0x04], sample: seededSamples(5)))) == "damaged", "a cut resource header")
        var short = PSDFile.gray; short.depth = 16
        #expect(kind(psdError(short.data)) == "damaged", "8-bit sized planes in a 16-bit file")
        let icc = [UInt8](try ColorProfile.displayP3.iccData())
        let seeds = [deepPSD(rle: true, resources: psdResource(1039, icc), sample: seededSamples(6)),
                     deepPSD(gray: true, resources: psdResource(1005, [7], name: "x"), sample: seededSamples(7))]
        fuzz(mutations(of: seeds, count: 600, seed: 0xD16)) { _ = try PSD.read($0) }
    }
}
