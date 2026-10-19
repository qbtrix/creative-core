// DeflateTests.swift: Deflate's block choice (stored, fixed or dynamic
// Huffman, RFC 1951 3.2.4 to 3.2.7), its length-limited codes, its bounded
// per-level match search, and seeded round trips through Inflate.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct DeflateTests {
    /// Bits 1-2 of the first block header byte (after the 2-byte zlib header): 0 stored, 1 fixed, 2 dynamic.
    static func firstBlockType(_ stream: Data) -> Int { Int([UInt8](stream)[2] >> 1 & 3) }

    /// Seeded bytes 0...31 skewed toward 0 (the product of two uniform bytes over 2,048): few long matches,
    /// so the gain comes from codes fitted to the counts. The fixed-only Deflate wrote 35,448 bytes here.
    @Test func skewedBytesTakeDynamicBlocks() throws {
        var rng = SplitMix64(seed: 0x1C9B)
        let bytes = (0..<40_000).map { _ in UInt8((Int.random(in: 0...255, using: &rng) * Int.random(in: 0...255, using: &rng)) >> 11) }
        let stream = Deflate.zlib(Data(bytes), level: 6)
        #expect(Self.firstBlockType(stream) == 2)
        #expect(stream.count < 30_000, "\(stream.count) bytes")
        #expect(try Inflate.zlib(stream, limit: bytes.count) == Data(bytes))
    }

    /// Seeded random bytes do not compress: each block is stored, a few bytes over the input.
    @Test func randomBytesTakeStoredBlocks() throws {
        var rng = SplitMix64(seed: 0x1C9C)
        let data = Data((0..<100_000).map { _ in UInt8.random(in: 0...255, using: &rng) })
        let stream = Deflate.zlib(data, level: 6)
        #expect(Self.firstBlockType(stream) == 0)
        #expect(stream.count < data.count + 64, "\(stream.count) bytes")
        #expect(try Inflate.zlib(stream, limit: data.count) == data)
    }

    /// Kraft's sum of a complete code: each length l adds 2^(15 - l), and the total is 2^15.
    static func kraft(_ lengths: [UInt8]) -> Int { lengths.reduce(0) { $1 == 0 ? $0 : $0 + 1 << (15 - Int($1)) } }

    /// Fibonacci counts make an unlimited Huffman code as deep as the symbols are many; the codes stay within
    /// 15 bits (7 for the code-length code), complete, and never longer for a more frequent symbol.
    @Test func lengthsStayWithinTheLimit() throws {
        var fib = [1, 1]
        while fib.count < 30 { fib.append(fib[fib.count - 1] + fib[fib.count - 2]) }
        for (count, limit) in [(30, 15), (19, 7)] {
            let lengths = Deflate.huffmanLengths(Array(fib.prefix(count)), limit: limit)
            #expect(lengths.allSatisfy { $0 >= 1 && Int($0) <= limit }, "limit \(limit): \(lengths)")
            #expect(Self.kraft(lengths) == 1 << 15, "limit \(limit): \(lengths)")
            #expect(zip(lengths, lengths.dropFirst()).allSatisfy { $0 >= $1 }, "limit \(limit): \(lengths)")
        }
        #expect(Deflate.huffmanLengths([0, 0, 5, 0], limit: 15) == [1, 0, 1, 0], "a lone symbol gets a partner")
        #expect(Deflate.huffmanLengths([0, 0, 0], limit: 15) == [1, 1, 0], "no symbol: two 1-bit codes")
        var rng = SplitMix64(seed: 0x1C9D)
        let bytes = (0..<24).flatMap { [UInt8](repeating: UInt8($0), count: fib[$0]) }.shuffled(using: &rng)
        for level in [1, 6] { #expect(try Inflate.zlib(Deflate.zlib(Data(bytes), level: level), limit: bytes.count) == Data(bytes)) }
    }

    /// X (300 seeded bytes), then X's first 200 bytes and 100 others, then X again. At 600 the newest
    /// candidate matches 200 bytes, the older one 258 (the most). Level 6 stops at its nice length (128);
    /// level 9 (nice 258) searches on. A run of zeros finds 258 at distance 1 even at level 1 (nice 16).
    @Test func niceLengthEndsTheSearch() {
        var rng = SplitMix64(seed: 0x1C9E)
        let x = (0..<300).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let junk = [x[200] ^ 0xFF] + (0..<99).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let input = x + Array(x.prefix(200)) + junk + x
        for (level, length, distance) in [(6, 200, 300), (9, 258, 600)] {
            var matcher = Deflate.Matcher(input, level: level)
            for p in 0..<600 { matcher.insert(p) }
            let found = matcher.find(600, longerThan: 0)
            #expect(found.length == length && found.distance == distance, "level \(level): \(found)")
        }
        var zeros = Deflate.Matcher([UInt8](repeating: 0, count: 1_000), level: 1)
        for p in 0..<10 { zeros.insert(p) }
        #expect(zeros.find(10, longerThan: 0) == (258, 1))
    }

    /// 1,000 seeded buffers (runs, noise, a small alphabet, copies of earlier bytes) at levels 0...9 come back
    /// whole and deflate to the same bytes twice; so does one 300 KB buffer of many blocks at levels 1, 6 and 9.
    @Test func seededRoundTrips() throws {
        var rng = SplitMix64(seed: 0x1C9F)
        func piece(_ n: Int, _ bytes: [UInt8]) -> [UInt8] {
            switch Int.random(in: 0...3, using: &rng) {
            case 0: return [UInt8](repeating: .random(in: 0...255, using: &rng), count: n)
            case 1: return (0..<n).map { _ in .random(in: 0...255, using: &rng) }
            case 2: return (0..<n).map { _ in .random(in: 97...100, using: &rng) }
            default:
                guard !bytes.isEmpty else { return [] }
                let start = Int.random(in: 0..<bytes.count, using: &rng)
                return Array(bytes[start..<min(bytes.count, start + n)])
            }
        }
        for i in 0..<1_000 {
            var bytes: [UInt8] = []
            for _ in 0..<Int.random(in: 0...8, using: &rng) { bytes += piece(Int.random(in: 0...600, using: &rng), bytes) }
            let data = Data(bytes), stream = Deflate.zlib(data, level: i % 10)
            #expect(try Inflate.zlib(stream, limit: bytes.count) == data, "case \(i)")
            #expect(Deflate.zlib(data, level: i % 10) == stream, "case \(i)")
        }
        var big: [UInt8] = []
        while big.count < 300_000 { big += piece(Int.random(in: 1...5_000, using: &rng), big) }
        for level in [1, 6, 9] { #expect(try Inflate.zlib(Deflate.zlib(Data(big), level: level), limit: big.count) == Data(big)) }
    }
}
