// SymbolCycleTests.swift: validate rejects symbols that contain themselves,
// directly or through other symbols, accepts shared (diamond) nesting, and
// walks deep chains without recursion.
import FlareCore
import Foundation
import Testing

@Suite struct SymbolCycleTests {
    /// A symbol whose single layer places one instance of each id in `uses`.
    static func symbol(_ id: String, uses: [String] = []) -> Symbol {
        let layer = Layer(id: "l", name: "L", instances: uses.map { Instance(symbolID: $0) })
        return Symbol(id: id, name: id, layers: [layer])
    }

    static func document(_ symbols: [Symbol]) -> Document {
        var doc = Fixtures.document()
        doc.symbols = symbols
        return doc
    }

    static func isCycleError(_ error: any Error) -> Bool {
        guard case FormatError.invalid(let message) = error else { return false }
        return message.hasPrefix("symbol cycle")
    }

    @Test func selfContainmentThrows() {
        let doc = Self.document([Self.symbol("A", uses: ["A"])])
        #expect(throws: FormatError.invalid("symbol cycle A -> A")) { try FlareFormat.validate(doc) }
    }

    @Test func indirectCycleThrows() {
        let doc = Self.document([Self.symbol("A", uses: ["B"]), Self.symbol("B", uses: ["A"])])
        #expect(throws: FormatError.invalid("symbol cycle A -> B -> A")) { try FlareFormat.validate(doc) }
    }

    @Test func cycleNotReachableFromFirstSymbolThrows() {
        let doc = Self.document([
            Self.symbol("root", uses: ["leaf"]), Self.symbol("leaf"),
            Self.symbol("X", uses: ["Y"]), Self.symbol("Y", uses: ["Z"]), Self.symbol("Z", uses: ["Y"]),
        ])
        #expect(throws: FormatError.invalid("symbol cycle Y -> Z -> Y")) { try FlareFormat.validate(doc) }
    }

    @Test func diamondPasses() throws {
        let doc = Self.document([
            Self.symbol("A", uses: ["B", "C"]), Self.symbol("B", uses: ["D"]),
            Self.symbol("C", uses: ["D"]), Self.symbol("D"),
        ])
        try FlareFormat.validate(doc)
        #expect(try FlareFormat.decode(FlareFormat.encode(doc)) == doc)
    }

    @Test func cyclicFileFailsToDecode() throws {
        let valid = Self.document([Self.symbol("A", uses: ["B"]), Self.symbol("B")])
        let json = try #require(String(data: FlareFormat.encode(valid), encoding: .utf8))
        // B now places an instance of A, closing the loop.
        let data = try JSONSerialization.data(withJSONObject: Self.injectInstance(json, into: 1, of: "A"))
        #expect { try FlareFormat.decode(data) } throws: { Self.isCycleError($0) }
    }

    /// Adds an instance of `symbolID` to the first layer of `symbols[index]` in raw JSON.
    static func injectInstance(_ json: String, into index: Int, of symbolID: String) throws -> Any {
        var root = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        var document = try #require(root["document"] as? [String: Any])
        var symbols = try #require(document["symbols"] as? [[String: Any]])
        var layers = try #require(symbols[index]["layers"] as? [[String: Any]])
        let instance = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Instance(symbolID: symbolID)))
        layers[0]["instances"] = [instance]
        symbols[index]["layers"] = layers
        document["symbols"] = symbols
        root["document"] = document
        return root
    }

    @Test func deepChainDoesNotOverflow() throws {
        let n = 10_000
        var symbols = (0..<n).map { Self.symbol("s\($0)", uses: $0 + 1 < n ? ["s\($0 + 1)"] : []) }
        try FlareFormat.validate(Self.document(symbols))
        symbols[n - 1] = Self.symbol("s\(n - 1)", uses: ["s0"])
        #expect { try FlareFormat.validate(Self.document(symbols)) } throws: { Self.isCycleError($0) }
    }

    @Test func randomAcyclicGraphsPassAndBackEdgesThrow() throws {
        var rng = SplitMix64(seed: 17)
        for _ in 0..<50 {
            let count = Int(rng.next() % 12) + 2
            // Edges only go from lower to higher index, so the graph is acyclic.
            var symbols = (0..<count).map { i in
                Self.symbol("s\(i)", uses: ((i + 1)..<count).filter { _ in rng.next() % 3 == 0 }.map { "s\($0)" })
            }
            try FlareFormat.validate(Self.document(symbols))
            let low = Int(rng.next() % UInt64(count - 1))
            let high = low + 1 + Int(rng.next() % UInt64(count - low - 1))
            // A path low -> high plus high -> low is always a cycle.
            symbols[low].layers[0].instances.append(Instance(symbolID: "s\(high)"))
            symbols[high].layers[0].instances.append(Instance(symbolID: "s\(low)"))
            #expect { try FlareFormat.validate(Self.document(symbols)) } throws: { Self.isCycleError($0) }
        }
    }
}
