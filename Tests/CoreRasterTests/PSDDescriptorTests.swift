// PSDDescriptorTests.swift: the PSD action descriptor reader (layer-style-engine
// LE-6). `Desc` writes descriptor bytes as the published spec lays them out, so
// tests build effect blocks without fixture files; the reader reads every value
// type back, stops at its nesting and count limits, and throws on random or
// truncated bytes instead of crashing.
@testable import CoreRaster
import Foundation
import Testing

/// A descriptor value as the spec stores it, for writing test blocks.
indirect enum Desc {
    case obj(String, [(String, Desc)]), doub(Double), untf(String, Double), long(Int), bool(Bool), enm(String, String), list([Desc])

    func write(_ w: inout BigEndian) {
        func id(_ s: String) { w.u32(s.utf8.count == 4 ? 0 : s.utf8.count); w.ascii(s) }
        switch self {
        case let .obj(cls, items):
            w.u32(1); w.u16(0); id(cls); w.u32(items.count)
            for (key, value) in items { id(key); w.ascii(value.type); value.write(&w) }
        case let .doub(v): w.u32(Int(v.bitPattern >> 32)); w.u32(Int(v.bitPattern & 0xFFFF_FFFF))
        case let .untf(unit, v): w.ascii(unit); Desc.doub(v).write(&w)
        case let .long(v): w.u32(v)
        case let .bool(v): w.out.append(v ? 1 : 0)
        case let .enm(type, value): id(type); id(value)
        case let .list(items): w.u32(items.count); for item in items { w.ascii(item.type); item.write(&w) }
        }
    }

    var type: String {
        switch self {
        case .obj: "Objc"
        case .doub: "doub"
        case .untf: "UntF"
        case .long: "long"
        case .bool: "bool"
        case .enm: "enum"
        case .list: "VlLs"
        }
    }

    var bytes: [UInt8] { var w = BigEndian(); write(&w); return w.out }

    static let sample = Desc.obj("null", [("masterFXSwitch", .bool(false)), ("Opct", .untf("#Prc", 75)), ("long", .long(-3)),
                                          ("Md  ", .enm("BlnM", "Mltp")), ("Clr ", .obj("RGBC", [("Rd  ", .doub(255))])),
                                          ("list", .list([.long(1), .doub(2.5)]))])
}

@Suite struct PSDDescriptorTests {
    private func read(_ bytes: [UInt8]) throws -> PSDDescriptor { var r = ByteReader(bytes); return try PSDDescriptor(&r) }

    @Test func readsEveryValueType() throws {
        let d = try read(Desc.sample.bytes)
        #expect(d.classID == "null" && d.items.map(\.key) == ["masterFXSwitch", "Opct", "long", "Md  ", "Clr ", "list"])
        #expect(d.bool("masterFXSwitch") == false && d.number("Opct") == 75 && d.number("long") == -3)
        #expect(d.enumValue("Md  ") == "Mltp" && d.object("Clr ")?.number("Rd  ") == 255 && d.list("list")?.count == 2)
    }

    @Test func nestingAndCountsStopAtTheirLimits() throws {
        var deep = Desc.obj("leaf", [])
        for _ in 0..<PSDDescriptor.maxDepth { deep = .obj("node", [("next", deep)]) }
        #expect(kind(psdDescriptorError(deep.bytes)) == "tooLarge")
        var w = BigEndian(); w.u32(0); w.u32(0); w.ascii("null"); w.u32(PSDDescriptor.maxItems + 1)
        #expect(kind(psdDescriptorError(w.out)) == "tooLarge")
        var shallow = Desc.obj("leaf", [])
        for _ in 0..<(PSDDescriptor.maxDepth - 1) { shallow = .obj("node", [("next", shallow)]) }
        #expect(try read(shallow.bytes).classID == "node")
    }

    @Test func randomAndTruncatedBytesThrow() {
        var rng = SplitMix64(seed: 0xDE5C)
        let valid = Desc.sample.bytes
        for round in 0..<500 {
            var bytes = Array(valid.prefix(Int.random(in: 0..<valid.count, using: &rng)))
            if round % 2 == 0 {
                bytes = (0..<Int.random(in: 0..<256, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
                if round % 4 == 0 { bytes = Array(valid.prefix(30)) + bytes }
            }
            #expect(psdDescriptorError(bytes) != nil, "round \(round) read random bytes")
        }
    }
}

func psdDescriptorError(_ bytes: [UInt8]) -> CodecError? {
    var r = ByteReader(bytes)
    do { _ = try PSDDescriptor(&r); return nil } catch { return error as? CodecError }
}
