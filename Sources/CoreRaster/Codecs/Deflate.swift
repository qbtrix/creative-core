// Deflate.swift: DEFLATE compression in a zlib wrapper (RFC 1950, 1951) for
// PNG's IDAT stream. Level 0 writes stored blocks; 1...9 run LZ77 over a
// 32 KiB window into blocks each stored, fixed or dynamic Huffman, whichever
// is smallest (DeflateHuffman.swift; lazy matching from level 4, longer hash
// chains at higher levels). Invariants: deterministic (same input and level,
// same bytes); stored blocks hold at most 65,535 bytes, the last has BFINAL
// set, and empty input is one empty final block.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// DEFLATE compression, from the published RFCs only.
public enum Deflate {
    /// `data` as a zlib stream: header 0x78 0x01, DEFLATE blocks, then the
    /// big-endian Adler-32 of `data`. Never fails.
    ///
    /// `level` 0 writes stored blocks; 1...9 run LZ77 over a 32 KiB window into
    /// stored, fixed or dynamic Huffman blocks, whichever is smallest, searching
    /// longer chains at higher levels. Values outside 0...9 act as the nearest end.
    public static func zlib(_ data: Data, level: Int = 6) -> Data {
        let input = [UInt8](data)
        var writer = BitWriter(bytes: [0x78, 0x01])
        writer.bytes.reserveCapacity(input.count / 2 + 64)
        if level <= 0 { stored(input, final: true, into: &writer) } else { compress(input, level: level, into: &writer) }
        var output = writer.flushed()
        let check = adler32(input)
        for shift in stride(from: 24, through: 0, by: -8) { output.append(UInt8(truncatingIfNeeded: check >> UInt32(shift))) }
        return Data(output)
    }

    static func stored(_ input: [UInt8], final: Bool, into writer: inout BitWriter) {
        var start = 0
        repeat {
            let count = min(65_535, input.count - start)
            let length = UInt16(count)
            writer.put(final && start + count == input.count ? 1 : 0, 3); writer.align()
            writer.bytes += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            writer.bytes += input[start..<(start + count)]
            start += count
        } while start < input.count
    }

    static let blockSymbols = 1 << 15

    /// LZ77 symbols (a literal byte, or length | distance << 9), a block per `blockSymbols`. A match shorter
    /// than `lazy` waits one byte: a longer match there wins and the byte goes out as a literal.
    static func compress(_ input: [UInt8], level: Int, into writer: inout BitWriter) {
        var matcher = Matcher(input, level: level), symbols: [UInt32] = [], start = 0, i = 0, pending: (length: Int, distance: Int)?
        while i < input.count {
            let found = pending ?? matcher.find(i, longerThan: 2); pending = nil
            matcher.insert(i)
            if found.length >= 3, found.length < matcher.lazy {
                let next = matcher.find(i + 1, longerThan: found.length)
                if next.length > 0 { pending = next }
            }
            if pending == nil, found.length >= 3 {
                symbols.append(UInt32(found.distance) << 9 | UInt32(found.length))
                for p in (i + 1)..<(i + found.length) { matcher.insert(p) }
                i += found.length
            } else {
                symbols.append(UInt32(input[i]))
                i += 1
            }
            guard symbols.count >= blockSymbols else { continue }
            block(symbols, Array(input[start..<i]), final: false, into: &writer)
            (symbols, start) = ([], i)
        }
        block(symbols, Array(input[start...]), final: true, into: &writer)
    }

    /// LZ77 over a 32 KiB window: hash chains of 3-byte prefixes, newest first. A search walks at most `chain`
    /// links, a quarter of that once a match reaches `good`, and stops once one reaches `nice`.
    struct Matcher {
        let input: [UInt8], chain: Int, good: Int, nice: Int, lazy: Int
        var head = [Int](repeating: -1, count: 1 << 15), prev = [Int](repeating: -1, count: 1 << 15)
        /// Levels past 9 act as 9. `lazy` is 0 (greedy) at levels 1...3.
        init(_ input: [UInt8], level: Int) {
            let level = min(level, 9)
            (self.input, chain, good) = (input, 4 << (level - 1), level < 4 ? 4 : level < 8 ? 8 : 32)
            (nice, lazy) = (level < 8 ? 16 << (level / 2) : 258, level < 4 ? 0 : level < 8 ? 2 << (level / 2) : 258)
        }

        func hash(_ p: Int) -> Int { (Int(input[p]) << 10 ^ Int(input[p + 1]) << 5 ^ Int(input[p + 2])) & 0x7FFF }

        mutating func insert(_ p: Int) {
            guard p + 2 < input.count else { return }
            let h = hash(p); (prev[p & 0x7FFF], head[h]) = (head[h], p)
        }

        /// The longest earlier match at `i` (at most 258 bytes) longer than `best` bytes, or (0, 0).
        func find(_ i: Int, longerThan best: Int) -> (length: Int, distance: Int) {
            let most = min(258, input.count - i)
            guard i + 2 < input.count, best < most else { return (0, 0) }
            var best = best, distance = 0, candidate = head[hash(i)], left = best >= good ? chain >> 2 : chain
            while candidate >= 0, i - candidate <= 32_768, left > 0 {
                if input[candidate + best] == input[i + best] {
                    var length = 0; while length < most, input[candidate + length] == input[i + length] { length += 1 }
                    if length > best {
                        (best, distance) = (length, i - candidate)
                        if best >= nice || best == most { break }
                        if best >= good { left = min(left, chain >> 2) }
                    }
                }
                let next = prev[candidate & 0x7FFF]; if next >= candidate { break }
                (candidate, left) = (next, left - 1)
            }
            return distance == 0 ? (0, 0) : (best, distance)
        }
    }

    /// The Adler-32 of `bytes` (RFC 1950, 8.2): two sums modulo 65,521,
    /// reduced every 5,552 bytes so neither overflows a UInt32.
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0, index = 0
        while index < bytes.count {
            let end = min(index + 5_552, bytes.count)
            for byte in bytes[index..<end] { a += UInt32(byte); b += a }
            a %= 65_521
            b %= 65_521
            index = end
        }
        return b << 16 | a
    }
}

/// LSB-first bit packing (RFC 1951, 3.1.1); Huffman codes arrive bit-reversed, so they go out most significant bit first.
struct BitWriter {
    var bytes: [UInt8]
    var acc: UInt64 = 0, count: UInt64 = 0

    mutating func put(_ value: Int, _ bits: Int) {
        acc |= UInt64(truncatingIfNeeded: value) << count
        count += UInt64(bits)
        while count >= 8 {
            bytes.append(UInt8(truncatingIfNeeded: acc))
            (acc, count) = (acc >> 8, count - 8)
        }
    }

    mutating func align() {
        if count > 0 { bytes.append(UInt8(truncatingIfNeeded: acc)) }
        (acc, count) = (0, 0)
    }

    /// The bytes with the last partial byte, zero-padded.
    func flushed() -> [UInt8] { count > 0 ? bytes + [UInt8(truncatingIfNeeded: acc)] : bytes }
}
