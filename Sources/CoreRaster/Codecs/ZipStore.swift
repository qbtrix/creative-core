// ZipStore.swift: the stored-only zip container OpenRaster files use, written
// from the PKWARE APPNOTE (local file header, central directory, end of
// central directory record) and the OpenRaster spec's container rules.
// Invariants a reader must keep:
// - Writing is deterministic: every entry stored (method 0), the `first`
//   entry (`mimetype` for ORA) first so its name sits at byte offset 30, the
//   other paths sorted by their UTF-8 bytes, one fixed DOS date and time, no
//   extra fields, no comment. The same files always give the same bytes.
// - Reading never trusts a length: every field read is bounds checked against
//   the bytes, a method other than 0 throws `compressedEntry` naming the
//   entry, and a CRC that does not match throws `damaged`. The entry sizes'
//   running total may not pass the archive's byte count, so entries that all
//   point at one body throw before they are copied.
// - CRC-32 is the IEEE one (reflected polynomial 0xEDB88320), slicing-by-8.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Writes and reads zip archives whose entries are stored, not compressed.
public enum ZipStore {
    static let localSignature: UInt32 = 0x0403_4B50
    static let centralSignature: UInt32 = 0x0201_4B50
    static let endSignature: UInt32 = 0x0605_4B50
    static let localHeaderCount = 30
    static let centralHeaderCount = 46
    static let endRecordCount = 22
    /// 1980-01-01 00:00:00, the earliest DOS date: (0 << 9) | (1 << 5) | 1.
    static let dosDate: UInt16 = 0x0021
    static let dosTime: UInt16 = 0
    /// Version 1.0 is enough to extract a stored entry; written by 2.0, MS-DOS.
    static let versionNeeded: UInt16 = 10
    static let versionMadeBy: UInt16 = 20
    /// General purpose bit 11: the name is UTF-8.
    static let utf8Flag: UInt16 = 0x0800

    /// The archive of `files`, with the entry named `first` (if given) first and
    /// the rest sorted. Throws `tooLarge` past the plain zip limits (65,535
    /// entries or name bytes, 4 GiB sizes or offsets) and `unsupported` for an
    /// empty name or a `first` that is not in `files`.
    public static func archive(_ files: [String: Data], first: String?) throws -> Data {
        var order = files.keys.filter { $0 != first }
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        if let first {
            guard files[first] != nil else { throw CodecError.unsupported("first entry \(first) is not in the archive") }
            order.insert(first, at: 0)
        }
        guard order.count <= Int(UInt16.max) else { throw CodecError.tooLarge("\(order.count) entries") }
        var local: [UInt8] = []
        var central: [UInt8] = []
        for name in order {
            let data = [UInt8](files[name] ?? Data())
            let nameBytes = Array(name.utf8)
            guard !nameBytes.isEmpty else { throw CodecError.unsupported("empty entry name") }
            guard nameBytes.count <= Int(UInt16.max) else { throw CodecError.tooLarge("entry name \(name)") }
            guard data.count <= Int(UInt32.max) else { throw CodecError.tooLarge("entry \(name)") }
            guard local.count <= Int(UInt32.max) else { throw CodecError.tooLarge("archive offset at \(name)") }
            let flags: UInt16 = nameBytes.contains { $0 >= 0x80 } ? utf8Flag : 0
            let crc = ByteReader.crc32(data)
            let offset = UInt32(local.count)
            // Shared tail of both headers: flags through extra length.
            var common: [UInt8] = []
            for half in [flags, 0, dosTime, dosDate] { appendLE(half, to: &common) }
            for word in [crc, UInt32(data.count), UInt32(data.count)] { appendLE(word, to: &common) }
            appendLE(UInt16(nameBytes.count), to: &common)
            appendLE(UInt16(0), to: &common)

            appendLE(localSignature, to: &local)
            appendLE(versionNeeded, to: &local)
            local += common + nameBytes + data

            appendLE(centralSignature, to: &central)
            appendLE(versionMadeBy, to: &central)
            appendLE(versionNeeded, to: &central)
            central += common
            // Comment length, disk start, internal attributes, external attributes.
            for half: UInt16 in [0, 0, 0] { appendLE(half, to: &central) }
            appendLE(UInt32(0), to: &central)
            appendLE(offset, to: &central)
            central += nameBytes
        }
        guard local.count <= Int(UInt32.max), central.count <= Int(UInt32.max) else {
            throw CodecError.tooLarge("archive")
        }
        var end: [UInt8] = []
        appendLE(endSignature, to: &end)
        for half: UInt16 in [0, 0, UInt16(order.count), UInt16(order.count)] { appendLE(half, to: &end) }
        appendLE(UInt32(central.count), to: &end)
        appendLE(UInt32(local.count), to: &end)
        appendLE(UInt16(0), to: &end)
        return Data(local + central + end)
    }

    /// Every entry of a stored-only archive, by path. Throws `notThisFormat`
    /// without an end of central directory record, `compressedEntry` for an
    /// entry that is not stored, `unsupported` for an encrypted one, and
    /// `damaged` for anything out of bounds, a duplicate path or a bad CRC.
    public static func entries(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        let end = try endRecordOffset(bytes)
        let count = Int(try readLE16(bytes, end + 10))
        let centralSize = Int(try readLE32(bytes, end + 12))
        let centralStart = Int(try readLE32(bytes, end + 16))
        guard centralStart <= end, centralSize <= end - centralStart else {
            throw CodecError.damaged("central directory outside the archive")
        }
        var result: [String: Data] = [:]
        var cursor = centralStart, total = 0
        for _ in 0..<count {
            guard try readLE32(bytes, cursor) == centralSignature else {
                throw CodecError.damaged("central directory entry at \(cursor)")
            }
            let flags = try readLE16(bytes, cursor + 8)
            let method = try readLE16(bytes, cursor + 10)
            let crc = try readLE32(bytes, cursor + 16)
            let size = Int(try readLE32(bytes, cursor + 20))
            let storedSize = Int(try readLE32(bytes, cursor + 24))
            let nameCount = Int(try readLE16(bytes, cursor + 28))
            let skipCount = Int(try readLE16(bytes, cursor + 30)) + Int(try readLE16(bytes, cursor + 32))
            let localStart = Int(try readLE32(bytes, cursor + 42))
            let name = String(decoding: try slice(bytes, cursor + centralHeaderCount, nameCount), as: UTF8.self)
            cursor += centralHeaderCount + nameCount + skipCount
            guard method == 0 else { throw CodecError.compressedEntry(name) }
            guard flags & 1 == 0 else { throw CodecError.unsupported("encrypted entry \(name)") }
            guard size == storedSize else { throw CodecError.damaged("sizes differ for \(name)") }
            total += size
            guard total <= bytes.count else { throw CodecError.damaged("entries overlap at \(name)") }
            guard try readLE32(bytes, localStart) == localSignature else {
                throw CodecError.damaged("local header of \(name)")
            }
            let localName = Int(try readLE16(bytes, localStart + 26))
            let localExtra = Int(try readLE16(bytes, localStart + 28))
            let body = try slice(bytes, localStart + localHeaderCount + localName + localExtra, size)
            guard ByteReader.crc32(body) == crc else { throw CodecError.damaged("CRC of \(name)") }
            guard result.updateValue(Data(body), forKey: name) == nil else {
                throw CodecError.damaged("duplicate entry \(name)")
            }
        }
        return result
    }

    /// The offset of the end of central directory record: searched backwards,
    /// since a comment of up to 65,535 bytes may follow it.
    private static func endRecordOffset(_ bytes: [UInt8]) throws -> Int {
        guard bytes.count >= endRecordCount else { throw CodecError.notThisFormat }
        let last = bytes.count - endRecordCount
        for offset in stride(from: last, through: max(0, last - Int(UInt16.max)), by: -1) {
            if try readLE32(bytes, offset) == endSignature,
               Int(try readLE16(bytes, offset + 20)) == last - offset { return offset }
        }
        throw CodecError.notThisFormat
    }

    /// `count` bytes at `offset`, or `damaged` when they run past the end.
    private static func slice(_ bytes: [UInt8], _ offset: Int, _ count: Int) throws -> ArraySlice<UInt8> {
        guard offset >= 0, count >= 0, offset <= bytes.count, count <= bytes.count - offset else {
            throw CodecError.damaged("\(count) bytes at \(offset) past the end")
        }
        return bytes[offset..<(offset + count)]
    }

    private static func readLE16(_ bytes: [UInt8], _ offset: Int) throws -> UInt16 {
        try slice(bytes, offset, 2).reversed().reduce(0) { $0 << 8 | UInt16($1) }
    }

    private static func readLE32(_ bytes: [UInt8], _ offset: Int) throws -> UInt32 {
        try slice(bytes, offset, 4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to bytes: inout [UInt8]) {
        for index in 0..<(T.bitWidth / 8) { bytes.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }

    /// `ByteReader.crc32`, under the name `RawPixelCodec` and the container tests use.
    static func crc32<Bytes: Collection>(_ bytes: Bytes) -> UInt32 where Bytes.Element == UInt8 { ByteReader.crc32(bytes) }
}
