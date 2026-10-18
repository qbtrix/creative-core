// ByteReader.swift: a bounds-checked cursor over untrusted bytes, for the
// layered-codec readers (PSD records are big-endian; the zip container is
// little-endian, so both orders are here). Every read checks its count
// against the bytes left first and throws `CodecError.damaged` instead of
// trapping; length arithmetic goes through `adding` and `multiplying`, which
// throw `CodecError.tooLarge` on overflow. A sub-reader shares storage, so
// framing a section by its length copies nothing. `crc32`, the IEEE CRC-32, is shared by zip and PNG.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ByteReader: Sendable {
    private let storage: ArraySlice<UInt8>
    /// The absolute index of the next byte in `storage`.
    private var position: Int

    init(_ bytes: [UInt8]) { self.init(slice: bytes[...]) }

    init(_ data: Data) { self.init([UInt8](data)) }

    private init(slice: ArraySlice<UInt8>) {
        storage = slice
        position = slice.startIndex
    }

    /// Bytes read so far, from the start of this reader.
    var offset: Int { position - storage.startIndex }
    /// Bytes not yet read.
    var remaining: Int { storage.endIndex - position }
    var isAtEnd: Bool { remaining == 0 }

    /// Moves past the next `count` bytes and returns where they start, or
    /// throws when fewer remain. The one bounds check every read goes through.
    private mutating func advance(_ count: Int) throws -> Int {
        guard count >= 0, count <= remaining else {
            throw CodecError.damaged("need \(count) bytes at offset \(offset), \(remaining) left")
        }
        let start = position
        position += count
        return start
    }

    mutating func u8() throws -> UInt8 { storage[try advance(1)] }

    mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }

    /// Reads `width` bytes as one unsigned big-endian (or little-endian) value.
    private mutating func unsigned(_ width: Int, bigEndian: Bool) throws -> UInt64 {
        let start = try advance(width)
        var value: UInt64 = 0
        for step in 0..<width {
            let index = bigEndian ? start + step : start + width - 1 - step
            value = value << 8 | UInt64(storage[index])
        }
        return value
    }

    mutating func u16() throws -> UInt16 { UInt16(truncatingIfNeeded: try unsigned(2, bigEndian: true)) }
    mutating func u32() throws -> UInt32 { UInt32(truncatingIfNeeded: try unsigned(4, bigEndian: true)) }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func u16LE() throws -> UInt16 { UInt16(truncatingIfNeeded: try unsigned(2, bigEndian: false)) }
    mutating func u32LE() throws -> UInt32 { UInt32(truncatingIfNeeded: try unsigned(4, bigEndian: false)) }

    /// A big-endian UInt32 length as an `Int`, so it can be compared and summed.
    mutating func length32() throws -> Int {
        let value = try u32()
        guard let length = Int(exactly: value) else {
            throw CodecError.tooLarge("length \(value) at offset \(offset - 4)")
        }
        return length
    }

    /// The next `count` bytes, copied out.
    mutating func bytes(_ count: Int) throws -> [UInt8] {
        let start = try advance(count)
        return Array(storage[start..<(start + count)])
    }

    mutating func skip(_ count: Int) throws { _ = try advance(count) }

    /// A reader over the next `count` bytes, which this reader moves past;
    /// the sub-reader cannot read beyond them.
    mutating func reader(_ count: Int) throws -> ByteReader {
        let start = try advance(count)
        return ByteReader(slice: storage[start..<(start + count)])
    }

    /// `a + b` for lengths read from a file, throwing instead of overflowing.
    static func adding(_ a: Int, _ b: Int) throws -> Int {
        let (sum, overflow) = a.addingReportingOverflow(b)
        guard !overflow else { throw CodecError.tooLarge("length \(a) + \(b) overflows") }
        return sum
    }

    /// `a * b` for sizes read from a file, throwing instead of overflowing.
    static func multiplying(_ a: Int, _ b: Int) throws -> Int {
        let (product, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow else { throw CodecError.tooLarge("size \(a) x \(b) overflows") }
        return product
    }
}

extension ByteReader {
    /// Eight 256-entry tables, flat: table k at `k * 256`. Table 0 is the
    /// byte-at-a-time table; table k advances table k - 1 by one zero byte.
    static let crcTables: [UInt32] = {
        var tables = [UInt32](repeating: 0, count: 8 * 256)
        for byte in 0..<256 {
            var crc = UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
            tables[byte] = crc
        }
        for index in 256..<(8 * 256) {
            let previous = tables[index - 256]
            tables[index] = (previous >> 8) ^ tables[Int(previous & 0xFF)]
        }
        return tables
    }()

    /// The IEEE CRC-32 of `bytes`, eight bytes per step.
    static func crc32<Bytes: Collection>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 {
        let input = Array(bytes)
        let tables = crcTables
        var crc: UInt32 = 0xFFFF_FFFF
        var index = 0
        while input.count - index >= 8 {
            let low = crc ^ (UInt32(input[index]) | UInt32(input[index + 1]) << 8
                | UInt32(input[index + 2]) << 16 | UInt32(input[index + 3]) << 24)
            crc = tables[7 * 256 + Int(low & 0xFF)] ^ tables[6 * 256 + Int((low >> 8) & 0xFF)]
                ^ tables[5 * 256 + Int((low >> 16) & 0xFF)] ^ tables[4 * 256 + Int(low >> 24)]
                ^ tables[3 * 256 + Int(input[index + 4])] ^ tables[2 * 256 + Int(input[index + 5])]
                ^ tables[256 + Int(input[index + 6])] ^ tables[Int(input[index + 7])]
            index += 8
        }
        while index < input.count {
            crc = tables[Int((crc ^ UInt32(input[index])) & 0xFF)] ^ (crc >> 8)
            index += 1
        }
        return crc ^ 0xFFFF_FFFF
    }
}
