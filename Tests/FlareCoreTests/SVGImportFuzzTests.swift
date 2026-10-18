import Foundation
import Testing
@testable import FlareCore

/// Seeded byte mutations shared by the import fuzz suites.
enum ImportFuzz {
    static let tokens = ["<", ">", "/", "\"", "&", "&#99999999;", "{", "}", "[", "]", ",", ":", "-", "1e308", "NaN",
                         "99999999999999999999", "<g>", "A"].map { Array($0.utf8) }

    /// `bytes` with one to four seeded edits: a byte replaced, a run deleted, a run doubled or a token inserted.
    static func mutate(_ bytes: [UInt8], _ rng: inout SplitMix64) -> [UInt8] {
        var out = bytes
        for _ in 0..<Int.random(in: 1...4, using: &rng) where !out.isEmpty {
            let at = Int.random(in: 0..<out.count, using: &rng), run = min(Int.random(in: 1...16, using: &rng), out.count - at)
            switch Int.random(in: 0..<4, using: &rng) {
            case 0: out[at] = UInt8.random(in: 0...255, using: &rng)
            case 1: out.removeSubrange(at..<at + run)
            case 2: out.insert(contentsOf: out[at..<at + run], at: at)
            default: out.insert(contentsOf: tokens[Int.random(in: 0..<tokens.count, using: &rng)], at: at)
            }
        }
        return out
    }

    /// `body` on `cases` mutations of `seeds`: each imports or throws an `ImportError`, in under 1 s.
    static func run(seeds: [Data], cases: Int, seed: UInt64, _ body: (Data) throws -> Void) {
        var rng = SplitMix64(seed: seed)
        for i in 0..<cases {
            let data = Data(mutate(Array(seeds[i % seeds.count]), &rng))
            let took = ContinuousClock().measure {
                do { try body(data) } catch is ImportError {} catch { Issue.record("case \(i): \(error)") }
            }
            #expect(took < .seconds(1), "case \(i) took \(took)")
        }
    }
}

/// The SVG reader never crashes on damaged input and keeps to its caps (VI-5).
struct SVGImportFuzzTests {
    static let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\">"
    func kind(_ body: String) -> String? { ImportFixture.kind { _ = try SVGImport.scene(from: Data((Self.svg + body + "</svg>").utf8), name: "s") } }

    @Test(.disabled("waits on VI-5")) func mutationsThrowOrImport() throws {
        let seeds = try ["shapes.svg", "groups.svg", "paint.svg", "skipped.svg"].map(ImportFixture.data)
        ImportFuzz.run(seeds: seeds, cases: 1_000, seed: 0x5649_5F35) { data in
            let (scene, _) = try SVGImport.scene(from: data, name: "fuzz")
            #expect(throws: Never.self) { try FlareFormat.validate(Document(scenes: [scene])) }
        }
    }

    @Test(.disabled("waits on VI-5")) func capsOnBytesElementsAndNesting() {
        #expect(kind(String(repeating: " ", count: SVGImport.maxBytes)) == "tooLarge")
        #expect(kind(String(repeating: "<g/>", count: SVGImport.maxElements + 1)) == "tooLarge")
        #expect(kind(String(repeating: "<g>", count: 200) + String(repeating: "</g>", count: 200)) == nil)
        #expect(kind(String(repeating: "<g>", count: 300) + String(repeating: "</g>", count: 300)) == "tooLarge")
    }
}
