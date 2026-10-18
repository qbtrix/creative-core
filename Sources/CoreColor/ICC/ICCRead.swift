// ICCRead.swift: reads ICC matrix-and-curve profiles (RGB and gray, v2 and v4) into a ColorProfile.
// Layouts come only from the public ICC.1:2010 specification (section numbers below) and ICC.1:2001-04
// for the v2 `desc` type. The bytes are untrusted: every offset, size and count is checked against the
// bytes with no Int overflow, so damaged input throws `ColorError.invalid` and never traps. LUT-based,
// CMYK and Lab profiles, and classes other than display (`mntr`) and input (`scnr`), throw naming what they are. Colourants are read as stored: ICC.1 already
// adapts them to the D50 PCS (the `chad` step), so the reader applies no adaptation of its own.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A bounds-checked window on profile bytes, read big-endian (4.1). Offsets are relative to the window.
struct ICCSpan {
    let bytes: ArraySlice<UInt8>

    static func fail(_ why: String) -> ColorError { .invalid("ICC profile: \(why)") }

    /// `count` bytes from `at`, or a throw naming `what` when they are not all inside this window.
    func span(_ at: Int, _ count: Int, _ what: String) throws(ColorError) -> ICCSpan {
        let (end, overflow) = at.addingReportingOverflow(count)
        guard at >= 0, count >= 0, !overflow, end <= bytes.count else {
            throw Self.fail("\(what) runs past the end of its data")
        }
        return ICCSpan(bytes: bytes[(bytes.startIndex + at)..<(bytes.startIndex + end)])
    }

    func u16(_ at: Int) throws(ColorError) -> UInt16 {
        try span(at, 2, "a uInt16").bytes.reduce(0) { $0 << 8 | UInt16($1) }
    }

    func u32(_ at: Int) throws(ColorError) -> UInt32 {
        try span(at, 4, "a uInt32").bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// A uInt32 count or offset as an Int, which it always fits on a 64-bit platform.
    func int(_ at: Int) throws(ColorError) -> Int {
        guard let value = Int(exactly: try u32(at)) else { throw Self.fail("a count does not fit an Int") }
        return value
    }

    /// s15Fixed16Number (4.6): a signed 32-bit value over 65536.
    func s15(_ at: Int) throws(ColorError) -> Double {
        Double(Int32(bitPattern: try u32(at))) / 65536
    }

    /// A four-byte signature (4.12) such as `RGB ` or `curv`.
    func signature(_ at: Int) throws(ColorError) -> String {
        String(decoding: try span(at, 4, "a signature").bytes, as: UTF8.self)
    }
}

/// The header (7.2) and tag table (7.3) of a profile, every tag's range checked inside the profile.
struct ICCTagTable {
    let header: ICCSpan
    /// Tag signature to its data; the first entry wins when a signature repeats.
    let tags: [String: ICCSpan]

    init(_ data: Data) throws(ColorError) {
        let all = ICCSpan(bytes: ArraySlice(data))
        let size = try all.int(0)
        guard size >= 132, size <= data.count else {
            throw ICCSpan.fail("the size field says \(size) bytes but there are \(data.count)")
        }
        let profile = try all.span(0, size, "the profile")
        guard try profile.signature(36) == "acsp" else { throw ICCSpan.fail("no 'acsp' signature") }
        let count = try profile.int(128)
        guard count <= (size - 132) / 12 else { throw ICCSpan.fail("a tag table of \(count) tags runs past the end") }
        var tags: [String: ICCSpan] = [:]
        for entry in 0..<count {
            let at = 132 + 12 * entry, name = try profile.signature(at)
            let offset = try profile.int(at + 4), length = try profile.int(at + 8)
            let (end, overflow) = offset.addingReportingOverflow(length)
            // Every tag type starts with its signature and four reserved bytes (10.1), and its
            // last byte lies inside the profile. This guard is the only bound on the slice below
            // (the profile window starts at index 0).
            guard !overflow, length >= 8, end - 1 < size else { throw ICCSpan.fail("tag '\(name)' runs past the end") }
            if tags[name] == nil { tags[name] = ICCSpan(bytes: profile.bytes[offset..<end]) }
        }
        header = profile
        self.tags = tags
    }

    func tag(_ name: String) throws(ColorError) -> ICCSpan {
        guard let tag = tags[name] else { throw ICCSpan.fail("no '\(name)' tag") }
        return tag
    }
}

enum ICCRead {
    /// Reads a matrix-and-curve profile; see the file comment for what throws.
    static func profile(_ data: Data) throws(ColorError) -> ColorProfile {
        let table = try ICCTagTable(data)
        let space = try table.header.signature(16), pcs = try table.header.signature(20)
        let isGray: Bool
        switch space {
        case "RGB ": isGray = false
        case "GRAY": isGray = true
        case "CMYK": throw ICCSpan.fail("CMYK profiles are not supported")
        case "Lab ": throw ICCSpan.fail("Lab colour space profiles are not supported")
        default: throw ICCSpan.fail("colour space '\(space)' is not supported")
        }
        guard pcs == "XYZ " else {
            throw ICCSpan.fail(pcs == "Lab " ? "a Lab PCS is not supported" : "PCS '\(pcs)' is not supported")
        }
        // Device class (7.2.5): only input and display profiles carry the matrix-and-curve model read here.
        let cls = try table.header.signature(12)
        guard cls == "mntr" || cls == "scnr" else { throw ICCSpan.fail("profile class '\(cls)' is not supported") }
        let major = try table.header.span(8, 1, "the version").bytes.first ?? 0
        guard major == 2 || major == 4 else { throw ICCSpan.fail("version \(major) is not 2 or 4") }
        let needed = isGray ? ["wtpt", "kTRC"] : ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]
        if needed.contains(where: { table.tags[$0] == nil }),
           table.tags.keys.contains(where: { $0.hasPrefix("A2B") || $0.hasPrefix("B2A") }) {
            throw ICCSpan.fail("LUT-based profiles are not supported")
        }
        var name = ""
        if let desc = table.tags["desc"] { name = try description(desc) }
        if isGray {
            return ColorProfile(name: name, isGray: true, toXYZD50: try xyz(table.tag("wtpt")),
                                curves: [try curve(table.tag("kTRC"))])
        }
        let r = try xyz(table.tag("rXYZ")), g = try xyz(table.tag("gXYZ")), b = try xyz(table.tag("bXYZ"))
        var curves: [ProfileCurve] = []
        for trc in ["rTRC", "gTRC", "bTRC"] { curves.append(try curve(table.tag(trc))) }
        return ColorProfile(name: name, isGray: false,
                            toXYZD50: [r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]], curves: curves)
    }

    /// XYZType (10.31) with one XYZNumber.
    static func xyz(_ tag: ICCSpan) throws(ColorError) -> [Double] {
        guard try tag.signature(0) == "XYZ " else { throw ICCSpan.fail("a colourant is not XYZType") }
        return [try tag.s15(8), try tag.s15(12), try tag.s15(16)]
    }

    /// curveType (10.6) or parametricCurveType (10.18).
    static func curve(_ tag: ICCSpan) throws(ColorError) -> ProfileCurve {
        switch try tag.signature(0) {
        case "curv":
            let count = try tag.int(8)
            switch count {
            case 0: return .gamma(1)
            case 1: return .gamma(Double(try tag.u16(12)) / 256)
            default:
                let (length, overflow) = count.multipliedReportingOverflow(by: 2)
                guard !overflow else { throw ICCSpan.fail("a curve table of \(count) entries is too long") }
                let entries = try tag.span(12, length, "a curve table").bytes
                return .table(stride(from: entries.startIndex, to: entries.endIndex, by: 2).map {
                    Double(UInt16(entries[$0]) << 8 | UInt16(entries[$0 + 1])) / 65535
                })
            }
        case "para":
            let function = Int(try tag.u16(8)), counts = [1, 3, 4, 5, 7]
            guard function < counts.count else { throw ICCSpan.fail("parametric function type \(function) is not 0 to 4") }
            var params: [Double] = []
            for i in 0..<counts[function] { params.append(try tag.s15(12 + 4 * i)) }
            return .parametric(type: function, params: params)
        case let other:
            throw ICCSpan.fail("a tone curve of type '\(other)' is not curv or para")
        }
    }

    /// textDescriptionType (v2) or multiLocalizedUnicodeType (10.15, its first record).
    static func description(_ tag: ICCSpan) throws(ColorError) -> String {
        switch try tag.signature(0) {
        case "desc":
            let ascii = try tag.span(12, tag.int(8), "the description").bytes
            return String(decoding: ascii.prefix { $0 != 0 }, as: UTF8.self)
        case "mluc":
            guard try tag.int(8) > 0 else { return "" }
            let text = try tag.span(tag.int(24), tag.int(20) / 2 * 2, "the description").bytes
            let units = stride(from: text.startIndex, to: text.endIndex, by: 2).map {
                UInt16(text[$0]) << 8 | UInt16(text[$0 + 1])
            }
            return String(decoding: units, as: UTF16.self)
        case let other:
            throw ICCSpan.fail("a description of type '\(other)' is not desc or mluc")
        }
    }
}
