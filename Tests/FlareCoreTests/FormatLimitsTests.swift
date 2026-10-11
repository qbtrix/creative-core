// FormatLimitsTests.swift: decoder size limits. Oversize input throws
// `tooLarge` before parsing; documents exactly at the layer and point limits
// still decode; one over each limit throws. Symbols count like scenes.
import FlareCore
import Foundation
import Testing

@Suite struct FormatLimitsTests {
    static func isTooLarge(_ error: any Error) -> Bool {
        guard case FormatError.tooLarge = error else { return false }
        return true
    }

    static func document(layers: Int) -> Document {
        let all = (0..<layers).map { Layer(id: "l\($0)", name: "L") }
        return Document(scenes: [Scene(id: "s", name: "S", layers: all)])
    }

    /// One layer whose shapes hold `points` points: half as `Shape.points`,
    /// the rest as path elements (move 1, quad 2, cubic 3, close 0).
    static func document(points: Int) -> Document {
        let p = Point(x: 1, y: 2)
        let plain = Shape(points: Array(repeating: p, count: points / 2))
        var elements: [PathElement] = [.close]
        var remaining = points - points / 2
        while remaining >= 3 { elements.append(.cubic(control1: p, control2: p, to: p)); remaining -= 3 }
        if remaining == 2 { elements.append(.quad(control: p, to: p)) }
        if remaining == 1 { elements.append(.move(to: p)) }
        let curved = Shape(points: [], path: Path(elements: elements))
        let layer = Layer(id: "l", name: "L", shapes: [plain, curved])
        return Document(scenes: [Scene(id: "s", name: "S", layers: [layer])])
    }

    @Test func oversizeInputThrowsBeforeParsing() {
        // Not JSON at all: only the byte check can produce tooLarge here.
        let data = Data(count: FlareFormat.maxFileBytes + 1)
        let start = Date()
        #expect(performing: { try FlareFormat.decode(data) }, throws: Self.isTooLarge)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func inputAtByteLimitIsParsed() {
        // Exactly at the limit the byte check passes and parsing rejects the junk.
        let data = Data(count: FlareFormat.maxFileBytes)
        #expect(throws: FormatError.malformed("not a JSON object")) { try FlareFormat.decode(data) }
    }

    @Test func layersAtLimitDecode() throws {
        let doc = Self.document(layers: FlareFormat.maxLayersPerScene)
        let decoded = try FlareFormat.decode(try JSONEncoder().encode(Envelope(document: doc)))
        #expect(decoded == doc)
    }

    @Test func layersOverLimitThrow() throws {
        let doc = Self.document(layers: FlareFormat.maxLayersPerScene + 1)
        let data = try JSONEncoder().encode(Envelope(document: doc))
        #expect(performing: { try FlareFormat.decode(data) }, throws: Self.isTooLarge)
        #expect(performing: { try FlareFormat.encode(doc) }, throws: Self.isTooLarge)
    }

    @Test func pointsAtLimitDecode() throws {
        let doc = Self.document(points: FlareFormat.maxTotalPoints)
        let decoded = try FlareFormat.decode(try JSONEncoder().encode(Envelope(document: doc)))
        #expect(decoded == doc)
    }

    @Test(arguments: [0, 1, 2]) func pointsOverLimitThrow(extra: Int) {
        // Over by one to three, so the last path element is each kind. Checked
        // through validate, which decode runs (see layersOverLimitThrow), to
        // keep the test fast.
        let doc = Self.document(points: FlareFormat.maxTotalPoints + 1 + extra)
        #expect(performing: { try FlareFormat.validate(doc) }, throws: Self.isTooLarge)
    }

    @Test func pointsAreCountedAcrossScenes() {
        let half = Self.document(points: FlareFormat.maxTotalPoints / 2 + 1)
        var other = half.scenes[0]
        other.id = "t"
        let doc = Document(scenes: [half.scenes[0], other])
        #expect(performing: { try FlareFormat.validate(doc) }, throws: Self.isTooLarge)
    }

    @Test func symbolPointsCountTowardLimit() {
        // Over the limit only inside a symbol: the scene itself is empty.
        let big = Self.document(points: FlareFormat.maxTotalPoints + 1)
        let symbol = Symbol(id: "sym", name: "Sym", layers: big.scenes[0].layers)
        let doc = Document(scenes: [Scene(id: "s", name: "S")], symbols: [symbol])
        #expect(performing: { try FlareFormat.validate(doc) }, throws: Self.isTooLarge)
    }

    @Test func symbolLayersOverLimitThrow() {
        let layers = Self.document(layers: FlareFormat.maxLayersPerScene + 1).scenes[0].layers
        let doc = Document(symbols: [Symbol(id: "sym", name: "Sym", layers: layers)])
        #expect(throws: FormatError.tooLarge("symbol sym: \(layers.count) layers, limit \(FlareFormat.maxLayersPerScene)")) {
            try FlareFormat.validate(doc)
        }
    }
}

/// The file envelope, encoded compactly so big fixtures stay cheap.
private struct Envelope: Encodable {
    var format = "flare"
    var version = 1
    var document: Document
}
