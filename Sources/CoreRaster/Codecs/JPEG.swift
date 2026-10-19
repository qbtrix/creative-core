// JPEG.swift: the Foundation-only JPEG codec (ITU-T T.81 with its Annex K
// tables, JFIF 1.02, the EXIF orientation tag): the API and marker parser,
// JPEGDecode.swift the scans; IC-7 adds JPEGProgressive.swift, IC-8 the writer, which keep these
// signatures. Invariants: sizes come from SOF and are checked against
// `maxSide` and `PixelBuffer.maxPixels` before any pixel buffer is made;
// decoded pixels are never rotated, `JPEGInfo.orientation` says how to.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What a JPEG's markers say, read without decoding any scan.
public struct JPEGInfo: Hashable, Sendable {
    /// Frame width and height in pixels (each 1...`JPEG.maxSide`) as stored
    /// in SOF, before `orientation` is applied, and the component count
    /// (1 grey, 3 YCbCr).
    public var width, height, components: Int
    /// True for a progressive frame (SOF2).
    public var progressive: Bool
    /// The EXIF (TIFF) Orientation, 1...8, saying how to turn the stored
    /// pixels for display; 1 when there is no EXIF tag. 1 as stored, 2
    /// mirrored left to right, 3 rotated 180 degrees, 4 flipped top to bottom;
    /// 5 to 8 are transposed: 5 mirrored across the main diagonal, 6 rotate
    /// 90 degrees clockwise to display, 7 mirrored across the other diagonal,
    /// 8 rotate 90 degrees counter-clockwise. For 5...8 the displayed image
    /// is `height` wide and `width` tall. The `PixelBuffer` calls that turn
    /// `JPEG.read`'s pixels upright, in order:
    /// - 1: none.
    /// - 2: `flipped(.horizontal)`.
    /// - 3: `rotated(.degrees180)`.
    /// - 4: `flipped(.vertical)`.
    /// - 5: `rotated(.degrees90)` then `flipped(.horizontal)` (transpose).
    /// - 6: `rotated(.degrees90)`.
    /// - 7: `rotated(.degrees270)` then `flipped(.horizontal)` (transverse).
    /// - 8: `rotated(.degrees270)`.
    public var orientation: Int
}

/// JPEG files to and from `PixelBuffer`. Throws `CodecError`: `notThisFormat`
/// without SOI, `damaged` for a broken stream, `unsupported` for arithmetic
/// coding, lossless or hierarchical frames, 12-bit samples or CMYK,
/// `tooLarge` past its limits.
public enum JPEG {
    /// The largest width or height read or written, in pixels; the pixel
    /// count is also capped by `PixelBuffer.maxPixels`.
    public static let maxSide = 30_000

    /// The frame header and EXIF orientation of `data`, with no scan decoded.
    /// Throws `notThisFormat` without SOI, `damaged` for a malformed marker
    /// segment or no SOF, `unsupported` for a frame type it does not read,
    /// `tooLarge` for a side over `maxSide`.
    public static func info(_ data: Data) throws -> JPEGInfo {
        var d = try JPEGDecoder(data)
        _ = try d.nextScan()
        guard let f = d.frame else { throw CodecError.damaged("no SOF") }
        return JPEGInfo(width: f.width, height: f.height, components: f.components.count, progressive: f.progressive,
                        orientation: d.orientation)
    }

    /// `data` decoded (baseline or progressive; grey or YCbCr at 4:4:4, 4:2:2
    /// or 4:2:0; restart markers) as premultiplied linear Float32 pixels with
    /// alpha 1, not rotated. Throws what `info` throws, `damaged` for a missing
    /// table, a bad Huffman code or a short scan, and `tooLarge` past `maxSide`
    /// or `PixelBuffer.maxPixels` before allocating, and when the progressive
    /// scans together pass over the frame's blocks more than 64 times (too many
    /// progressive scans, at any image size); a progressive scan out of
    /// Annex G's order or limits is `damaged`.
    public static func read(_ data: Data) throws -> PixelBuffer {
        var d = try JPEGDecoder(data), coded: [[Int]] = []
        while let body = try d.nextScan() {
            let scan = try d.scanHeader(body)
            if d.frame?.progressive == true { try d.progressiveScan(scan, d.entropy(), &coded); continue }
            try d.baselineScan(scan, d.entropy())
        }
        guard !d.coefficients.isEmpty else { throw CodecError.damaged("no scan") }
        return try d.pixels()
    }
}

/// A frame component (B.2.2): the blocks a scan of it alone codes (A.2.2) and its stored `stride` x `rows` MCU grid.
struct JPEGComponent: Sendable {
    var id, h, v, tq, blocksX, blocksY, stride, rows: Int
}

/// The frame header (SOF0, SOF1 or SOF2 at 8 bits) with the largest factors and the MCUs across and down (A.2.4).
struct JPEGFrame: Sendable {
    var width, height: Int, progressive: Bool, components: [JPEGComponent], hmax, vmax, mcusX, mcusY: Int
}

/// A scan header (B.2.3): component indexes with their Huffman tables (nil when undefined), band and approximation.
struct JPEGScan: Sendable {
    struct Part: Sendable { var index: Int, dc: JPEGHuffman?, ac: JPEGHuffman? }
    var parts: [Part], ss, se, ah, al: Int
}

/// The marker cursor, the tables in effect and per component the quantized coefficients, 64 per block, natural order.
struct JPEGDecoder {
    let bytes: [UInt8]
    var at = 2, frame: JPEGFrame?, orientation = 1, restart = 0, quant = [[Float]?](repeating: nil, count: 4)
    var dc = [JPEGHuffman?](repeating: nil, count: 4), ac = [JPEGHuffman?](repeating: nil, count: 4)
    var coefficients: [[Int32]] = []

    /// Figure A.6: entry k is the natural (row-major) index of zigzag coefficient k.
    static let zigzag: [Int] = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34,
                                27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44,
                                51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xD8 else { throw CodecError.notThisFormat }
    }

    /// Reads marker segments up to the next SOS, returning its body, or nil at EOI or the end of the bytes.
    mutating func nextScan() throws -> [UInt8]? {
        while at + 1 < bytes.count {
            guard bytes[at] == 0xFF else { throw CodecError.damaged("no marker (0xFF) at byte \(at)") }
            let marker = bytes[at + 1], start = at
            at += marker == 0xFF ? 1 : 2
            if marker == 0xD9 { return nil }
            if marker == 0xFF || marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
            guard at + 1 < bytes.count else { throw CodecError.damaged("marker \(Self.hex(marker)) at byte \(start) has no length") }
            let length = Int(bytes[at]) << 8 | Int(bytes[at + 1])
            guard length >= 2, length <= bytes.count - at else {
                throw CodecError.damaged("segment \(Self.hex(marker)) at byte \(start) runs past the end (length \(length), \(bytes.count - at) bytes left)")
            }
            let body = Array(bytes[(at + 2)..<(at + length)])
            at += length
            if marker == 0xDA { return body }
            try segment(marker, body)
        }
        return nil
    }

    /// A marker as T.81 writes it, 0xFF then its code, in uppercase hex: hex(0xDB) is "0xFFDB".
    static func hex(_ marker: UInt8) -> String { "0x" + String(0xFF00 | Int(marker), radix: 16, uppercase: true) }

    /// A table's class or precision (high nibble) and id (low nibble) as two uppercase hex digits: 17 is "0x11".
    static func nibbles(_ t: Int) -> String { "0x" + String(t >> 4, radix: 16, uppercase: true) + String(t & 15, radix: 16, uppercase: true) }

    mutating func segment(_ marker: UInt8, _ body: [UInt8]) throws {
        var r = ByteReader(body)
        switch marker {
        case 0xC0, 0xC1, 0xC2: frame = try Self.frame(&r, progressive: marker == 0xC2, seen: frame != nil)
        case 0xC3, 0xC5...0xC7, 0xC9...0xCB, 0xCD...0xCF:
            throw CodecError.unsupported("SOF \(Self.hex(marker)): lossless, hierarchical or arithmetic coding")
        case 0xC4:
            while r.remaining > 0 {
                let t = Int(try r.u8()), counts = try r.bytes(16), values = try r.bytes(counts.reduce(0) { $0 + Int($1) })
                guard values.count <= 256 else { throw CodecError.damaged("DHT \(Self.nibbles(t)) has \(values.count) values (256 at most)") }
                guard t >> 4 <= 1, t & 15 <= 3 else { throw CodecError.damaged("DHT class/id \(Self.nibbles(t)) out of range (class 0...1, id 0...3)") }
                let table = try JPEGHuffman(counts: counts, values: values)
                if t >> 4 == 0 { dc[t & 15] = table } else { ac[t & 15] = table }
            }
        case 0xDB:
            while r.remaining > 0 {
                let t = Int(try r.u8())
                guard t >> 4 <= 1, t & 15 <= 3 else { throw CodecError.damaged("DQT precision/id \(Self.nibbles(t)) out of range (precision 0...1, id 0...3)") }
                var q = [Float](repeating: 0, count: 64)
                for k in 0..<64 { q[Self.zigzag[k]] = try Float(t >> 4 == 0 ? UInt16(r.u8()) : r.u16()) }
                quant[t & 15] = q
            }
        case 0xDD: restart = Int(try r.u16())
        case 0xE1: orientation = (try? Self.exifOrientation(body)) ?? orientation
        default: break
        }
    }

    /// SOF (B.2.2): 8-bit samples, one or three components with factors 1...4, sides checked before anything else.
    static func frame(_ r: inout ByteReader, progressive: Bool, seen: Bool) throws -> JPEGFrame {
        guard !seen else { throw CodecError.damaged("a second SOF") }
        let precision = try r.u8(), height = Int(try r.u16()), width = Int(try r.u16()), n = Int(try r.u8())
        guard precision == 8 else { throw CodecError.unsupported("\(precision)-bit samples") }
        guard height > 0 else { throw CodecError.unsupported("height from DNL") }
        guard width > 0 else { throw CodecError.damaged("width 0") }
        guard width <= JPEG.maxSide, height <= JPEG.maxSide else { throw CodecError.tooLarge("JPEG \(width)x\(height): sides are at most \(JPEG.maxSide)") }
        guard n == 1 || n == 3 else { throw n == 0 ? CodecError.damaged("no components") : CodecError.unsupported("\(n) components (4 is CMYK or YCCK, not read)") }
        var parts: [(id: Int, h: Int, v: Int, tq: Int)] = []
        for _ in 0..<n {
            let id = Int(try r.u8()), hv = Int(try r.u8()), tq = Int(try r.u8())
            guard (1...4).contains(hv >> 4), (1...4).contains(hv & 15), tq <= 3 else {
                throw CodecError.damaged("SOF component \(id): H \(hv >> 4) V \(hv & 15) Tq \(tq), need H and V 1...4 and Tq 0...3")
            }
            parts.append((id, hv >> 4, hv & 15, tq))
        }
        let hmax = parts.map(\.h).max() ?? 1, vmax = parts.map(\.v).max() ?? 1
        let mcusX = (width + 8 * hmax - 1) / (8 * hmax), mcusY = (height + 8 * vmax - 1) / (8 * vmax)
        let components = parts.map { (p: (id: Int, h: Int, v: Int, tq: Int)) -> JPEGComponent in
            let w = (width * p.h + hmax - 1) / hmax, h = (height * p.v + vmax - 1) / vmax
            return JPEGComponent(id: p.id, h: p.h, v: p.v, tq: p.tq, blocksX: (w + 7) / 8, blocksY: (h + 7) / 8,
                                 stride: mcusX * p.h, rows: mcusY * p.v)
        }
        return JPEGFrame(width: width, height: height, progressive: progressive, components: components,
                         hmax: hmax, vmax: vmax, mcusX: mcusX, mcusY: mcusY)
    }

    /// An APP1 EXIF body's IFD0 Orientation (0x0112, SHORT) in either TIFF byte order, or nil.
    static func exifOrientation(_ body: [UInt8]) throws -> Int? {
        guard body.starts(with: [0x45, 0x78, 0x69, 0x66, 0, 0]) else { return nil }
        let tiff = Array(body.dropFirst(6)), little = tiff.starts(with: [0x49, 0x49])
        guard little || tiff.starts(with: [0x4D, 0x4D]) else { return nil }
        var r = ByteReader(tiff)
        func u16() throws -> Int { try Int(little ? r.u16LE() : r.u16()) }
        _ = try r.bytes(4)
        let ifd = try Int(little ? r.u32LE() : r.u32())
        guard ifd < tiff.count else { return nil }
        r = ByteReader(Array(tiff[ifd...]))
        for _ in 0..<(try u16()) {
            let tag = try u16(), type = try u16(); _ = try r.bytes(4)
            let value = try u16(); _ = try r.bytes(2)
            if tag == 0x0112, type == 3 { return (1...8).contains(value) ? value : nil }
        }
        return nil
    }

    /// SOS (B.2.3) checked against the frame and the tables in effect; the first one sizes the coefficient store.
    mutating func scanHeader(_ body: [UInt8]) throws -> JPEGScan {
        guard let f = frame else { throw CodecError.damaged("SOS before SOF") }
        var r = ByteReader(body), parts: [JPEGScan.Part] = []
        for _ in 0..<Int(try r.u8()) {
            let id = Int(try r.u8()), t = Int(try r.u8())
            guard let i = f.components.firstIndex(where: { $0.id == id }) else { throw CodecError.damaged("scan names component \(id), not in the frame") }
            guard quant[f.components[i].tq] != nil else {
                throw CodecError.damaged("scan component \(id) uses DQT \(f.components[i].tq), not defined before its scan")
            }
            parts.append(JPEGScan.Part(index: i, dc: t >> 4 < 4 ? dc[t >> 4] : nil, ac: t & 15 < 4 ? ac[t & 15] : nil))
        }
        let units = parts.reduce(0) { $0 + f.components[$1.index].h * f.components[$1.index].v }
        guard (1...4).contains(parts.count), parts.count == 1 || units <= 10 else {
            throw CodecError.damaged("scan names \(parts.count) components (1...4 allowed) with \(units) blocks per MCU (10 at most interleaved, B.2.3)")
        }
        let ss = Int(try r.u8()), se = Int(try r.u8()), a = Int(try r.u8())
        if coefficients.isEmpty {
            // Sides are at most maxSide, so the product cannot overflow.
            guard f.width * f.height <= PixelBuffer.maxPixels else { throw CodecError.tooLarge("JPEG \(f.width)x\(f.height): more than \(PixelBuffer.maxPixels) pixels") }
            // A sequential block takes at least a DC code and an EOB, two bits, so the bytes left bound the blocks. In a
            // progressive frame check() takes no AC scan of a component before its DC first scan (G.1.1.1.1), which
            // codes each of its blocks with 1 bit or more, inside the bytes left: 8 blocks a byte over all components.
            let coded = f.components.reduce(0) { $0 + $1.blocksX * $1.blocksY }
            guard coded <= (f.progressive ? 8 : 4) * (bytes.count - at) else {
                throw CodecError.damaged("\(coded) blocks in too few bytes (\(bytes.count - at) after the scan header): truncated")
            }
            coefficients = f.components.map { [Int32](repeating: 0, count: $0.stride * $0.rows * 64) }
        }
        return JPEGScan(parts: parts, ss: ss, se: se, ah: a >> 4, al: a & 15)
    }
}
