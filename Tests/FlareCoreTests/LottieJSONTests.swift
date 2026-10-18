// LottieJSONTests.swift: LottieJSON.parse, the importer's iterative JSON reader, checked against
// Foundation's JSONDecoder (the reader it replaced, kept here as the reference) on edge cases and
// seeded mutations of the import fixtures: both accept the same bytes and read the same values.
import Foundation
import Testing
@testable import FlareCore

struct LottieJSONTests {
    /// The importer's previous reader: Foundation's decoder, trying each JSON type in turn.
    struct Reference: Decodable {
        var value: LottieJSON
        init(from decoder: any Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { value = .null } else if let v = try? c.decode(Double.self) { value = .number(v) }
            else if let v = try? c.decode(String.self) { value = .string(v) }
            else if let v = try? c.decode([String: Reference].self) { value = .object(v.mapValues(\.value)) }
            else if let v = try? c.decode([Reference].self) { value = .array(v.map(\.value)) } else { value = .bool(try c.decode(Bool.self)) }
        }
    }
    func same(_ bytes: [UInt8]) -> Bool {
        let data = Data(bytes)
        return (try? JSONDecoder().decode(Reference.self, from: data).value) == (try? LottieJSON.parse(data))
    }

    @Test func edgeCasesMatchFoundation() {
        let cases = [#"{"a":[1,-0.5,2e3,1E-2,true,false,null,"x"],"b":{}}"#, #"{"a":[]}"#, #" { "a" : [ ] } "#,
                     #"{"s":"\u00e9\uD83D\uDE00\n\t\"\\\/"}"#, #"{"s":"\uD800"}"#, #"{"s":"\uDC00"}"#, #"{"s":"\uD800\u0041"}"#,
                     #"{"s":"\u+0ab"}"#, "{\"s\":\"a\u{01}\"}", #"{"a":1,}"#, #"{"a":[1,]}"#, #"{"a":01}"#, #"{"a":1.}"#,
                     #"{"a":.5}"#, #"{"a":+1}"#, #"{"a":1e400}"#, #"{"a":-}"#, #"{"a":NaN}"#, #"{"a":tru}"#, #"{"a":1} x"#,
                     #"{"a":1}}"#, #"{"a" 1}"#, #"{a:1}"#, #"{"a":1"b":2}"#, #"{"#, "", #"{"a":[[[]]]}"#,
                     #"{"a":[,]}"#, #"{,}"#, #"{"a":[1,,2]}"#, #"{"a":1,,}"#, #"{"a":"x","a":"y"}"#,
                     #"{"a":[1}}"#, #"{"a":1]"#, #"{"s":"\uD800\uE000"}"#]
        for json in cases { #expect(same(Array(json.utf8)), "\(json)") }
        #expect(same(Array(#"{"s":""#.utf8) + [0xC3, 0x28] + Array(#""}"#.utf8)))  // invalid UTF-8
    }

    @Test func mutationsMatchFoundation() throws {
        var rng = SplitMix64(seed: 0x4C4A_534E)
        let seeds = try ["shapes.json", "animated.json"].map { Array(try ImportFixture.data($0)) }
        for i in 0..<500 {
            let bytes = ImportFuzz.mutate(seeds[i % seeds.count], &rng)
            #expect(same(bytes), "case \(i): \(String(decoding: bytes, as: UTF8.self))")
        }
    }

    /// `==` compares every item and member: a shorter array, a renamed key or a changed leaf differs.
    @Test func equalityComparesEveryLevel() {
        let value = LottieJSON.object(["a": .array([.number(1), .string("x")]), "b": .object(["c": .null])])
        #expect(value == .object(["b": .object(["c": .null]), "a": .array([.number(1), .string("x")])]))
        #expect(value != .object(["a": .array([.number(1)]), "b": .object(["c": .null])]))
        #expect(value != .object(["a": .array([.number(1), .string("x")]), "d": .object(["c": .null])]))
        #expect(value != .object(["a": .array([.number(1), .string("y")]), "b": .object(["c": .null])]))
        #expect(LottieJSON.array([.number(1)]) != .array([.number(1), .number(1)]) && LottieJSON.bool(true) != .number(1))
    }

    /// Two values at the nesting cap compare on a 64 KB thread stack, which a recursive `==` overflows.
    @Test func deepValuesCompareOnASmallStack() {
        func nest(_ leaf: LottieJSON) -> LottieJSON { (0..<(LottieImport.maxDepth + 6)).reduce(leaf) { v, _ in .array([.object(["k": v])]) } }
        // Shared through `done`. The values are dropped here, not on the small thread, whose
        // recursive deinit of a deep value would overflow it.
        final class Box: @unchecked Sendable { var values: [LottieJSON] = [], same = false, differ = false }
        let box = Box(), done = DispatchSemaphore(value: 0)
        box.values = [nest(.number(1)), nest(.number(1)), nest(.number(2))]
        let thread = Thread {
            if box.values.count == 3 { (box.same, box.differ) = (box.values[0] == box.values[1], box.values[0] != box.values[2]) }
            done.signal()
        }
        thread.stackSize = 64 << 10
        thread.start()
        done.wait()
        box.values = []
        #expect(box.same && box.differ)
    }
}
