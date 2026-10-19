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
    /// Dynamic block: HLIT 0, HDIST 0, HCLEN 14; the code-length code gives only symbols 1 and 18 length 2
    /// (codes 00 and 01, two of four unused: incomplete). The rest would decode as an empty block: 18 + 127
    /// and 18 + 107 (256 zeros), 1 for end of block, 1 for the distance code, then end of block (bit 0).
    /// zlib rejects it as "invalid code lengths set".
    static let incompleteLengthCode: [UInt8] = [0x05, 0xC0, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x20, 0xFF, 0xAE, 0x01]
    /// Fixed block: BFINAL 1, BTYPE 01, then literal/length code 286 (8 bits 11000110), which 3.2.6 reserves.
    static let fixed286: [UInt8] = [0x1B, 0x03, 0x00]
    /// Fixed block: 'a' 'b' 'c' as three 8-bit literals, end of block.
    static let fixedABC: [UInt8] = [0x4B, 0x4C, 0x4A, 0x06, 0x00]
    /// Dynamic headers: HLIT 30 (287 codes); HDIST 30 (31 codes); HCLEN 14.
    static let hlit30: [UInt8] = [0xF5, 0xC0, 0x01]
    static let hdist30: [UInt8] = [0x05, 0xDE, 0x01]
    /// Dynamic block: HLIT 0, HDIST 0 (258 lengths), HCLEN 14; the code-length code gives 1 code 0 and 18
    /// code 1. Then 18 + 127 (138 zeros) and 18 + 127 again, 18 more than the 120 left.
    static let repeatPast: [UInt8] = [0x05, 0xC0, 0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0xFF, 0x7F]
    /// The same header, then 18 + 127 and 18 + 109: all 258 lengths 0, so symbol 256 (end of block) has no code.
    static let noEndOfBlock: [UInt8] = [0x05, 0xC0, 0x81, 0x00, 0x00, 0x00, 0x00, 0x00, 0x90, 0xFF, 0x6D, 0x00]
    /// Dynamic block: HLIT 0, HDIST 0, HCLEN 18; code-length code 0 = 3 bits, 1...12, 17 and 18 = 4 bits.
    /// Literal/length lengths 'a' 1, 'b' 2, ... 'l' 12, end of block 12 (a complete code); the one distance
    /// length 0. Data: 'l' (12 bits), 'k' (11 bits), 'a', 'b', 'l', end (12 bits): past the 10-bit fast table,
    /// so 'k', 'l' and the end decode through the bit-by-bit walk. Checked against zlib.
    static let longCodeBlock: [UInt8] = [0x05, 0xC0, 0x41, 0x8E, 0x24, 0x49, 0x92, 0x04, 0xC1, 0xB7, 0x12, 0x8B, 0x9A,
                                         0x47, 0x56, 0xCF, 0xFE, 0xFF, 0xBC, 0xF8, 0xBF, 0xFF, 0xE9, 0xFF, 0xFE, 0x1F]
    static let longCodeOut = Array("lkabl".utf8)
    /// Dynamic block: HLIT 1, HDIST 0, HCLEN 18; code-length code 1 = 1 bit, 2 and 18 = 2 bits. Literal/length
    /// lengths 'a' 1, end 2, 257 2; one distance code, length 1 (incomplete, which 3.2.7 allows for a single
    /// code). Data: 'a', 257 (length 3) distance 1, end. Checked against zlib.
    static let oneDistanceCode: [UInt8] = [0x0D, 0xC0, 0x01, 0x01, 0x00, 0x00, 0x00, 0x80, 0x90, 0xAD, 0xFE, 0x9F, 0x28, 0x16]
    static let oneDistanceOut = Array("aaaa".utf8)
    /// Fixed block: 'a', length code 257 (7 bits 0000001), then distance code 30 (5 bits 11110), which 3.2.6 reserves.
    static let fixedDist30: [UInt8] = [0x4B, 0x04, 0x3E]

    func raw(_ bytes: [UInt8], limit: Int = 1 << 20) throws -> [UInt8] { [UInt8](try Inflate.raw(Data(bytes), limit: limit)) }
    func zlib(_ bytes: [UInt8], limit: Int = 1 << 20) throws -> [UInt8] { [UInt8](try Inflate.zlib(Data(bytes), limit: limit)) }
    /// The full description of the error `raw(bytes)` throws, or "returned".
    func rawError(_ bytes: [UInt8]) -> String {
        do { _ = try raw(bytes); return "returned" } catch { return String(describing: error) }
    }

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

    /// Codes of 11 and 12 bits miss the 10-bit fast table and decode through the canonical walk.
    @Test func longCodes() throws {
        #expect(try raw(Self.longCodeBlock) == Self.longCodeOut)
    }

    /// A dynamic block whose only distance code is one bit long (incomplete, but allowed) decodes.
    @Test func singleDistanceCode() throws {
        #expect(try raw(Self.oneDistanceCode) == Self.oneDistanceOut)
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
        let zlibNamed: [(String, [UInt8], String)] = [
            ("method 9", [0x79, 0x18], "method 9, not 8"), ("window 2^16", [0x88, 0x1C], "over 32 KiB"),
            ("check bits", [0x78, 0x02], "check bits"), ("preset dictionary", [0x78, 0x20], "dictionary"),
        ]
        for (name, header, text) in zlibNamed {
            var message = "returned"
            do { _ = try zlib(header + a.dropFirst(2)) } catch { message = String(describing: error) }
            #expect(message.hasPrefix("damaged") && message.contains(text), "\(name): \(message)")
        }
        let rawCases: [(String, [UInt8])] = [
            ("distance 2 after one byte", [0x4B, 0x04, 0x42, 0x00]),
            ("over-subscribed code-length code", Array(Self.dynamic.prefix(8)) + [0x10] + Self.dynamic.dropFirst(9)),
            ("incomplete code-length code", Self.incompleteLengthCode),
            ("reserved block type", [0x07]), ("LEN and NLEN disagree", [0x01, 0x03, 0x00, 0xFC, 0xFE, 0x61, 0x62, 0x63]),
            ("no final block", [0x00, 0x03, 0x00, 0xFC, 0xFF, 0x61, 0x62, 0x63]), ("cut mid-block", Array(Self.dynamic.prefix(12))),
        ]
        for (name, bytes) in rawCases { #expect(F.thrown { try raw(bytes) } == "damaged", "\(name)") }
        let named: [(String, [UInt8], String)] = [
            ("length code 286 in a fixed block", Self.fixed286, "length code 286"),
            ("distance code 30 in a fixed block", Self.fixedDist30, "distance code 30"),
            ("HLIT 30", Self.hlit30, "HLIT or HDIST"), ("HDIST 30", Self.hdist30, "HLIT or HDIST"),
            ("lengths repeat past the codes", Self.repeatPast, "repeat past"),
            ("no end-of-block code", Self.noEndOfBlock, "no end-of-block"),
        ]
        for (name, bytes, text) in named {
            let message = rawError(bytes)
            #expect(message.hasPrefix("damaged") && message.contains(text), "\(name): \(message)")
        }
    }

    /// Inflate stops at the final block (zlib: at the Adler-32) and ignores what follows.
    @Test func trailingBytesIgnored() throws {
        let data = Data("trailing".utf8)
        #expect(try Inflate.zlib(Deflate.zlib(data) + [0xFF], limit: 64) == data)
        #expect(try raw(Self.fixedA + [0xFF, 0x00]) == [0x61])
    }

    /// The limit is checked before the output grows: a 6-byte stored block then a reserved block type
    /// throws `tooLarge` at limit 5 (not `damaged` after the bytes were kept), `damaged` at limit 6.
    @Test func limitBeforeGrowth() throws {
        let six: [UInt8] = [0x00, 0x06, 0x00, 0xF9, 0xFF] + Array("abcdef".utf8) + [0x07]
        #expect(F.thrown { try raw(six, limit: 5) } == "tooLarge")
        #expect(F.thrown { try raw(six, limit: 6) } == "damaged")
        #expect(F.thrown { try raw(Self.dynamic, limit: 477) } == "tooLarge")
        #expect(F.thrown { try raw(Self.dynamic, limit: 0) } == "tooLarge")
        #expect(F.thrown { try raw(Self.fixedA, limit: 0) } == "tooLarge", "a literal past the limit")
        #expect(F.thrown { try raw(Self.fixedABC, limit: 2) } == "tooLarge", "the third literal past the limit")
        #expect(try raw(Self.fixedABC, limit: 3) == Array("abc".utf8))
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

    /// The only earlier copy of the last 1,000 bytes sits 41,000 bytes back, past the 32 KiB window: a
    /// match there would need a distance code 29 extra value over 13 bits and corrupt the stream.
    @Test func deflateWindowLimit() throws {
        var rng = SplitMix64(seed: 0x1C5)
        let head = (0..<1_000).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let middle = (0..<40_000).map { _ in UInt8.random(in: 0...255, using: &rng) }
        let data = Data(head + middle + head)
        for level in [1, 9] { #expect(try Inflate.zlib(Deflate.zlib(data, level: level), limit: data.count) == data, "level \(level)") }
    }

    /// Higher levels search longer hash chains: on 20,000 seeded bytes over a 4-letter alphabet (every
    /// 3-byte prefix recurs hundreds of times) level 9 finds longer matches than level 1.
    @Test func deflateLevelsSearchLonger() throws {
        var rng = SplitMix64(seed: 0x1C6)
        let data = Data((0..<20_000).map { _ in UInt8.random(in: 0...3, using: &rng) })
        let fast = Deflate.zlib(data, level: 1), best = Deflate.zlib(data, level: 9)
        #expect(best.count < fast.count)
        #expect(try Inflate.zlib(best, limit: data.count) == data)
    }

    /// Levels past 9 search the level-9 chain (1,024 steps), not a longer one: on the same chain-sensitive
    /// data an 8,192-step chain (level 12 unclamped) writes different bytes.
    @Test func deflateLevelAboveNineActsAsNine() throws {
        var rng = SplitMix64(seed: 0x1C6)
        let data = Data((0..<20_000).map { _ in UInt8.random(in: 0...3, using: &rng) })
        let nine = Deflate.zlib(data, level: 9)
        #expect(nine != Deflate.zlib(data, level: 1), "the data is chain-sensitive")
        #expect(Deflate.zlib(data, level: 12) == nine)
        #expect(Deflate.zlib(data, level: Int.max) == nine)
        #expect(Deflate.zlib(data, level: -5) == Deflate.zlib(data, level: 0))
    }

    /// Golden bytes, derived by hand from RFC 1951, 3.2.6 and checked against an independent zlib decoder:
    /// header 78 01; fixed block 'a' 'b' 'c', length 9 (code 263) distance 3 (code 2), 'x' 'y' 'z', end; Adler-32.
    /// A same-process comparison cannot catch output that depends on a per-process hash seed; this can.
    static let goldenText = Data("abcabcabcabcxyz".utf8)
    static let goldenZlib: [UInt8] = [0x78, 0x01, 0x4B, 0x4C, 0x4A, 0x86, 0xA3, 0x8A, 0xCA, 0x2A, 0x00, 0x2E, 0x7F, 0x06, 0x04]

    @Test func deflateDeterministic() throws {
        for level in [1, 6, 9] { #expect([UInt8](Deflate.zlib(Self.goldenText, level: level)) == Self.goldenZlib, "level \(level)") }
        #expect(try zlib(Self.goldenZlib) == [UInt8](Self.goldenText))
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
