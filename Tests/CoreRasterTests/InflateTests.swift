// InflateTests.swift: Inflate against DEFLATE streams derived by hand from
// RFC 1951 (stored, fixed and dynamic Huffman blocks; the bit layouts are in
// the comments) and zlib wrappers from RFC 1950; damaged streams and the
// output limit; Deflate then Inflate on seeded buffers.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct InflateTests {
    typealias F = PNGFixtures
    /// Fixed block (3.2.6): BFINAL 1, BTYPE 01, literal 'a' (0x91, 8 bits), end of block (7 zero bits).
    static let fixedA: [UInt8] = [0x4B, 0x04, 0x00]
    /// Fixed block: 'a' 'b' 'c', length 6 (code 260) distance 3 (code 2), 'x', length 9 (code 263) distance 1
    /// (code 0, a copy that overlaps its own output), end of block.
    static let fixedRepeats: [UInt8] = [0x4B, 0x4C, 0x4A, 0x86, 0xA0, 0x0A, 0x38, 0x00, 0x00]
    static let repeatsOut = Array("abcabcabc".utf8) + [UInt8](repeating: 0x78, count: 10)
    /// Dynamic block (3.2.7): HLIT 28, HDIST 1, HCLEN 14; code-length code 18 = 0, 1 = 10, 2 = 11; literal/length
    /// lengths 'x' 2, end 2, 284 1; two 1-bit distance codes. Data: 'x', 284 + extra 23 (length 250) distance 1,
    /// 284 + extra 0 (length 227) distance 1, end: 478 bytes of 'x'.
    static let dynamic: [UInt8] = [0xE5, 0xC1, 0x81, 0x00, 0x00, 0x00, 0x00, 0x80, 0x20, 0xED, 0xF1, 0x07, 0xA9, 0x72, 0x01, 0x06]
    static let dynamicOut = [UInt8](repeating: 0x78, count: 478)

    func raw(_ bytes: [UInt8], limit: Int = 1 << 20) throws -> [UInt8] { [UInt8](try Inflate.raw(Data(bytes), limit: limit)) }
    func zlib(_ bytes: [UInt8], limit: Int = 1 << 20) throws -> [UInt8] { [UInt8](try Inflate.zlib(Data(bytes), limit: limit)) }

    @Test func storedBlocks() throws {
        #expect(try raw([0x00, 0x02, 0x00, 0xFD, 0xFF, 0x61, 0x62, 0x01, 0x01, 0x00, 0xFE, 0xFF, 0x63]) == Array("abc".utf8))
        #expect(try zlib([0x78, 0x01, 0x01, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63, 0x02, 0x4D, 0x01, 0x27]) == Array("abc".utf8))
        #expect(try zlib(F.stored([])).isEmpty)
        let long = (0..<70_000).map { UInt8(truncatingIfNeeded: $0 * 7) }
        #expect(try zlib(F.stored(long)) == long, "two stored blocks, the first 65,535 bytes")
    }

    @Test func fixedBlocks() throws {
        #expect(try raw(Self.fixedA) == [0x61])
        #expect(try raw(Self.fixedRepeats) == Self.repeatsOut)
        #expect(try zlib(F.zlib(Self.fixedRepeats, of: Self.repeatsOut)) == Self.repeatsOut)
    }

    @Test func dynamicBlocks() throws {
        #expect(try raw(Self.dynamic) == Self.dynamicOut)
        #expect(try zlib(F.zlib(Self.dynamic, of: Self.dynamicOut)) == Self.dynamicOut)
    }

    @Test func adlerChecked() throws {
        var bytes = F.zlib(Self.dynamic, of: Self.dynamicOut)
        bytes[bytes.count - 1] ^= 0x01
        #expect(F.thrown { try zlib(bytes) } == "damaged")
        #expect(F.thrown { try zlib(Array(bytes.dropLast(4))) } == "damaged", "the checksum missing")
    }

    @Test func damagedStreams() throws {
        let a = F.zlib(Self.fixedA, of: [0x61])
        let zlibCases: [(String, [UInt8])] = [
            ("method 9", [0x79, 0x18] + a.dropFirst(2)), ("window over 32 KiB", [0x88, 0x1C] + a.dropFirst(2)),
            ("check bits", [0x78, 0x02] + a.dropFirst(2)), ("preset dictionary", [0x78, 0x20] + a.dropFirst(2)),
            ("empty", []),
        ]
        for (name, bytes) in zlibCases { #expect(F.thrown { try zlib(bytes) } == "damaged", "\(name)") }
        let rawCases: [(String, [UInt8])] = [
            ("distance 2 after one byte", [0x4B, 0x04, 0x42, 0x00]),
            ("over-subscribed code-length code", Array(Self.dynamic.prefix(8)) + [0x10] + Self.dynamic.dropFirst(9)),
            ("reserved block type", [0x07]), ("LEN and NLEN disagree", [0x01, 0x03, 0x00, 0xFC, 0xFE, 0x61, 0x62, 0x63]),
            ("no final block", [0x00, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63]), ("cut mid-block", Array(Self.dynamic.prefix(12))),
        ]
        for (name, bytes) in rawCases { #expect(F.thrown { try raw(bytes) } == "damaged", "\(name)") }
    }

    /// The limit is checked before the output grows: a 6-byte stored block then a reserved block type
    /// throws `tooLarge` at limit 5 (not `damaged` after the bytes were kept), `damaged` at limit 6.
    @Test func limitBeforeGrowth() throws {
        let six: [UInt8] = [0x00, 0x06, 0x00, 0xF9, 0xFF] + Array("abcdef".utf8) + [0x07]
        #expect(F.thrown { try raw(six, limit: 5) } == "tooLarge")
        #expect(F.thrown { try raw(six, limit: 6) } == "damaged")
        #expect(F.thrown { try raw(Self.dynamic, limit: 477) } == "tooLarge")
        #expect(F.thrown { try raw(Self.dynamic, limit: 0) } == "tooLarge")
        #expect(try raw(Self.dynamic, limit: 478) == Self.dynamicOut)
        #expect(F.thrown { try zlib(F.stored([UInt8](repeating: 1, count: 1_000)), limit: 999) } == "tooLarge")
    }

    @Test func deflateRoundTrip() throws {
        var rng = SplitMix64(seed: 0x1C3)
        for i in 0..<1_000 {
            var bytes: [UInt8] = []
            for _ in 0..<Int.random(in: 0...6, using: &rng) {
                let n = Int.random(in: 0...400, using: &rng), run = UInt8.random(in: 0...255, using: &rng)
                bytes += Bool.random(using: &rng) ? (0..<n).map { _ in UInt8.random(in: 0...255, using: &rng) } : [UInt8](repeating: run, count: n)
            }
            let level = i % 10, data = Data(bytes)
            #expect(try Inflate.zlib(Deflate.zlib(data, level: level), limit: bytes.count) == data, "case \(i) level \(level)")
        }
        let big = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 / 3) })
        #expect(try Inflate.zlib(Deflate.zlib(big, level: 6), limit: big.count) == big)
    }

    @Test func deflateDeterministic() {
        let text = Data((0..<5_000).map { UInt8(truncatingIfNeeded: ($0 % 97) * 3) })
        for level in 0...9 { #expect(Deflate.zlib(text, level: level) == Deflate.zlib(text, level: level)) }
        let fixed = [UInt8](Deflate.zlib(text, level: 6))
        #expect(fixed.count > 2 && fixed[2] & 0x06 == 0x02, "levels 1...9 write fixed-Huffman blocks (BTYPE 01)")
        #expect(fixed.count < Deflate.zlib(text, level: 0).count)
    }

    @Test func fuzzed() {
        let seeds = [F.zlib(Self.dynamic, of: Self.dynamicOut), F.zlib(Self.fixedRepeats, of: Self.repeatsOut), F.stored(Array("abcdef".utf8), block: 2)]
        let cases = mutations(of: seeds.map { Data($0) }, count: 1_000, seed: 0x1C4)
        fuzz(cases) { _ = try Inflate.zlib($0, limit: 1 << 16) }
        fuzz(cases.map { $0.dropFirst(2) }) { _ = try Inflate.raw($0, limit: 1 << 16) }
    }
}
