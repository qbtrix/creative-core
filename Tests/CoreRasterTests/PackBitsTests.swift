// PackBitsTests.swift: PackBits decodes the published example exactly,
// encode then decode is the identity on seeded rows, a run past the row end
// throws, and neither the decoder nor ByteReader traps on truncated bytes.
@testable import CoreRaster
import Testing

@Suite struct PackBitsTests {
    /// The worked example in the published PackBits description.
    @Test func publishedExample() throws {
        let packed: [UInt8] = [0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A, 0xFD, 0xAA, 0x03, 0x80, 0x00, 0x2A,
                               0x22, 0xF7, 0xAA]
        let unpacked: [UInt8] = [0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0xAA, 0xAA, 0xAA, 0xAA, 0x80,
                                 0x00, 0x2A, 0x22] + Array(repeating: 0xAA, count: 10)
        #expect(try PackBits.decode(packed, count: unpacked.count) == unpacked)
        #expect(try PackBits.decode(PackBits.encode(unpacked), count: unpacked.count) == unpacked)
    }

    @Test func seededRowsRoundTrip() throws {
        var rng = SplitMix64(seed: 0x9AC6_B175)
        for _ in 0..<1_000 {
            let count = Int.random(in: 0...400, using: &rng)
            // A small alphabet and sticky repeats give long runs, short runs and literals.
            let alphabet = UInt8.random(in: 1...255, using: &rng)
            var row: [UInt8] = []
            while row.count < count {
                let value = UInt8.random(in: 0...alphabet, using: &rng)
                let length = Bool.random(using: &rng) ? 1 : Int.random(in: 1...300, using: &rng)
                row.append(contentsOf: repeatElement(value, count: min(length, count - row.count)))
            }
            let encoded = PackBits.encode(row)
            #expect(try PackBits.decode(encoded, count: row.count) == row)
        }
    }

    @Test func noOpHeaderIsSkipped() throws {
        #expect(try PackBits.decode([0x80, 0x01, 7, 9, 0x80], count: 2) == [7, 9])
    }

    @Test func runPastEndThrows() throws {
        // A repeat of 4 and a literal of 3 fill rows of exactly that length.
        #expect(try PackBits.decode([0xFD, 5], count: 4) == [5, 5, 5, 5])
        #expect(try PackBits.decode([0x02, 1, 2, 3], count: 3) == [1, 2, 3])
        #expect(throws: CodecError.self) { try PackBits.decode([0xFD, 5], count: 3) }
        #expect(throws: CodecError.self) { try PackBits.decode([0x02, 1, 2, 3], count: 2) }
        #expect(throws: CodecError.self) { try PackBits.decode([0x00, 1, 0xFF, 2], count: 2) }
    }

    @Test func everyTruncationThrows() throws {
        // A no-op, then nine pairs of a 4-byte literal and a 4-byte repeat: 64 bytes in, 72 out.
        var sample: [UInt8] = [0x80]
        for step in 0..<9 {
            let base = UInt8(step * 16)
            sample += [0x03, base, base + 1, base + 2, base + 3, 0xFD, base + 4]
        }
        #expect(sample.count == 64)
        let decoded = try PackBits.decode(sample, count: 72)
        #expect(decoded.count == 72 && decoded.suffix(4) == [132, 132, 132, 132])
        for cut in 0..<sample.count {
            #expect(throws: CodecError.self) { try PackBits.decode(Array(sample[..<cut]), count: 72) }
        }
    }

    /// Every field kind, in order, over 64 bytes 0, 1, ..., 63.
    private static func readFields(_ bytes: [UInt8]) throws -> [UInt64] {
        var reader = ByteReader(bytes)
        var fields: [UInt64] = [UInt64(try reader.u8()), UInt64(try reader.u16()), UInt64(try reader.u32()),
                                UInt64(bitPattern: Int64(try reader.i16())),
                                UInt64(bitPattern: Int64(try reader.i32())),
                                UInt64(try reader.u16LE()), UInt64(try reader.u32LE()),
                                UInt64(try reader.length32())]
        let block = try reader.bytes(20)
        fields.append(UInt64(block.first ?? 0) << 8 | UInt64(block.last ?? 0))
        try reader.skip(9)
        var section = try reader.reader(8)
        fields += [UInt64(try section.u32()), UInt64(try section.u32())]
        #expect(section.isAtEnd)
        #expect(throws: CodecError.self) { try section.u8() }
        fields.append(UInt64(try reader.u32()))
        #expect(reader.isAtEnd && reader.offset == 64)
        return fields
    }

    @Test func byteReaderReadsBothOrdersAndThrowsAtEveryTruncation() throws {
        let sample = (0..<64).map { UInt8($0) }
        #expect(try Self.readFields(sample) == [0, 0x0102, 0x0304_0506, 0x0708, 0x090A_0B0C, 0x0E0D,
                                                0x1211_100F, 0x1314_1516, 0x172A, 0x3435_3637,
                                                0x3839_3A3B, 0x3C3D_3E3F])
        for cut in 0..<sample.count {
            #expect(throws: CodecError.self) { try Self.readFields(Array(sample[..<cut])) }
        }
        var reader = ByteReader([0xFF, 0xFE])
        #expect(try reader.i16() == -2)
        #expect(throws: CodecError.self) { try reader.bytes(-1) }
    }

    @Test func lengthArithmeticThrowsOnOverflow() throws {
        #expect(try ByteReader.adding(3, 4) == 7)
        #expect(try ByteReader.multiplying(30_000, 30_000) == 900_000_000)
        #expect(throws: CodecError.self) { try ByteReader.adding(Int.max, 1) }
        #expect(throws: CodecError.self) { try ByteReader.multiplying(Int.max / 2, 3) }
    }
}
