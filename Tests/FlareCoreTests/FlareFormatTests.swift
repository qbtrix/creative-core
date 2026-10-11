// FlareFormatTests.swift: file format v1. Byte-stable round trip, forward
// compatibility (unknown fields ignored), and malformed input that must throw,
// including a seeded mutation fuzz.
import FlareCore
import Foundation
import Testing

@Suite struct FlareFormatTests {
    @Test func roundTripIsByteStable() throws {
        let first = try FlareFormat.encode(Fixtures.document())
        let decoded = try FlareFormat.decode(first)
        #expect(decoded == Fixtures.document())
        let second = try FlareFormat.encode(decoded)
        #expect(first == second)
    }

    @Test func headerIsPresent() throws {
        let text = String(decoding: try FlareFormat.encode(Document()), as: UTF8.self)
        #expect(text.contains(#""format" : "flare""#))
        #expect(text.contains(#""version" : 1"#))
    }

    @Test func unknownFieldsAreIgnored() throws {
        let json = #"""
        {"format":"flare","version":1,"futureTopLevel":{"a":[1,2]},
         "document":{"scenes":[{"id":"s","name":"S","fps":30,"durationFrames":10,"camera":"new",
           "layers":[{"id":"l","name":"L","shapes":[],"blendMode":"add",
             "tracks":{"x":[{"frame":0,"value":1,"easing":{"linear":{}},"spring":true}]}}]}]}}
        """#
        let doc = try FlareFormat.decode(Data(json.utf8))
        #expect(doc.scenes[0].layers[0].tracks["x"]?.first?.value == 1)
    }

    @Test(arguments: [
        ("", "empty"),
        ("null", "null"),
        ("[]", "array"),
        ("{", "truncated"),
        (#"{"format":"flare"}"#, "no version"),
        (#"{"format":"flare","version":"1","document":{"scenes":[]}}"#, "string version"),
        (#"{"format":"flare","version":1}"#, "no document"),
        (#"{"format":"flare","version":1,"document":{"scenes":[{"id":"s"}]}}"#, "partial scene"),
        (#"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":0,"durationFrames":1,"layers":[]}]}}"#, "fps 0"),
        (#"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,"layers":[{"id":"l","name":"L","shapes":[],"tracks":{"x":[{"frame":5,"value":0,"easing":{"linear":{}}},{"frame":2,"value":0,"easing":{"linear":{}}}]}}]}]}}"#, "unsorted track"),
        (#"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,"layers":[{"id":"l","name":"L","shapes":[],"tracks":{}},{"id":"l","name":"L2","shapes":[],"tracks":{}}]}]}}"#, "duplicate layer id"),
        (#"{"format":"flare","version":1,"document":{"scenes":[{"id":"s","name":"S","fps":24,"durationFrames":1,"layers":[{"id":"l","name":"L","shapes":[],"tracks":{"x":[{"frame":99999999999999999999999,"value":0,"easing":{"linear":{}}}]}}]}]}}"#, "frame overflow"),
    ])
    func malformedInputThrows(_ json: String, _ why: String) {
        #expect(throws: FormatError.self, "\(why)") { try FlareFormat.decode(Data(json.utf8)) }
    }

    @Test func wrongFormatAndFutureVersion() {
        #expect(throws: FormatError.notAFlareFile) {
            try FlareFormat.decode(Data(#"{"format":"svg","version":1,"document":{"scenes":[]}}"#.utf8))
        }
        #expect(throws: FormatError.unsupportedVersion(2)) {
            try FlareFormat.decode(Data(#"{"format":"flare","version":2,"document":{"scenes":[]}}"#.utf8))
        }
    }

    @Test func nonFiniteValuesThrowOnEncode() {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].tracks["x"]?[0].value = .nan
        #expect(throws: FormatError.self) { try FlareFormat.encode(doc) }
    }

    @Test func validateRejectsNonFiniteKeyframeValues() {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].tracks["x"]?[1].value = .infinity
        #expect(throws: FormatError.invalid("layer ball: track x has a non-finite value at frame 24")) {
            try FlareFormat.validate(doc)
        }
    }

    @Test func everyTruncationThrowsOrDecodes() throws {
        let bytes = Array(try FlareFormat.encode(Fixtures.document()))
        for n in 0..<bytes.count {
            #expect(throws: FormatError.self) { try FlareFormat.decode(Data(bytes[0..<n])) }
        }
    }

    @Test func mutationFuzzNeverCrashes() throws {
        let valid = Array(try FlareFormat.encode(Fixtures.document()))
        var rng = SplitMix64(seed: 7)
        let alphabet = Array(#"{}[]",:0123456789-.eE truefalsn\"#.utf8)
        for _ in 0..<3000 {
            var bytes = valid
            for _ in 0..<Int.random(in: 1...6, using: &rng) {
                let i = Int.random(in: 0..<bytes.count, using: &rng)
                switch Int.random(in: 0..<3, using: &rng) {
                case 0: bytes[i] = alphabet.randomElement(using: &rng) ?? 0
                case 1: bytes.remove(at: i)
                default: bytes.insert(alphabet.randomElement(using: &rng) ?? 0, at: i)
                }
                if bytes.isEmpty { bytes = [0x7B] }
            }
            do {
                _ = try FlareFormat.decode(Data(bytes))
            } catch is FormatError {
                // expected
            } catch {
                Issue.record("non-FormatError thrown: \(error)")
            }
        }
    }
}
