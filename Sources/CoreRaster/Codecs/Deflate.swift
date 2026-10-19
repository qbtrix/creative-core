// Deflate.swift: DEFLATE compression in a zlib wrapper (RFC 1950, 1951) for
// PNG's IDAT stream. Level 0 writes stored blocks; 1...9 write one fixed-
// Huffman block with greedy LZ77 over a 32 KiB window (hash chains, longer
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
    /// `level` 0 writes stored blocks; 1...9 write a fixed-Huffman block with
    /// LZ77 over a 32 KiB window (hash chains, lazy match off), searching
    /// longer chains at higher levels. Values outside 0...9 act as the nearest end.
    public static func zlib(_ data: Data, level: Int = 6) -> Data {
        let input = [UInt8](data)
        var output: [UInt8] = [0x78, 0x01]
        if level <= 0 { stored(input, into: &output) } else { fixed(input, chain: 4 << (min(level, 9) - 1), into: &output) }
        let check = adler32(input)
        for shift in stride(from: 24, through: 0, by: -8) { output.append(UInt8(truncatingIfNeeded: check >> UInt32(shift))) }
        return Data(output)
    }

    static func stored(_ input: [UInt8], into output: inout [UInt8]) {
        output.reserveCapacity(input.count + input.count / 65_535 * 5 + 11)
        var start = 0
        repeat {
            let count = min(65_535, input.count - start)
            let length = UInt16(count)
            output.append(start + count == input.count ? 1 : 0)
            output += [UInt8(length & 0xFF), UInt8(length >> 8), UInt8(~length & 0xFF), UInt8(~length >> 8)]
            output += input[start..<(start + count)]
            start += count
        } while start < input.count
    }

    /// One final fixed-Huffman block (BTYPE 01): each position takes the longest
    /// match of 3...258 bytes found in `chain` hash-chain steps, else a literal.
    static func fixed(_ input: [UInt8], chain: Int, into output: inout [UInt8]) {
        var writer = BitWriter(bytes: output)
        writer.bytes.reserveCapacity(output.count + input.count + input.count / 8 + 16)
        writer.put(3, 3)
        var head = [Int](repeating: -1, count: 1 << 15), prev = [Int](repeating: -1, count: 1 << 15)
        let n = input.count
        func hash(_ p: Int) -> Int { (Int(input[p]) << 10 ^ Int(input[p + 1]) << 5 ^ Int(input[p + 2])) & 0x7FFF }
        var i = 0
        while i < n {
            var best = 0, distance = 0
            if i + 2 < n {
                var candidate = head[hash(i)], left = chain
                let most = min(258, n - i)
                while candidate >= 0, i - candidate <= 32_768, left > 0 {
                    if input[candidate + best] == input[i + best] {
                        var length = 0
                        while length < most, input[candidate + length] == input[i + length] { length += 1 }
                        if length > best { (best, distance) = (length, i - candidate) }
                        if best == most { break }
                    }
                    let next = prev[candidate & 0x7FFF]
                    if next >= candidate { break }
                    (candidate, left) = (next, left - 1)
                }
            }
            let end = best >= 3 ? i + best : i + 1
            if best >= 3 { writer.match(best, distance) } else { writer.literal(Int(input[i])) }
            while i < end {
                if i + 2 < n { (prev[i & 0x7FFF], head[hash(i)]) = (head[hash(i)], i) }
                i += 1
            }
        }
        writer.literal(256)
        output = writer.flushed()
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

/// LSB-first bit packing with the fixed Huffman codes of RFC 1951, 3.2.6.
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

    /// A Huffman code goes most significant bit first, so its bits are reversed.
    mutating func code(_ value: Int, _ bits: Int) {
        var reversed = 0
        for bit in 0..<bits { reversed |= (value >> bit & 1) << (bits - 1 - bit) }
        put(reversed, bits)
    }

    mutating func literal(_ s: Int) {
        if s < 144 { code(0x30 + s, 8) } else if s < 256 { code(0x190 + s - 144, 9) } else if s < 280 { code(s - 256, 7) } else { code(0xC0 + s - 280, 8) }
    }

    mutating func match(_ length: Int, _ distance: Int) {
        var index = 28
        while Inflate.lengthBase[index] > length { index -= 1 }
        literal(257 + index)
        put(length - Inflate.lengthBase[index], Inflate.lengthExtra[index])
        index = 29
        while Inflate.distBase[index] > distance { index -= 1 }
        code(index, 5)
        put(distance - Inflate.distBase[index], Inflate.distExtra[index])
    }

    /// The bytes with the last partial byte, zero-padded.
    func flushed() -> [UInt8] { count > 0 ? bytes + [UInt8(truncatingIfNeeded: acc)] : bytes }
}
