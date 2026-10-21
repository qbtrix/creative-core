// A test-only layered image file builder from the published spec. CORE_RASTER_WRITE_CODEC_FIXTURES=1 rewrites Fixtures/codecs.
import CoreColor
import CoreRaster
import Foundation
import Testing

struct BigEndian {
    var out: [UInt8] = []
    mutating func u16(_ v: Int) { out += [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
    mutating func u32(_ v: Int) { u16(v >> 16); u16(v) }
    mutating func ascii(_ s: String) { out += Array(s.utf8) }
    mutating func sized(pad: Int = 1, _ body: (inout BigEndian) -> Void) {
        var inner = BigEndian(); body(&inner)
        inner.out += Array(repeating: 0, count: (pad - inner.out.count % pad) % pad)
        u32(inner.out.count); out += inner.out
    }
}

/// One layer record. Channels: -1 transparency, -2 user mask, 0... colour. Flags 0x02 hides.
struct PSDRecord {
    var name: String, top = 0, left = 0, bottom = 0, right = 0, channels: [Int16] = [-1, 0, 1, 2]
    var blendKey = "norm", opacity: UInt8 = 255, clipping: UInt8 = 0, flags: UInt8 = 0x08
    var mask: (top: Int, left: Int, bottom: Int, right: Int, color: UInt8, flags: UInt8)?, unicodeName: String?
    /// `lsct`: 1 open, 2 closed, 3 bounding divider, and a blend key. Compression 0 raw, 1 RLE, 2 and 3 zip.
    var section: (type: Int, key: String?)?, compression = 1
    /// Further tagged blocks, written as given after `lsct`.
    var extra: [UInt8] = []
    static let divider = PSDRecord(name: "</Layer group>", section: (3, nil), compression: 0)
    static func folder(_ name: String, type: Int = 1, key: String = "pass") -> PSDRecord { PSDRecord(name: name, blendKey: key, section: (type, key), compression: 0) }
    static func layer(_ name: String, top: Int, left: Int, height: Int, width: Int) -> PSDRecord { PSDRecord(name: name, top: top, left: left, bottom: top + height, right: left + width) }
    var channelData: [(id: Int16, bytes: [UInt8])] {
        channels.map { id in
            let r = id == -2 ? mask.map { ($0.top, $0.left, $0.bottom, $0.right) } ?? (0, 0, 0, 0) : (top, left, bottom, right)
            var w = BigEndian(); w.u16(compression)
            PSDFile.rows((0..<max(0, r.2 - r.0)).map { y in (0..<max(0, r.3 - r.1)).map { PSDFile.sample($0, y, id) } },
                         rle: compression == 1, into: &w)
            return (id, w.out)
        }
    }
}

struct PSDFile {
    var version = 1, channels = 4, width = 64, height = 48, depth = 8, mode = 3, records: [PSDRecord] = []
    /// A negative layer count: the merged image's first alpha channel is its transparency.
    var negativeCount = false
    /// The image resources section's bytes.
    var resources: [UInt8] = []
    static func sample(_ x: Int, _ y: Int, _ id: Int16) -> UInt8 {
        id == -1 ? UInt8(255 - (x + y) % 64) : id == -2 ? UInt8((x * 11 + y * 3) % 256) : UInt8((x * 7 + y * 13 + Int(id) * 50) % 256)
    }
    func merged(_ x: Int, _ y: Int, _ c: Int) -> UInt8 {
        c >= (mode == 1 ? 1 : 3) ? (x < 100 && y < 100 ? 0 : 255) : [UInt8(y % 256), 0x80, 0x40][c]
    }
    static func rows(_ rows: [[UInt8]], rle: Bool, into w: inout BigEndian) {
        let packed = rle ? rows.map(packBits) : rows
        if rle { packed.forEach { w.u16($0.count) } }
        packed.forEach { w.out += $0 }
    }
    /// PackBits with runs of 2...128 (header 1 - n) and single literals (header 0).
    static func packBits(_ row: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [], i = 0
        while i < row.count {
            var run = 1
            while i + run < row.count, run < 128, row[i + run] == row[i] { run += 1 }
            out += [run > 1 ? UInt8(truncatingIfNeeded: 1 - run) : 0, row[i]]
            i += run
        }
        return out
    }
    var data: Data {
        var w = BigEndian()
        w.ascii("8BPS"); w.u16(version); w.out += [0, 0, 0, 0, 0, 0]
        for v in [channels, height >> 16, height, width >> 16, width, depth, mode, 0, 0] { w.u16(v) } // no mode data
        w.sized { $0.out += resources }
        let data = records.map(\.channelData)
        w.sized { section in
            section.sized(pad: 2) { info in
                info.u16(negativeCount ? -records.count : records.count)
                for (r, channels) in zip(records, data) { Self.record(r, channels, into: &info) }
                data.joined().forEach { info.out += $0.bytes }
            }
            section.u32(0) // global layer mask info
        }
        return Data(w.out + mergedImage)
    }
    /// The merged image section: every channel, RLE.
    var mergedImage: [UInt8] {
        var w = BigEndian(); w.u16(1)
        Self.rows((0..<channels).flatMap { c in (0..<height).map { y in (0..<width).map { merged($0, y, c) } } }, rle: true, into: &w)
        return w.out
    }
    static func record(_ r: PSDRecord, _ channels: [(id: Int16, bytes: [UInt8])], into w: inout BigEndian) {
        for v in [r.top, r.left, r.bottom, r.right] { w.u32(v) }
        w.u16(channels.count); for c in channels { w.u16(Int(c.id)); w.u32(c.bytes.count) }
        w.ascii("8BIM" + r.blendKey); w.out += [r.opacity, r.clipping, r.flags, 0]
        w.sized { e in
            e.sized { m in
                guard let k = r.mask else { return }
                for v in [k.top, k.left, k.bottom, k.right] { m.u32(v) }
                m.out += [k.color, k.flags, 0, 0]
            }
            e.u32(0) // blending ranges
            let name = Array(r.name.utf8.prefix(255))
            e.out += [UInt8(name.count)] + name + Array(repeating: 0, count: 3 - name.count % 4)
            if let u = r.unicodeName { e.ascii("8BIMluni"); e.sized(pad: 2) { b in b.u32(u.utf16.count); u.utf16.forEach { b.u16(Int($0)) } } }
            if let s = r.section { e.ascii("8BIMlsct"); e.sized { b in b.u32(s.type); if let key = s.key { b.ascii("8BIM" + key) } } }
            e.out += r.extra
        }
    }
    /// Bottom to top: Base; Group (Masked, Multiply at 60% raw); Hidden; Clipped (0x0C: bit 2 is not hidden); Unicode.
    static func layers(width: Int = 1200, height: Int = 800) -> PSDFile {
        var masked = PSDRecord.layer("Masked", top: 100, left: 200, height: 32, width: 40)
        (masked.mask, masked.channels) = ((90, 190, 110, 230, 0, 0), [-1, 0, 1, 2, -2])
        var multiply = PSDRecord.layer("Multiply", top: 300, left: 400, height: 16, width: 16)
        (multiply.blendKey, multiply.opacity, multiply.compression) = ("mul ", 153, 0)
        var hidden = PSDRecord.layer("Hidden", top: 40, left: 600, height: 20, width: 30), clipped = hidden
        (hidden.flags, clipped.name, clipped.clipping, clipped.flags) = (0x0A, "Clipped", 1, 0x0C)
        var unicode = PSDRecord.layer("Unicode", top: 700, left: 1100, height: 8, width: 12)
        unicode.unicodeName = "Ünïcode 层"
        return PSDFile(width: width, height: height, records: [.layer("Base", top: 10, left: 20, height: 48, width: 64), .divider,
                                                               masked, multiply, .folder("Group"), hidden, clipped, unicode], negativeCount: true)
    }
    static let gray = PSDFile(channels: 2, width: 32, height: 24, mode: 1,
                              records: [PSDRecord(name: "Gray", top: 2, left: 3, bottom: 14, right: 23, channels: [-1, 0])])
    /// Bottom to top: Outer (pass through, open) holding A and Inner (closed, normal) holding B; then C.
    static let nested = PSDFile(records: [.divider, .layer("A", top: 0, left: 0, height: 4, width: 4), .divider,
                                          .layer("B", top: 4, left: 4, height: 4, width: 4), .folder("Inner", type: 2, key: "norm"),
                                          .folder("Outer"), .layer("C", top: 8, left: 8, height: 4, width: 4)])
    static func expected(_ x: Int, _ y: Int) -> RGBA {
        let a = Float(sample(x, y, -1)) / 255, c = (0..<3).map { Float(TransferCurve.decode(Double(sample(x, y, Int16($0))) / 255)) * a }
        return RGBA(r: c[0], g: c[1], b: c[2], a: a)
    }
}

func psdError(_ data: Data) -> CodecError? { do { _ = try PSD.read(data); return nil } catch { return error as? CodecError } }
func kind(_ error: CodecError?) -> String? { error.map { String(String(describing: $0).prefix { $0 != "(" }) } }
func near(_ a: RGBA, _ b: RGBA) -> Bool { [a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a].allSatisfy { abs($0) <= 1e-5 } }
func pixelLayer(_ node: LayerNode?) -> PixelLayer? { if case .pixels(let l)? = node { l } else { nil } }
func layerGroup(_ node: LayerNode?) -> LayerGroup? { if case .group(let g)? = node { g } else { nil } }
func codecFixture(_ name: String) -> URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/codecs/" + name) }
func loadCodecFixture(_ name: String) throws -> Data { try Data(contentsOf: codecFixture(name)) }

@Test func codecFixtureFilesMatchTheBuilders() throws {
    let write = ProcessInfo.processInfo.environment["CORE_RASTER_WRITE_CODEC_FIXTURES"] == "1"
    for (name, bytes) in ["layers.psd": PSDFile.layers().data, "gray.psd": PSDFile.gray.data, "nested.psd": PSDFile.nested.data,
                          "third-party-a.ora": try ORAFixtures.a(), "third-party-b.ora": try ORAFixtures.b()] {
        if write { try bytes.write(to: codecFixture(name)) }
        #expect(try loadCodecFixture(name) == bytes, "\(name) differs from its builder")
    }
    #expect(PSDFile.packBits([1, 1, 1, 2, 4, 4] + Array(repeating: 9, count: 130)) == [0xFE, 1, 0, 2, 0xFF, 4, 0x81, 9, 0xFF, 9])
}
