// Inflate.swift: DEFLATE decompression (RFC 1951), bare or zlib-wrapped
// (RFC 1950), for PNG's IDAT stream. Huffman codes decode through a 10-bit
// lookup table, with a canonical bit-by-bit walk for longer codes.
// Invariants: untrusted input throws `CodecError`, never traps; output past
// `limit` throws `tooLarge`, checked before the output grows.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// DEFLATE decompression, from the published RFCs only.
public enum Inflate {
    /// `data` as a zlib stream (a 2-byte header, DEFLATE blocks, a big-endian
    /// Adler-32 of the output), inflated to at most `limit` bytes.
    ///
    /// Throws `CodecError.damaged` on a bad header (method not 8, window over
    /// 32 KiB, failed check bits, a preset dictionary), a bad block, code or
    /// distance, early end of input, or a wrong Adler-32; `tooLarge` once the
    /// output would pass `limit`. Bytes after the Adler-32 are ignored.
    public static func zlib(_ data: Data, limit: Int) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { throw bad("zlib header missing") }
        let cmf = Int(bytes[0]), flg = Int(bytes[1])
        guard cmf & 0x0F == 8 else { throw bad("zlib compression method \(cmf & 0x0F), not 8") }
        guard cmf >> 4 <= 7 else { throw bad("zlib window 2^\((cmf >> 4) + 8) over 32 KiB") }
        guard (cmf << 8 | flg) % 31 == 0 else { throw bad("zlib header check bits fail") }
        guard flg & 0x20 == 0 else { throw bad("zlib preset dictionary not supported") }
        var state = Inflater(bytes, from: 2, limit: limit)
        let end = try state.run()
        guard bytes.count - end >= 4 else { throw bad("Adler-32 missing") }
        let check = bytes[end..<(end + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        guard Deflate.adler32(state.out) == check else { throw bad("Adler-32 mismatch") }
        return Data(state.out)
    }

    /// `data` as bare DEFLATE blocks (stored, fixed and dynamic Huffman), with
    /// no wrapper or checksum, inflated to at most `limit` bytes.
    ///
    /// Throws `CodecError.damaged` on a bad block header, Huffman code, length
    /// or distance code, or a distance past the bytes written, or on input
    /// that ends before the final block; `tooLarge` once the output would pass
    /// `limit`. Bytes after the final block are ignored.
    public static func raw(_ data: Data, limit: Int) throws -> Data {
        var state = Inflater([UInt8](data), from: 0, limit: limit)
        _ = try state.run()
        return Data(state.out)
    }

    static func bad(_ text: String) -> CodecError { .damaged("inflate: " + text) }

    /// RFC 1951, 3.2.5: base lengths and extra bits for codes 257...285, base
    /// distances and extra bits for codes 0...29.
    static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
                                    67, 83, 99, 115, 131, 163, 195, 227, 258]
    static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
                                  1_025, 1_537, 2_049, 3_073, 4_097, 6_145, 8_193, 12_289, 16_385, 24_577]
    static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    /// 3.2.7: the order code-length code lengths arrive in.
    static let order: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
    /// 3.2.6: the fixed literal/length code (288 symbols) and distance code (32, of which 30 and 31 are invalid).
    static let fixedLit = Huffman((0..<288).map { (s: Int) -> UInt8 in s < 144 ? 8 : s < 256 ? 9 : s < 280 ? 7 : 8 })
    static let fixedDist = Huffman([UInt8](repeating: 5, count: 32))
}

/// A canonical Huffman code (3.2.2): `fast` maps the next 10 input bits to
/// symbol << 4 | length (0 when the code is longer or unused); `counts` and
/// `symbols` drive the bit-by-bit walk. `valid` is false for an over-subscribed
/// code, or an incomplete one with more than one symbol.
struct Huffman: Sendable {
    var fast = [UInt16](repeating: 0, count: 1 << 10)
    var counts = [Int](repeating: 0, count: 16)
    var symbols: [UInt16] = []
    var valid = false

    /// `lengths[s]` is symbol s's code length, 0...15.
    init(_ lengths: [UInt8]) {
        for length in lengths { counts[Int(length & 15)] += 1 }
        counts[0] = 0
        var left = 1, used = 0
        for length in 1...15 where left >= 0 { (left, used) = ((left << 1) - counts[length], used + counts[length]) }
        guard left >= 0 else { return }
        guard left == 0 || used <= 1 else { return }
        var offsets = [Int](repeating: 0, count: 16), next = [Int](repeating: 0, count: 16), code = 0
        for length in 1...15 {
            code = (code + counts[length - 1]) << 1
            next[length] = code
            if length < 15 { offsets[length + 1] = offsets[length] + counts[length] }
        }
        symbols = [UInt16](repeating: 0, count: used)
        for (symbol, raw) in lengths.enumerated() where raw & 15 > 0 {
            let length = Int(raw & 15), value = next[length]
            symbols[offsets[length]] = UInt16(symbol)
            (offsets[length], next[length]) = (offsets[length] + 1, value + 1)
            guard length <= 10 else { continue }
            var reversed = 0
            for bit in 0..<length { reversed |= (value >> bit & 1) << (length - 1 - bit) }
            for index in stride(from: reversed, to: 1 << 10, by: 1 << length) { fast[index] = UInt16(symbol << 4 | length) }
        }
        valid = true
    }
}

/// One pass over DEFLATE blocks: an LSB-first bit buffer over `bytes` and the output so far.
struct Inflater {
    let bytes: [UInt8], limit: Int
    var pos: Int, bits: UInt64 = 0, count = 0
    var out: [UInt8] = []

    init(_ bytes: [UInt8], from start: Int, limit: Int) {
        (self.bytes, self.limit, pos) = (bytes, limit, start)
        out.reserveCapacity(min(max(limit, 0), bytes.count * 4 + 65_536))
    }

    /// Inflates every block through the final one; returns the offset of the first byte after it.
    mutating func run() throws -> Int {
        var final = 0
        repeat {
            final = try take(1)
            switch try take(2) {
            case 0: try stored()
            case 1: try codes(Inflate.fixedLit, Inflate.fixedDist)
            case 2:
                let (lit, dist) = try tables()
                try codes(lit, dist)
            default: throw Inflate.bad("reserved block type")
            }
        } while final == 0
        return pos - count / 8
    }

    mutating func refill() {
        while count <= 56, pos < bytes.count {
            bits |= UInt64(bytes[pos]) << UInt64(count)
            (pos, count) = (pos + 1, count + 8)
        }
    }

    /// The next `n` (0...16) bits as an integer, first bit lowest.
    mutating func take(_ n: Int) throws -> Int {
        if count < n {
            refill()
            guard count >= n else { throw Inflate.bad("input ends early") }
        }
        defer { (bits, count) = (bits >> UInt64(n), count - n) }
        return Int(bits & ((1 << UInt64(n)) - 1))
    }

    /// Throws `tooLarge` unless `n` more output bytes stay within `limit`.
    func room(_ n: Int) throws {
        guard n <= limit - out.count else { throw tooLarge() }
    }

    func tooLarge() -> CodecError { .tooLarge("inflate: output past \(limit) bytes") }

    mutating func decode(_ code: Huffman) throws -> Int {
        if count < 15 { refill() }
        let entry = code.fast[Int(bits & 0x3FF)], length = Int(entry & 15)
        if length != 0, length <= count {
            (bits, count) = (bits >> UInt64(length), count - length)
            return Int(entry >> 4)
        }
        var value = 0, first = 0, index = 0
        for length in 1...15 {
            guard count > 0 else { throw Inflate.bad("input ends early") }
            value |= Int(bits & 1)
            (bits, count) = (bits >> 1, count - 1)
            let n = code.counts[length]
            if value - n < first {
                let at = index + value - first
                guard at >= 0, at < code.symbols.count else { break }
                return Int(code.symbols[at])
            }
            (index, first, value) = (index + n, (first + n) << 1, value << 1)
        }
        throw Inflate.bad("unused Huffman code")
    }

    /// 3.2.4: skip to a byte boundary, LEN and its complement NLEN, then LEN bytes.
    mutating func stored() throws {
        (pos, bits, count) = (pos - count / 8, 0, 0)
        guard bytes.count - pos >= 4 else { throw Inflate.bad("input ends early") }
        let length = Int(bytes[pos]) | Int(bytes[pos + 1]) << 8, inverse = Int(bytes[pos + 2]) | Int(bytes[pos + 3]) << 8
        guard length ^ inverse == 0xFFFF else { throw Inflate.bad("stored LEN and NLEN disagree") }
        pos += 4
        guard length <= bytes.count - pos else { throw Inflate.bad("input ends early") }
        try room(length)
        out += bytes[pos..<(pos + length)]
        pos += length
    }

    /// 3.2.5: literals, end of block, and length/distance copies, which may overlap their own output.
    mutating func codes(_ lit: Huffman, _ dist: Huffman) throws {
        while true {
            let symbol = try decode(lit)
            if symbol < 256 {
                guard out.count < limit else { throw tooLarge() }
                out.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return }
            guard symbol < 286 else { throw Inflate.bad("length code \(symbol)") }
            let length = try take(Inflate.lengthExtra[symbol - 257]) + Inflate.lengthBase[symbol - 257]
            let code = try decode(dist)
            guard code < 30 else { throw Inflate.bad("distance code \(code)") }
            let distance = try take(Inflate.distExtra[code]) + Inflate.distBase[code]
            guard distance <= out.count else { throw Inflate.bad("distance past the window") }
            try room(length)
            let start = out.count - distance
            for index in start..<(start + length) { out.append(out[index]) }
        }
    }

    /// 3.2.7: HLIT, HDIST, HCLEN, the code-length code, then both codes' lengths with repeats.
    mutating func tables() throws -> (Huffman, Huffman) {
        let hlit = try take(5) + 257, hdist = try take(5) + 1, hclen = try take(4) + 4
        guard hlit <= 286, hdist <= 30 else { throw Inflate.bad("HLIT or HDIST out of range") }
        var codeLengths = [UInt8](repeating: 0, count: 19)
        for index in 0..<hclen { codeLengths[Inflate.order[index]] = UInt8(try take(3)) }
        let lengthCode = Huffman(codeLengths)
        guard lengthCode.valid else { throw Inflate.bad("bad code-length code") }
        let total = hlit + hdist
        var lengths: [UInt8] = []
        lengths.reserveCapacity(total)
        while lengths.count < total {
            let symbol = try decode(lengthCode)
            if symbol < 16 { lengths.append(UInt8(symbol)); continue }
            var value: UInt8 = 0, times = 0
            if symbol == 16 {
                guard let last = lengths.last else { throw Inflate.bad("repeat with no previous length") }
                value = last
                times = try take(2) + 3
            } else if symbol == 17 {
                times = try take(3) + 3
            } else {
                times = try take(7) + 11
            }
            guard times <= total - lengths.count else { throw Inflate.bad("lengths repeat past the codes") }
            lengths += repeatElement(value, count: times)
        }
        guard lengths[256] != 0 else { throw Inflate.bad("no end-of-block code") }
        let lit = Huffman(Array(lengths[0..<hlit])), dist = Huffman(Array(lengths[hlit...]))
        guard lit.valid, dist.valid else { throw Inflate.bad("bad literal/length or distance code") }
        return (lit, dist)
    }
}
