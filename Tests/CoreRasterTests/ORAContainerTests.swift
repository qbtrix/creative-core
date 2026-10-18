// ORAContainerTests.swift: ZipStore, the stored-only zip container of
// OpenRaster files. The writer gives pinned bytes, puts `mimetype` at offset
// 30 and round-trips; the reader refuses compressed entries by name, bad
// CRCs, every truncation and seeded byte damage without crashing; the CRC-32
// matches the published check values.
@testable import CoreRaster
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct ORAContainerTests {
    static let files: [String: Data] = [
        "mimetype": Data("image/openraster".utf8), "stack.xml": Data("<image/>".utf8),
        "data/b.png": Data("B".utf8), "Thumbnails/t.png": Data("T".utf8),
    ]

    /// The archive of `files` with `mimetype` first, laid out field by field
    /// from the PKWARE APPNOTE (stored, DOS date 1980-01-01 00:00, version
    /// needed 1.0, made by 2.0, paths after `mimetype` sorted by byte:
    /// Thumbnails/t.png, data/b.png, stack.xml) and checked with an independent
    /// zip reader. Photo's adoption of ZipStore compares its own output
    /// against these same bytes.
    static let golden: [UInt8] = hexBytes([
        "504b03040a000000000000002100c79af08c1000000010000000080000006d696d6574797065696d6167652f6f70656e",
        "726173746572504b03040a000000000000002100607a04be0100000001000000100000005468756d626e61696c732f74",
        "2e706e6754504b03040a00000000000000210031cfd04a01000000010000000a000000646174612f622e706e6742504b",
        "03040a000000000000002100a331c682080000000800000009000000737461636b2e786d6c3c696d6167652f3e504b01",
        "0214000a000000000000002100c79af08c10000000100000000800000000000000000000000000000000006d696d6574",
        "797065504b010214000a000000000000002100607a04be01000000010000001000000000000000000000000000360000",
        "005468756d626e61696c732f742e706e67504b010214000a00000000000000210031cfd04a01000000010000000a0000",
        "000000000000000000000065000000646174612f622e706e67504b010214000a000000000000002100a331c682080000",
        "000800000009000000000000000000000000008e000000737461636b2e786d6c504b05060000000004000400e3000000",
        "bd0000000000",
    ])

    static func hexBytes(_ lines: [String]) -> [UInt8] {
        let digits = Array(lines.joined().utf8).map { UInt8(String(UnicodeScalar($0)), radix: 16) ?? 0 }
        return stride(from: 0, to: digits.count - 1, by: 2).map { digits[$0] << 4 | digits[$0 + 1] }
    }

    /// The offset of the header with `signature` whose name, `headerCount`
    /// bytes in, is `name`.
    static func header(_ bytes: [UInt8], signature: [UInt8], headerCount: Int, name: String) -> Int? {
        let nameBytes = Array(name.utf8)
        return (0...(bytes.count - headerCount - nameBytes.count)).first { offset in
            Array(bytes[offset..<(offset + 4)]) == signature
                && Array(bytes[(offset + headerCount)..<(offset + headerCount + nameBytes.count)]) == nameBytes
        }
    }

    @Test func sameBytesAsPhoto() throws {
        #expect([UInt8](try ZipStore.archive(Self.files, first: "mimetype")) == Self.golden)
    }

    @Test func mimetypeAtOffset30() throws {
        let bytes = [UInt8](try ZipStore.archive(Self.files, first: "mimetype"))
        #expect(Array(bytes[30..<38]) == Array("mimetype".utf8))
        #expect(Array(bytes[38..<54]) == Array("image/openraster".utf8))
    }

    @Test func roundTrips() throws {
        #expect(try ZipStore.entries(Data(Self.golden)) == Self.files)
        var rng = SplitMix64(seed: 0x5A1F)
        var files: [String: Data] = [:]
        for index in 0..<40 {
            let count = Int.random(in: 0...300, using: &rng)
            files["layer \(index) é.png"] = Data((0..<count).map { _ in UInt8.random(in: 0...255, using: &rng) })
        }
        #expect(try ZipStore.entries(try ZipStore.archive(files, first: nil)) == files)
    }

    @Test func refusesMissingFirstAndEmptyName() {
        #expect(throws: CodecError.unsupported("first entry mimetype is not in the archive")) {
            try ZipStore.archive(["a": Data()], first: "mimetype")
        }
        #expect(throws: CodecError.unsupported("empty entry name")) { try ZipStore.archive(["": Data()], first: nil) }
    }

    @Test func compressedEntryThrows() throws {
        var bytes = Self.golden
        let name = "stack.xml"
        let local = try #require(Self.header(bytes, signature: [0x50, 0x4B, 3, 4], headerCount: 30, name: name))
        let central = try #require(Self.header(bytes, signature: [0x50, 0x4B, 1, 2], headerCount: 46, name: name))
        bytes[local + 8] = 8
        bytes[central + 10] = 8
        #expect(throws: CodecError.compressedEntry("stack.xml")) { try ZipStore.entries(Data(bytes)) }
    }

    @Test func badCRCThrows() {
        var bytes = Self.golden
        bytes[38] ^= 0x01  // first byte of the mimetype entry's data
        #expect(throws: CodecError.damaged("CRC of mimetype")) { try ZipStore.entries(Data(bytes)) }
    }

    @Test func everyTruncationThrows() {
        for count in 0..<Self.golden.count {
            #expect(throws: CodecError.self) { try ZipStore.entries(Data(Self.golden.prefix(count))) }
        }
    }

    @Test func seededDamageNeverCrashes() {
        var rng = SplitMix64(seed: 0x0DA7_A5E7)
        for _ in 0..<500 {
            var bytes = Self.golden
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                bytes[Int.random(in: 0..<bytes.count, using: &rng)] = UInt8.random(in: 0...255, using: &rng)
            }
            if Bool.random(using: &rng) { bytes = Array(bytes.prefix(Int.random(in: 0...bytes.count, using: &rng))) }
            do {
                _ = try ZipStore.entries(Data(bytes))
            } catch {
                #expect(error is CodecError)
            }
        }
    }

    @Test func crcMatches() {
        #expect(ZipStore.crc32([UInt8]()) == 0)
        #expect(ZipStore.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(ZipStore.crc32(Array("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
    }
}
