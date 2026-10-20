// PSDDescriptor.swift: the action descriptor structure of the published PSD
// file format specification ("Descriptor structure"), as the object-based
// effects block (`lfx2`) stores it: a class, then keyed items of a typed value
// (`Objc`, `GlbO`, `VlLs`, `doub`, `UntF`, `long`, `comp`, `bool`, `enum`,
// `TEXT`, `type`, `GlbC`, `tdta`, `alis`). A reference (`obj `) or any other
// type throws `unsupported`.
// Invariants: every read goes through `ByteReader`, so truncated bytes throw
// `damaged`; item and list counts stop at `maxItems`, nesting at `maxDepth`,
// and a string's length is checked against the bytes left before it is read.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One descriptor value. Raw data and aliases are skipped as `.other`.
indirect enum PSDValue: Sendable {
    case integer(Int), double(Double), unitFloat(unit: String, value: Double), bool(Bool)
    case enumerated(type: String, value: String), text(String), object(PSDDescriptor), list([PSDValue]), other
}

/// A descriptor: its class id and its items in file order.
struct PSDDescriptor: Sendable {
    /// The most items one descriptor or list may declare.
    static let maxItems = 4_096
    /// The deepest descriptors and lists may nest.
    static let maxDepth = 32

    var classID: String
    var items: [(key: String, value: PSDValue)]

    init(_ r: inout ByteReader, depth: Int = 0) throws {
        guard depth < Self.maxDepth else { throw CodecError.tooLarge("descriptors nested over \(Self.maxDepth) deep") }
        _ = try Self.text(&r) // the class's display name
        classID = try Self.id(&r)
        items = try (0..<Self.count(&r)).map { _ in
            let key = try Self.id(&r)
            return (key, try Self.value(&r, type: String(decoding: try r.bytes(4), as: UTF8.self), depth: depth))
        }
    }

    /// The first item under `key`.
    subscript(key: String) -> PSDValue? { items.first { $0.key == key }?.value }

    func number(_ key: String) -> Double? {
        switch self[key] {
        case let .double(v)?, let .unitFloat(_, v)?: return v.isFinite ? v : nil
        case let .integer(v)?: return Double(v)
        default: return nil
        }
    }

    func bool(_ key: String) -> Bool? { if case let .bool(v)? = self[key] { v } else { nil } }
    func enumValue(_ key: String) -> String? { if case let .enumerated(_, v)? = self[key] { v } else { nil } }
    func object(_ key: String) -> PSDDescriptor? { if case let .object(v)? = self[key] { v } else { nil } }
    func list(_ key: String) -> [PSDValue]? { if case let .list(v)? = self[key] { v } else { nil } }

    private static func value(_ r: inout ByteReader, type: String, depth: Int) throws -> PSDValue {
        switch type {
        case "Objc", "GlbO": return .object(try PSDDescriptor(&r, depth: depth + 1))
        case "VlLs":
            guard depth + 1 < maxDepth else { throw CodecError.tooLarge("lists nested over \(maxDepth) deep") }
            return .list(try (0..<count(&r)).map { _ in
                try value(&r, type: String(decoding: try r.bytes(4), as: UTF8.self), depth: depth + 1)
            })
        case "doub": return .double(try double(&r))
        case "UntF": return .unitFloat(unit: String(decoding: try r.bytes(4), as: UTF8.self), value: try double(&r))
        case "long": return .integer(Int(try r.i32()))
        case "comp": try r.skip(8); return .other
        case "bool": return .bool(try r.u8() != 0)
        case "enum": return .enumerated(type: try id(&r), value: try id(&r))
        case "TEXT": return .text(try text(&r))
        case "type", "GlbC": _ = try text(&r); _ = try id(&r); return .other
        case "tdta", "alis": try r.skip(try r.length32()); return .other
        default: throw CodecError.unsupported("descriptor value \(type)")
        }
    }

    /// A count, checked against `maxItems`.
    private static func count(_ r: inout ByteReader) throws -> Int {
        let count = try r.length32()
        guard count <= maxItems else { throw CodecError.tooLarge("\(count) descriptor items") }
        return count
    }

    /// A key or class id: a length, then that many bytes, or four bytes when the length is 0.
    private static func id(_ r: inout ByteReader) throws -> String {
        let length = try r.length32()
        return String(decoding: try r.bytes(length == 0 ? 4 : length), as: UTF8.self)
    }

    /// A Unicode string: a count of UTF-16 units, then the units; a trailing NUL is dropped.
    private static func text(_ r: inout ByteReader) throws -> String {
        let units = try r.length32()
        guard try ByteReader.multiplying(units, 2) <= r.remaining else { throw CodecError.damaged("a descriptor string passes its block") }
        let string = String(decoding: try (0..<units).map { _ in try r.u16() }, as: UTF16.self)
        return string.hasSuffix("\0") ? String(string.dropLast()) : string
    }

    private static func double(_ r: inout ByteReader) throws -> Double {
        Double(bitPattern: UInt64(try r.u32()) << 32 | UInt64(try r.u32()))
    }
}
