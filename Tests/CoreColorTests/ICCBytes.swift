// ICCBytes.swift: builds ICC profiles field by field from the published spec (ICC.1:2010,
// whose section numbers these are, and ICC.1:2001-04 for v2), so no vendor's file is copied.
// Every value is chosen here; `expected` is what a reader must get back, at each field's precision.
import CoreColor
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Big-endian field writers and the tag types the ICC suites need.
enum ICC {
    static func u32(_ v: UInt32) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
    static func u16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(truncatingIfNeeded: v)] }
    static func sig(_ s: String) -> [UInt8] { Array((s + "    ").utf8.prefix(4)) }
    static func zeros(_ n: Int) -> [UInt8] { [UInt8](repeating: 0, count: n) }
    /// s15Fixed16Number (4.6): the value times 65536, rounded, two's complement.
    static func s15(_ v: Double) -> [UInt8] { u32(UInt32(bitPattern: Int32((v * 65536).rounded()))) }
    /// What an s15Fixed16Number, a u8Fixed8Number and a uInt16 table entry store for `v`.
    static func q15(_ v: Double) -> Double { (v * 65536).rounded() / 65536 }
    static func q8(_ v: Double) -> Double { (v * 256).rounded() / 256 }
    static func q16(_ v: Double) -> Double { (v * 65535).rounded() / 65535 }
    /// A tag type's signature and the four reserved bytes every tag type starts with (10.1).
    static func type(_ s: String) -> [UInt8] { sig(s) + zeros(4) }

    static func xyz(_ x: Double, _ y: Double, _ z: Double) -> [UInt8] { type("XYZ ") + s15(x) + s15(y) + s15(z) }
    /// curveType (10.6): count 0 is identity, 1 a u8Fixed8 gamma, n a table of uInt16 over 65535.
    static func curv(gamma: Double) -> [UInt8] { type("curv") + u32(1) + u16(UInt16((gamma * 256).rounded())) }
    static func curv(table: [Double]) -> [UInt8] {
        type("curv") + u32(UInt32(table.count)) + table.flatMap { u16(UInt16(($0 * 65535).rounded())) }
    }
    /// parametricCurveType (10.18): function type 0 to 4 and its 1, 3, 4, 5 or 7 parameters.
    static func para(_ function: UInt16, _ params: [Double]) -> [UInt8] {
        type("para") + u16(function) + zeros(2) + params.flatMap(s15)
    }
    /// s15Fixed16ArrayType (10.22), as the `chad` tag uses it.
    static func sf32(_ values: [Double]) -> [UInt8] { type("sf32") + values.flatMap(s15) }
    /// textDescriptionType (v2, 6.5.17): ASCII with its NUL, empty Unicode and ScriptCode parts.
    static func desc(_ text: String) -> [UInt8] {
        let ascii: [UInt8] = Array(text.utf8) + [0]
        return type("desc") + u32(UInt32(ascii.count)) + ascii + zeros(8) + zeros(2 + 1 + 67)
    }
    /// multiLocalizedUnicodeType (10.15): one en-US record, UTF-16BE, right after the record.
    static func mluc(_ text: String) -> [UInt8] {
        let utf16 = text.utf16.flatMap { u16($0) }
        return type("mluc") + u32(1) + u32(12) + sig("enUS") + u32(UInt32(utf16.count)) + u32(28) + utf16
    }
    /// lut16Type (10.11): identity matrix, 2-entry input and output ramps, a grid-2 CLUT.
    static func mft2(inputs: Int, outputs: Int) -> [UInt8] {
        let ramp = u16(0) + u16(0xFFFF), cells = (0..<inputs).reduce(1) { n, _ in n * 2 }
        var out = type("mft2") + [UInt8(inputs), UInt8(outputs), 2, 0]
        out += [1.0, 0, 0, 0, 1, 0, 0, 0, 1].flatMap(s15) + u16(2) + u16(2) + (0..<inputs).flatMap { _ in ramp }
        out += (0..<cells * outputs).flatMap { u16(UInt16(truncatingIfNeeded: $0 &* 4099)) }
        return out + (0..<outputs).flatMap { _ in ramp }
    }
    /// lutAToBType (10.12) with only its B curves (identity `curv`s): enough when inputs equal outputs.
    static func mAB(channels: Int) -> [UInt8] {
        type("mAB ") + [UInt8(channels), UInt8(channels), 0, 0] + u32(32) + zeros(16)
            + (0..<channels).flatMap { _ in type("curv") + u32(0) }
    }

    struct Header {
        var version: UInt32 = 0x0430_0000
        var deviceClass = "mntr", colorSpace = "RGB ", pcs = "XYZ "
    }

    /// A whole profile: the 128-byte header (7.2), the tag table (7.3), each tag's
    /// data at a 4-byte boundary. `share` points tags with equal bytes at one copy (7.3.1).
    static func profile(_ h: Header, _ tags: [(String, [UInt8])], share: Bool = false) -> [UInt8] {
        let start = 132 + 12 * tags.count
        var table = u32(UInt32(tags.count)), body: [UInt8] = [], placed: [[UInt8]: Int] = [:]
        for (signature, bytes) in tags {
            let offset = share ? placed[bytes] ?? start + body.count : start + body.count
            if offset == start + body.count {
                placed[bytes] = offset
                body += bytes + zeros((4 - bytes.count % 4) % 4)
            }
            table += sig(signature) + u32(UInt32(offset)) + u32(UInt32(bytes.count))
        }
        // Size, CMM, version, class, colour space, PCS, date, 'acsp', platform to intent, illuminant, creator to reserved.
        var header = u32(UInt32(start + body.count)) + u32(0) + u32(h.version) + sig(h.deviceClass)
        header += sig(h.colorSpace) + sig(h.pcs) + [2026, 10, 18, 12, 0, 0].flatMap { u16(UInt16($0)) }
        header += sig("acsp") + zeros(28) + s15(0.9642) + s15(1) + s15(0.8249) + zeros(48)
        return header + table + body
    }

    static func read32(_ b: [UInt8], _ at: Int) -> Int { (0..<4).reduce(0) { $0 << 8 | Int(b[at + $1]) } }
    /// Every tag table entry: signature, offset and size.
    static func tags(_ b: [UInt8]) -> [(sig: String, offset: Int, size: Int)] {
        (0..<read32(b, 128)).map { i in
            let at = 132 + 12 * i
            return (String(decoding: b[at..<at + 4], as: UTF8.self), read32(b, at + 4), read32(b, at + 8))
        }
    }

    /// SplitMix64, seeded as in every test target (this target's other copies are file-private).
    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            let z = (state ^ (state >> 30)) &* 0xBF58_476D_1CE4_E5B9, y = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return y ^ (y >> 31)
        }
    }
}

func three<T>(_ x: T) -> [T] { [x, x, x] }

/// One fixture profile and, when it is a matrix-and-curve profile, what it reads as.
struct ICCFixture: Sendable {
    let name: String, bytes: [UInt8], expected: ColorProfile?
    var data: Data { Data(bytes) }

    static let d50 = [0.9642, 1.0, 0.8249], v2 = ICC.Header(version: 0x0210_0000)
    /// Colourants chosen for the tests, columns r, g, b (the second has a negative Z).
    static let primariesA = [0.4361, 0.3851, 0.1431, 0.2225, 0.7169, 0.0606, 0.0139, 0.0971, 0.7141]
    static let primariesB = [0.5151, 0.2920, 0.1571, 0.2412, 0.6922, 0.0666, -0.0011, 0.0419, 0.7841]
    static let sRGBParams = [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045]
    static let tables: [[Double]] = [[0, 1], (0...16).map { Double($0 * $0) / 256 }, (0...255).map { Double($0 * $0 * $0) / 16_581_375 }]
    static let chad = [1.0479, 0.0229, -0.0502, 0.0296, 0.9904, -0.0171, -0.0092, 0.0151, 0.7519]

    static func rgbTags(_ m: [Double], _ trc: [[UInt8]]) -> [(String, [UInt8])] {
        [("wtpt", ICC.xyz(d50[0], d50[1], d50[2])), ("rXYZ", ICC.xyz(m[0], m[3], m[6])), ("gXYZ", ICC.xyz(m[1], m[4], m[7])),
         ("bXYZ", ICC.xyz(m[2], m[5], m[8])), ("rTRC", trc[0]), ("gTRC", trc[1]), ("bTRC", trc[2])]
    }
    static func rgb(_ name: String, _ m: [Double], _ curves: [ProfileCurve]) -> ColorProfile {
        ColorProfile(name: name, isGray: false, toXYZD50: m.map(ICC.q15), curves: curves)
    }
    static func make(_ name: String, _ h: ICC.Header, _ tags: [(String, [UInt8])], share: Bool = false,
                     _ expected: ColorProfile? = nil) -> ICCFixture {
        ICCFixture(name: name, bytes: ICC.profile(h, tags, share: share), expected: expected)
    }

    static let v2Gamma = make("v2 gamma", v2, [("desc", ICC.desc("Fixture v2 gamma"))]
        + rgbTags(primariesA, three(ICC.curv(gamma: 2.2))), share: true,
        rgb("Fixture v2 gamma", primariesA, three(.gamma(ICC.q8(2.2)))))
    static let v4Parametric = make("v4 parametric", ICC.Header(), [("desc", ICC.mluc("Fixture v4 parametric")),
        ("chad", ICC.sf32(chad))] + rgbTags(primariesB, three(ICC.para(3, sRGBParams))),
        rgb("Fixture v4 parametric", primariesB, three(.parametric(type: 3, params: sRGBParams.map(ICC.q15)))))
    static let table = make("table", v2, [("desc", ICC.desc("Fixture table"))] + rgbTags(primariesA, tables.map { ICC.curv(table: $0) }),
        rgb("Fixture table", primariesA, tables.map { ProfileCurve.table($0.map(ICC.q16)) }))
    static let gray = make("gray", ICC.Header(colorSpace: "GRAY"), [("desc", ICC.mluc("Fixture gray")),
        ("wtpt", ICC.xyz(d50[0], d50[1], d50[2])), ("kTRC", ICC.curv(gamma: 1.8))],
        ColorProfile(name: "Fixture gray", isGray: true, toXYZD50: d50.map(ICC.q15), curves: [.gamma(ICC.q8(1.8))]))
    static let lutV2 = make("LUT v2", v2, [("desc", ICC.desc("Fixture LUT")), ("wtpt", ICC.xyz(d50[0], d50[1], d50[2])),
        ("A2B0", ICC.mft2(inputs: 3, outputs: 3)), ("B2A0", ICC.mft2(inputs: 3, outputs: 3))])
    static let lutV4 = make("LUT v4", ICC.Header(), [("desc", ICC.mluc("Fixture LUT")), ("A2B0", ICC.mAB(channels: 3))])
    static let cmyk = make("CMYK", ICC.Header(deviceClass: "prtr", colorSpace: "CMYK"), [("desc", ICC.mluc("Fixture CMYK")),
        ("A2B0", ICC.mft2(inputs: 4, outputs: 3)), ("B2A0", ICC.mft2(inputs: 3, outputs: 4))])
    static let lab = make("Lab", ICC.Header(deviceClass: "spac", colorSpace: "Lab "), [("desc", ICC.mluc("Fixture Lab")),
        ("A2B0", ICC.mAB(channels: 3)), ("B2A0", ICC.mAB(channels: 3))])
    /// v2 gamma with its last tag one byte longer than the bytes left: a tag past the end.
    static let damaged: ICCFixture = {
        var b = v2Gamma.bytes
        let at = 132 + 12 * (ICC.read32(b, 128) - 1), offset = ICC.read32(b, at + 4)
        b.replaceSubrange(at + 8..<at + 12, with: ICC.u32(UInt32(b.count - offset + 1)))
        return ICCFixture(name: "damaged", bytes: b, expected: nil)
    }()

    static let all = [v2Gamma, v4Parametric, table, gray, lutV2, lutV4, cmyk, lab, damaged]
}

/// Equal names and curve kinds, and every number within `tolerance`.
func nearlyEqual(_ a: ColorProfile, _ b: ColorProfile, _ tolerance: Double) -> Bool {
    func near(_ x: [Double], _ y: [Double]) -> Bool { x.count == y.count && zip(x, y).allSatisfy { abs($0 - $1) <= tolerance } }
    func numbers(_ c: ProfileCurve) -> (String, [Double]) {
        switch c { case .gamma(let g): ("gamma", [g]); case .table(let t): ("table", t); case .parametric(let k, let p): ("para \(k)", p) }
    }
    let pairs = zip(a.curves.map(numbers), b.curves.map(numbers))
    return a.name == b.name && a.isGray == b.isGray && near(a.toXYZD50, b.toXYZD50) && a.curves.count == b.curves.count
        && pairs.allSatisfy { $0.0 == $1.0 && near($0.1, $1.1) }
}

@Test func iccBuilderSizesAndTagTablesHold() {
    for fixture in ICCFixture.all {
        let b = fixture.bytes, tags = ICC.tags(b), name = fixture.name
        #expect(ICC.read32(b, 0) == b.count && b.count % 4 == 0 && Array(b[36..<40]) == ICC.sig("acsp"), "\(name)")
        let inside = tags.allSatisfy { $0.offset >= 132 + 12 * tags.count && $0.offset % 4 == 0 && $0.offset + $0.size <= b.count }
        #expect(!tags.isEmpty && inside == (name != "damaged"), "\(name)")
    }
    // The v2 gamma fixture shares one `curv` among its three TRC tags; the table one does not.
    let trcOffsets = { (f: ICCFixture) in Set(ICC.tags(f.bytes).filter { $0.sig.hasSuffix("TRC") }.map { $0.offset }) }
    #expect(trcOffsets(ICCFixture.v2Gamma).count == 1 && trcOffsets(ICCFixture.table).count == 3)
}
