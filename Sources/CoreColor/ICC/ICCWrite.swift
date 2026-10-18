// ICCWrite.swift: writes a ColorProfile as v4 ICC bytes that ICCRead reads back equal on the fields'
// grids (s15Fixed16 colourants and parameters, u8Fixed8 gamma, uInt16 table entries over 65535).
// Layouts come only from the public ICC.1:2010 specification (section numbers below): the 128-byte
// header (7.2), the tag table (7.3), then each tag's data at a 4-byte boundary, zero-padded so the
// profile size is a multiple of 4 (7.1.2); tags with equal bytes share one copy (7.3.1). RGB profiles
// carry `chad`, the Bradford D65-to-D50 matrix, because ColorProfile holds colourants already adapted
// from a D65 white to the D50 PCS; `wtpt` is then D50 (9.2.36). Gray stores its white point in `wtpt`
// as given, with no `chad`. The date and profile ID stay 0 so equal profiles write equal bytes. A
// value that does not fit its field throws `ColorError.invalid`; nothing traps or overflows.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ICCWrite {
    static func fail(_ why: String) -> ColorError { .invalid("ICC write: \(why)") }

    static func profile(_ p: ColorProfile) throws(ColorError) -> Data {
        let m = p.toXYZD50
        guard m.count == (p.isGray ? 3 : 9), p.curves.count == (p.isGray ? 1 : 3) else {
            let want = p.isGray ? "3 matrix values and 1 curve" : "9 matrix values and 3 curves"
            throw fail("a \(p.isGray ? "gray" : "RGB") profile needs \(want), has \(m.count) and \(p.curves.count)")
        }
        var tags: [(String, [UInt8])] = [("desc", try mluc(p.name))]
        if p.isGray {
            tags.append(("wtpt", try xyz(m[0], m[1], m[2])))
            tags.append(("kTRC", try curve(p.curves[0])))
        } else {
            let white = Matrix3.d50White, c = Matrix3.bradfordD65ToD50.m
            tags.append(("wtpt", try xyz(white.c0, white.c1, white.c2)))
            tags.append(("chad", try sf32([c.0, c.1, c.2, c.3, c.4, c.5, c.6, c.7, c.8])))
            for (i, name) in ["rXYZ", "gXYZ", "bXYZ"].enumerated() { tags.append((name, try xyz(m[i], m[i + 3], m[i + 6]))) }
            for (i, name) in ["rTRC", "gTRC", "bTRC"].enumerated() { tags.append((name, try curve(p.curves[i]))) }
        }
        return Data(try assemble(colorSpace: p.isGray ? "GRAY" : "RGB ", tags))
    }

    /// The header (7.2), the tag table (7.3) and every tag's data, each padded to 4 bytes.
    static func assemble(colorSpace: String, _ tags: [(String, [UInt8])]) throws(ColorError) -> [UInt8] {
        let start = 132 + 12 * tags.count
        var table = try u32(tags.count), body: [UInt8] = [], placed: [[UInt8]: Int] = [:]
        for (name, bytes) in tags {
            let offset = placed[bytes] ?? start + body.count
            if placed[bytes] == nil {
                placed[bytes] = offset
                body += bytes + [UInt8](repeating: 0, count: (4 - bytes.count % 4) % 4)
            }
            table += sig(name) + (try u32(offset))
            table += try u32(bytes.count)
        }
        // Size, CMM, version 4.3, class, colour space, PCS, date (0), 'acsp', platform to rendering
        // intent (0), the PCS illuminant D50, creator, profile ID and reserved bytes (0).
        var out = try u32(start + body.count) + u32(0)
        out += [4, 0x30, 0, 0] + sig("mntr")
        out += sig(colorSpace) + sig("XYZ ")
        out += [UInt8](repeating: 0, count: 12) + sig("acsp")
        out += [UInt8](repeating: 0, count: 28)
        out += try xyzNumber(Matrix3.d50White.c0, Matrix3.d50White.c1, Matrix3.d50White.c2)
        out += [UInt8](repeating: 0, count: 48)
        return out + table + body
    }

    /// A uInt32 field (4.10) for a count, offset or size, which must fit it.
    static func u32(_ value: Int) throws(ColorError) -> [UInt8] {
        guard let v = UInt32(exactly: value) else { throw fail("\(value) does not fit a uInt32") }
        return [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) }
    }

    static func u16(_ v: UInt16) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }

    /// A four-byte signature (4.12), space padded.
    static func sig(_ s: String) -> [UInt8] { Array((s + "    ").utf8.prefix(4)) }

    /// A tag type's signature and its four reserved bytes (10.1).
    static func type(_ s: String) -> [UInt8] { sig(s) + [0, 0, 0, 0] }

    /// s15Fixed16Number (4.6): the value times 65536, rounded, as a two's complement Int32.
    static func s15(_ value: Double) throws(ColorError) -> [UInt8] {
        guard let v = Int32(exactly: (value * 65536).rounded()) else { throw fail("\(value) does not fit an s15Fixed16Number") }
        return [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: UInt32(bitPattern: v) >> $0) }
    }

    static func xyzNumber(_ x: Double, _ y: Double, _ z: Double) throws(ColorError) -> [UInt8] {
        try s15(x) + s15(y) + s15(z)
    }

    /// XYZType (10.31) with one XYZNumber.
    static func xyz(_ x: Double, _ y: Double, _ z: Double) throws(ColorError) -> [UInt8] {
        type("XYZ ") + (try xyzNumber(x, y, z))
    }

    /// s15Fixed16ArrayType (10.22), as `chad` uses it.
    static func sf32(_ values: [Double]) throws(ColorError) -> [UInt8] {
        var out = type("sf32")
        for v in values { out += try s15(v) }
        return out
    }

    /// curveType (10.6), count 1 a u8Fixed8 gamma or n >= 2 a uInt16 table; or parametricCurveType (10.18).
    static func curve(_ c: ProfileCurve) throws(ColorError) -> [UInt8] {
        switch c {
        case .gamma(let g):
            guard let v = UInt16(exactly: (g * 256).rounded()) else { throw fail("gamma \(g) does not fit a u8Fixed8Number") }
            return type("curv") + (try u32(1)) + u16(v)
        case .table(let entries):
            // A count of 0 or 1 means identity or gamma (10.6), so a table needs two entries.
            guard entries.count >= 2 else { throw fail("a curve table needs 2 or more entries, has \(entries.count)") }
            var out = type("curv") + (try u32(entries.count))
            for e in entries {
                guard e >= 0, e <= 1, let v = UInt16(exactly: (e * 65535).rounded()) else {
                    throw fail("a curve table entry \(e) is not in 0...1")
                }
                out += u16(v)
            }
            return out
        case .parametric(let function, let params):
            let counts = [1, 3, 4, 5, 7]
            guard counts.indices.contains(function), params.count == counts[function],
                  let kind = UInt16(exactly: function) else {
                throw fail("parametric type must be 0 to 4 with 1/3/4/5/7 params, has type \(function) with \(params.count)")
            }
            var out = type("para") + u16(kind) + [0, 0]
            for v in params { out += try s15(v) }
            return out
        }
    }

    /// multiLocalizedUnicodeType (10.15): one en-US record, UTF-16BE, right after the record.
    static func mluc(_ text: String) throws(ColorError) -> [UInt8] {
        var utf16: [UInt8] = []
        for unit in text.utf16 { utf16 += u16(unit) }
        var out = type("mluc") + (try u32(1))
        out += try u32(12) + sig("enUS")
        out += try u32(utf16.count) + u32(28)
        return out + utf16
    }
}
