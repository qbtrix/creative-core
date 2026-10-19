// JPEGFixtures.swift: JPEG streams built from ITU-T T.81 (the zigzag of
// Figure A.6, tables K.1 to K.6, Huffman codes by C.1 and C.2, DC differences
// and AC run/size symbols by F.1.2, byte stuffing and restart markers by
// F.1.2.3 and B.2.4.4), JFIF 1.02 (APP0, the YCbCr equations) and EXIF 2.3
// (APP1, Orientation 0x0112), and their reference pixels from the A.3.3
// inverse DCT in Double. No decoder made any of it.
@testable import CoreRaster
import CoreColor
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum JPEGFixtures {
    typealias Codes = [Int: (code: Int, length: Int)]
    /// Figure A.6: entry k is the natural (row-major, row = vertical frequency) index of zigzag coefficient k.
    static let zigzag = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6,
                         7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31,
                         39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
    /// Tables K.1 (luminance) and K.2 (chrominance), natural order.
    static let lumaQ = [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56,
                        14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92,
                        49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]
    static let chromaQ = [17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99,
                          47, 66, 99, 99, 99, 99, 99, 99] + [Int](repeating: 99, count: 32)

    /// A Huffman table as DHT carries it (B.2.4.2): code counts for lengths 1...16 and the values in code order.
    struct Huffman { var bits: [Int]; var values: [Int] }
    static let dcLuma = Huffman(bits: [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], values: Array(0...11))
    static let dcChroma = Huffman(bits: [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], values: Array(0...11))
    static let acLuma = ac([0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7D], [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14,
        0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72, 0x82])
    static let acChroma = ac([0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77], [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22, 0x32,
        0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62, 0x72, 0xD1, 0x0A, 0x16,
        0x24, 0x34, 0xE1, 0x25, 0xF1])
    /// K.5 and K.6 as printed: the values of codes up to 15 bits, then the 16-bit codes for every other run/size
    /// (sizes 1...10), run by run.
    static func ac(_ bits: [Int], _ head: [Int]) -> Huffman {
        Huffman(bits: bits, values: head + (0..<16).flatMap { r in (1...10).map { r << 4 | $0 } }.filter { !head.contains($0) })
    }
    /// C.1 and C.2: each value's code and length.
    static func codes(_ table: Huffman) -> Codes {
        var map: Codes = [:], code = 0, k = 0
        for length in 1...16 {
            for _ in 0..<table.bits[length - 1] { map[table.values[k]] = (code, length); code += 1; k += 1 }
            code <<= 1
        }
        return map
    }
    /// The DC and AC codes of table 0 (luminance, component 0) and table 1 (chrominance, the others).
    static let huffman: [(dc: Codes, ac: Codes)] = [(codes(dcLuma), codes(acLuma)), (codes(dcChroma), codes(acChroma))]

    /// Entropy-coded bytes (F.1.2.3): most significant bit first, a 0x00 stuffed after each 0xFF, 1-bits to pad.
    struct Bits {
        var bytes: [UInt8] = [], byte = 0, count = 0
        mutating func put(_ value: Int, _ length: Int) {
            for i in stride(from: length - 1, through: 0, by: -1) {
                byte = byte << 1 | (value >> i & 1); count += 1
                if count == 8 { bytes += byte == 0xFF ? [0xFF, 0] : [UInt8(byte)]; byte = 0; count = 0 }
            }
        }
        mutating func put(_ codes: Codes, _ symbol: Int) { let c = codes[symbol] ?? (0, 0); put(c.code, c.length) }
        mutating func align() { while count != 0 { put(1, 1) } }
    }
    /// F.1.2.1: the size category of `v` and its additional bits (v, or v - 1 in `size` bits when negative).
    static func magnitude(_ v: Int) -> (size: Int, bits: Int) {
        let size = Int.bitWidth - abs(v).leadingZeroBitCount
        return (size, v < 0 ? v + (1 << size) - 1 : v)
    }
    /// F.1.2.2: `band`, zigzag order, as run/size symbols, ZRL per 16 zeros, EOB after the last non-zero.
    static func encodeAC(_ band: [Int], _ codes: Codes, _ w: inout Bits) {
        var run = 0
        for v in band {
            if v == 0 { run += 1; continue }
            while run > 15 { w.put(codes, 0xF0); run -= 16 }
            let m = magnitude(v)
            w.put(codes, run << 4 | m.size); w.put(m.bits, m.size); run = 0
        }
        if run > 0 { w.put(codes, 0x00) }
    }

    static func be16(_ v: Int) -> [UInt8] { [UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v)] }
    static func segment(_ marker: UInt8, _ body: [UInt8]) -> [UInt8] { [0xFF, marker] + be16(body.count + 2) + body }
    /// JFIF 1.02 APP0: version 1.02, no units, density 1:1, no thumbnail.
    static let jfif = segment(0xE0, Array("JFIF".utf8) + [0, 1, 2, 0, 0, 1, 0, 1, 0, 0])
    /// EXIF APP1: a TIFF header (MM big-endian or II little-endian, 42, IFD0 at 8) and IFD0 holding one entry,
    /// Orientation (0x0112, SHORT unless `type` says otherwise, count 1, the value left-justified in the 4-byte
    /// field), no next IFD.
    static func exif(_ orientation: Int, littleEndian: Bool, type: Int = 3) -> [UInt8] {
        func n(_ v: Int, _ size: Int) -> [UInt8] {
            let b = (0..<size).map { UInt8(truncatingIfNeeded: v >> (8 * (size - 1 - $0))) }
            return littleEndian ? b.reversed() : b
        }
        // Built as a list of parts: one long `+` chain times out the macOS type checker.
        let entry: [[UInt8]] = [n(1, 2), n(0x0112, 2), n(type, 2), n(1, 4), n(orientation, 2), [0, 0], n(0, 4)]
        let order: [UInt8] = Array((littleEndian ? "II" : "MM").utf8)
        let body: [[UInt8]] = [Array("Exif".utf8), [0, 0], order, n(42, 2), n(8, 4), Array(entry.joined())]
        return segment(0xE1, Array(body.joined()))
    }
    static func dqt(_ id: Int, _ table: [Int]) -> [UInt8] { segment(0xDB, [UInt8(id)] + zigzag.map { UInt8(clamping: table[$0]) }) }
    static func dht(_ tableClass: Int, _ id: Int, _ t: Huffman) -> [UInt8] {
        segment(0xC4, [UInt8(tableClass << 4 | id)] + (t.bits + t.values).map { UInt8($0) })
    }
    /// SOS for `components` (0-based), spectral band ss...se and successive approximation ah, al.
    static func sos(_ components: [Int], _ ss: Int, _ se: Int, _ ah: Int, _ al: Int) -> [UInt8] {
        let selectors = components.flatMap { [UInt8($0 + 1), UInt8(min($0, 1) * 0x11)] }
        return segment(0xDA, [UInt8(components.count)] + selectors + [UInt8(ss), UInt8(se), UInt8(ah << 4 | al)])
    }

    /// A frame: its size, sampling factors per component (one is grey, three YCbCr), quantization tables (component 0
    /// takes table 0 and the luminance Huffman tables, the others table 1 and the chrominance ones), and `block(c, bx, by)`,
    /// component c's quantized block at block column bx and row by, natural order.
    struct Frame {
        var width: Int, height: Int
        var sampling: [(h: Int, v: Int)] = [(1, 1)]
        var tables = [lumaQ, chromaQ]
        var block: (Int, Int, Int) -> [Int]
        var hmax: Int { sampling.map(\.h).max() ?? 1 }
        var vmax: Int { sampling.map(\.v).max() ?? 1 }
        /// A.2.4: MCUs across and down.
        var mcus: (x: Int, y: Int) { ((width + 8 * hmax - 1) / (8 * hmax), (height + 8 * vmax - 1) / (8 * vmax)) }
        /// A.2.2: the blocks across and down a scan of component c alone covers (its own size, not the MCU grid).
        func blocks(_ c: Int) -> (x: Int, y: Int) {
            let w = (width * sampling[c].h + hmax - 1) / hmax, h = (height * sampling[c].v + vmax - 1) / vmax
            return ((w + 7) / 8, (h + 7) / 8)
        }
        /// The blocks of a scan over `components` in coding order, one array per MCU (A.2.2, A.2.3).
        func units(_ components: [Int]) -> [[(c: Int, x: Int, y: Int)]] {
            if components.count == 1, let c = components.first {
                let n = blocks(c)
                return (0..<(n.x * n.y)).map { [(c, $0 % n.x, $0 / n.x)] }
            }
            let m = mcus
            return (0..<(m.x * m.y)).map { (i: Int) -> [(c: Int, x: Int, y: Int)] in
                components.flatMap { (c: Int) -> [(c: Int, x: Int, y: Int)] in
                    let (h, v) = (sampling[c].h, sampling[c].v)
                    return (0..<(h * v)).map { (c, i % m.x * h + $0 % h, i / m.x * v + $0 / h) }
                }
            }
        }
    }

    /// SOI, JFIF, EXIF when `orientation` is set, DQT, SOF (`sof`, `precision`), DHT K.3 and K.4 with the AC tables
    /// `ac` (K.5 and K.6 by default), DRI when `restart` > 0.
    static func header(_ f: Frame, sof: UInt8, precision: Int, restart: Int, orientation: Int?, littleEndian: Bool,
                       ac: (Huffman, Huffman) = (acLuma, acChroma)) -> [UInt8] {
        var bytes: [UInt8] = [0xFF, 0xD8] + jfif + (orientation.map { exif($0, littleEndian: littleEndian) } ?? [])
        bytes += f.tables.enumerated().flatMap { dqt($0.offset, $0.element) }
        let components = f.sampling.enumerated().flatMap { [UInt8($0.offset + 1), UInt8($0.element.h << 4 | $0.element.v), UInt8(min($0.offset, 1))] }
        bytes += segment(sof, [UInt8(precision)] + be16(f.height) + be16(f.width) + [UInt8(f.sampling.count)] + components)
        bytes += dht(0, 0, dcLuma) + dht(1, 0, ac.0) + dht(0, 1, dcChroma) + dht(1, 1, ac.1)
        return bytes + (restart > 0 ? segment(0xDD, be16(restart)) : [])
    }

    /// A sequential Huffman JPEG of `f`: the header, one interleaved scan, EOI. With `restart` n, RSTm follows every n
    /// MCUs (m counting 0...7 and wrapping) and each resets the DC predictions to 0 (F.1.2.1, F.1.2.3).
    static func baseline(_ f: Frame, sof: UInt8 = 0xC0, precision: Int = 8, restart: Int = 0, orientation: Int? = nil,
                         littleEndian: Bool = false) -> Data {
        var w = Bits(), prediction = [Int](repeating: 0, count: f.sampling.count)
        for (i, unit) in f.units(Array(f.sampling.indices)).enumerated() {
            if restart > 0, i > 0, i % restart == 0 {
                w.align(); w.bytes += [0xFF, UInt8(0xD0 + (i / restart - 1) % 8)]
                prediction = prediction.map { _ in 0 }
            }
            for b in unit {
                let q = f.block(b.c, b.x, b.y), d = magnitude(q[0] - prediction[b.c]), codes = huffman[min(b.c, 1)]
                prediction[b.c] = q[0]
                w.put(codes.dc, d.size); w.put(d.bits, d.size)
                encodeAC(zigzag.dropFirst().map { q[$0] }, codes.ac, &w)
            }
        }
        w.align()
        let head = header(f, sof: sof, precision: precision, restart: restart, orientation: orientation, littleEndian: littleEndian)
        return Data(head + sos(Array(f.sampling.indices), 0, 63, 0, 0) + w.bytes + [0xFF, 0xD9])
    }
    /// An AC table of 8-bit codes for every symbol a progressive scan uses: EOB0...EOB14 (r << 4, G.1.2.2), ZRL and
    /// run/size for sizes 1...10. K.5 and K.6 hold no EOBn for n >= 1.
    static let acAll = Huffman(bits: [0, 0, 0, 0, 0, 0, 0, 176] + [Int](repeating: 0, count: 8),
                               values: (0...14).map { $0 << 4 } + [0xF0] + (0..<16).flatMap { r in (1...10).map { r << 4 | $0 } })
    /// One progressive scan's bits, the DC predictions, and G.1.2.2's end-of-band run: EOBRUN bands still to send and,
    /// for a refinement, the correction bits of the blocks it covers, which follow its EOBn symbol and bits.
    struct Scan {
        var w = Bits(), eobrun = 0, held: [Int] = [], prediction = [Int](repeating: 0, count: 4)
        let codes = JPEGFixtures.codes(acAll)
        /// EOBn: symbol n << 4 and n bits of EOBRUN - 2^n, n = floor(log2 EOBRUN), then the held correction bits.
        mutating func flush() {
            guard eobrun > 0 else { return }
            let n = Int.bitWidth - 1 - eobrun.leadingZeroBitCount
            w.put(codes, n << 4); w.put(eobrun - (1 << n), n); held.forEach { w.put($0, 1) }
            (eobrun, held) = (0, [])
        }
        /// A band ending in zeros joins the run with its trailing correction bits; 0x7FFF is the most EOB14 codes.
        mutating func endBand(_ bits: [Int]) { eobrun += 1; held += bits; if eobrun == 0x7FFF { flush() } }
        /// B.2.4.4 and G.1.2.2: RSTm ends the run and the byte, and resets the DC predictions.
        mutating func restart(_ m: Int) {
            flush(); w.align(); w.bytes += [0xFF, UInt8(0xD0 + m % 8)]
            prediction = prediction.map { _ in 0 }
        }
        /// G.1.2.2: a first scan's band as run/size symbols, ZRL per 16 zeros before a non-zero, the zero tail an EOB run.
        mutating func first(_ band: [Int]) {
            var run = 0
            for v in band {
                if v == 0 { run += 1; continue }
                flush()
                while run > 15 { w.put(codes, 0xF0); run -= 16 }
                let m = magnitude(v)
                w.put(codes, run << 4 | m.size); w.put(m.bits, m.size); run = 0
            }
            if run > 0 { endBand([]) }
        }
        /// G.1.2.3, refining |coefficients| one bit (Al = 0 after Al = 1): a coefficient going 0 to 1 is (R, 1) and its
        /// sign (1 positive), R counting only zero-history zeros; one with history gives its correction bit, held until
        /// the next symbol. A ZRL is sent at the next non-zero once 16 zeros have passed, never after the last new
        /// coefficient (the EOB run carries the rest).
        mutating func refine(_ band: [Int]) {
            let t = band.map(abs), last = t.lastIndex(of: 1) ?? -1
            var run = 0, mine: [Int] = []
            for (k, v) in t.enumerated() {
                if v == 0 { run += 1; continue }
                while run > 15, k <= last { flush(); w.put(codes, 0xF0); mine.forEach { w.put($0, 1) }; mine = []; run -= 16 }
                if v > 1 { mine.append(v & 1); continue }
                flush(); w.put(codes, run << 4 | 1); w.put(band[k] > 0 ? 1 : 0, 1); mine.forEach { w.put($0, 1) }
                (mine, run) = ([], 0)
            }
            if run > 0 || !mine.isEmpty { endBand(mine) }
        }
    }
    /// A progressive JPEG of `f` (SOF2, Annex G) coding the same coefficients as `baseline`: DC first at Al 1 and its
    /// refinement (all components interleaved), chroma AC by spectral selection (1...5, 6...63), luma AC 1...63 at
    /// Al 1 (divided toward zero) then refined. Every AC scan holds one component over its own block grid (A.2.2);
    /// zero tails of consecutive blocks merge into EOBn runs. With `restart` n, RSTm follows every n units of a scan.
    static func progressive(_ f: Frame, restart: Int = 0) -> Data {
        let all = Array(f.sampling.indices)
        var out = header(f, sof: 0xC2, precision: 8, restart: restart, orientation: nil, littleEndian: false, ac: (acAll, acAll))
        func scan(_ cs: [Int], _ ss: Int, _ se: Int, _ ah: Int, _ al: Int, _ code: (Int, [Int], inout Scan) -> Void) {
            var s = Scan()
            for (i, unit) in f.units(cs).enumerated() {
                if restart > 0, i > 0, i % restart == 0 { s.restart(i / restart - 1) }
                for b in unit { let q = f.block(b.c, b.x, b.y); code(b.c, zigzag.map { q[$0] }, &s) }
            }
            s.flush(); s.w.align(); out += sos(cs, ss, se, ah, al) + s.w.bytes
        }
        scan(all, 0, 0, 0, 1) { c, z, s in
            let d = magnitude((z[0] >> 1) - s.prediction[c]); s.prediction[c] = z[0] >> 1
            s.w.put(huffman[min(c, 1)].dc, d.size); s.w.put(d.bits, d.size)
        }
        scan(all, 0, 0, 1, 0) { _, z, s in s.w.put(z[0] & 1, 1) }
        for c in all.dropFirst() {
            for (ss, se) in [(1, 5), (6, 63)] { scan([c], ss, se, 0, 0) { _, z, s in s.first(Array(z[ss...se])) } }
        }
        scan([0], 1, 63, 0, 1) { _, z, s in s.first(z.dropFirst().map { $0 < 0 ? -(-$0 >> 1) : $0 >> 1 }) }
        scan([0], 1, 63, 1, 0) { _, z, s in s.refine(Array(z.dropFirst())) }
        return Data(out + [0xFF, 0xD9])
    }
    /// The header and a scan header (DC-only for SOF2) with two entropy bytes: enough for `info`, too short to decode.
    static func stub(_ f: Frame, sof: UInt8 = 0xC0) -> Data {
        let head = header(f, sof: sof, precision: 8, restart: 0, orientation: nil, littleEndian: false)
        return Data(head + sos(Array(f.sampling.indices), 0, sof == 0xC2 ? 0 : 63, 0, 0) + [0x12, 0x34, 0xFF, 0xD9])
    }
    /// The marker segments before the first SOS, then the bytes from SOS on.
    static func split(_ data: Data) -> (segments: [(marker: UInt8, body: [UInt8])], scan: [UInt8]) {
        let b = [UInt8](data)
        var at = 2, segments: [(marker: UInt8, body: [UInt8])] = []
        while at + 4 <= b.count, b[at] == 0xFF, b[at + 1] != 0xDA {
            let end = at + 2 + (Int(b[at + 2]) << 8 | Int(b[at + 3]))
            guard end >= at + 4, end <= b.count else { break }
            segments.append((b[at + 1], Array(b[(at + 4)..<end]))); at = end
        }
        return (segments, Array(b[min(at, b.count)...]))
    }
    static func join(_ segments: [(marker: UInt8, body: [UInt8])], _ scan: [UInt8]) -> Data {
        Data([0xFF, 0xD8] + segments.flatMap { segment($0.marker, $0.body) } + scan)
    }

    /// Seeded quantized blocks, the same for the same seed and block: DC in ±40 (luma) or ±20 (chroma), AC at
    /// (u, v) in ±(4 - u - v), so the high frequencies are zero and the samples rarely clip.
    static func seeded(_ seed: UInt64) -> (Int, Int, Int) -> [Int] {
        { c, x, y in
            var rng = SplitMix64(seed: seed ^ UInt64(c) << 48 ^ UInt64(x) << 24 ^ UInt64(y))
            return (0..<64).map { (i: Int) -> Int in
                let span = i == 0 ? (c == 0 ? 40 : 20) : max(0, 4 - i / 8 - i % 8)
                return Int.random(in: -span...span, using: &rng)
            }
        }
    }
    /// A.3.3: the inverse DCT of a dequantized block (natural order) plus the level shift of 128, clamped to 0...255.
    static func idct(_ s: [Double]) -> [Double] {
        let c = (0..<8).map { (u: Int) -> [Double] in
            (0..<8).map { x in (u == 0 ? 1 / 2.0.squareRoot() : 1) * cos(Double((2 * x + 1) * u) * .pi / 16) }
        }
        return (0..<64).map { (i: Int) -> Double in
            var sum = 0.0
            for v in 0..<8 { for u in 0..<8 { sum += c[u][i % 8] * c[v][i / 8] * s[v * 8 + u] } }
            return min(max(sum / 4 + 128, 0), 255)
        }
    }
    /// The reference image, sRGB levels 0...255 per pixel: each component's samples from `idct`, chroma repeated over
    /// the pixels it covers (box upsampling: sample (x * H / Hmax, y * V / Vmax)), then JFIF 1.02's YCbCr to RGB, clamped.
    static func reference(_ f: Frame) -> [[Double]] {
        var cache: [[Int]: [Double]] = [:]
        func sample(_ c: Int, _ x: Int, _ y: Int) -> Double {
            let key = [c, x / 8, y / 8], table = f.tables[min(c, 1)]
            if cache[key] == nil { let q = f.block(c, x / 8, y / 8); cache[key] = idct(q.indices.map { Double(q[$0] * table[$0]) }) }
            return cache[key]?[y % 8 * 8 + x % 8] ?? 0
        }
        return (0..<(f.width * f.height)).map { (i: Int) -> [Double] in
            let s = f.sampling.indices.map { sample($0, i % f.width * f.sampling[$0].h / f.hmax, i / f.width * f.sampling[$0].v / f.vmax) }
            guard s.count == 3 else { return [s[0], s[0], s[0]] }
            let (y, cb, cr) = (s[0], s[1] - 128, s[2] - 128)
            return [y + 1.402 * cr, y - 0.344_136 * cb - 0.714_136 * cr, y + 1.772 * cb].map { min(max($0, 0), 255) }
        }
    }
    /// `JPEG.read(data)` against `reference(f)`: the mean and largest difference in sRGB levels, alpha's distance from 1
    /// counting toward the largest; infinite for the wrong size.
    static func error(_ data: Data, _ f: Frame) throws -> (mean: Double, max: Double) {
        let read = try JPEG.read(data)
        guard read.width == f.width, read.height == f.height else { return (.infinity, .infinity) }
        var total = 0.0, worst = 0.0
        for (i, want) in reference(f).enumerated() {
            let p = try read.pixel(x: i % f.width, y: i / f.width)
            let got = [p.r, p.g, p.b].map { TransferCurve.encode(Double($0)) * 255 }
            for (a, b) in zip(got, want) { total += abs(a - b); worst = max(worst, abs(a - b)) }
            worst = max(worst, abs(Double(p.a) - 1) * 255)
        }
        return (total / Double(3 * f.width * f.height), worst)
    }
}
