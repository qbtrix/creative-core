// Deflate.swift: DEFLATE compression in a zlib wrapper (RFC 1950, 1951) for
// PNG's IDAT stream. Until IC-3 every level writes stored blocks, a valid
// stream any inflater reads; IC-3 adds Huffman levels and keeps the
// signature. Invariants: deterministic (same input and level, same bytes);
// stored blocks hold at most 65,535 bytes, the last has BFINAL set, and empty
// input is one empty final block.
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
    /// `level` 0 writes stored blocks; 1...9 will write fixed-Huffman blocks
    /// with LZ77 over a 32 KiB window (hash chains, lazy match off) from IC-3
    /// on, and write stored blocks until then. Values outside 0...9 act as
    /// the nearest end.
    public static func zlib(_ data: Data, level: Int = 6) -> Data {
        let input = [UInt8](data)
        var output: [UInt8] = [0x78, 0x01]
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
        let check = adler32(input)
        for shift in stride(from: 24, through: 0, by: -8) { output.append(UInt8(truncatingIfNeeded: check >> UInt32(shift))) }
        return Data(output)
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
