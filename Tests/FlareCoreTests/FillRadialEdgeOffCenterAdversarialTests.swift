// FillRadialEdgeOffCenterAdversarialTests.swift: tries to get a radial fill
// whose edge rounds back onto center.x (#235) past validation by other routes
// than a plain load: commands (add, set fill, a drag that coalesces), text
// fills, symbol layers exported through an instance, a save and reload, and a
// seeded fuzz over the whole Double range including NaN, infinities, signed
// zero and subnormals. Each route rejects the collapsed edge or exports e != s.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import FlareCore

@Suite struct FillRadialEdgeOffCenterAdversarialTests {
    static let message = "radial gradient radius too small to move its edge off center.x"
    static let stops = FillRadialExtentAdversarialTests.stops

    static func radial(_ x: Double, _ r: Double) -> Fill {
        FillRadialExtentAdversarialTests.radial(x, 0, r)
    }

    static func layerDoc(_ layer: Layer = Layer(id: "l", name: "L")) -> Document {
        Document(scenes: [Scene(id: "s", name: "S", layers: [layer])])
    }

    /// Every Lottie gradient fill in the export, at any group depth. JSONDecoder
    /// because it parses doubles exactly.
    struct Item: Decodable {
        struct Value: Decodable {
            let k: [Double]?
            init(from decoder: any Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                k = try? c.decode([Double].self, forKey: .k)
            }
            enum CodingKeys: String, CodingKey { case k }
        }
        let ty: String
        let s: Value?
        let e: Value?
        let it: [Item]?
        var gradients: [Item] { (ty == "gf" ? [self] : []) + (it ?? []).flatMap(\.gradients) }
    }
    struct Lottie: Decodable {
        struct Layer: Decodable { let shapes: [Item] }
        let layers: [Layer]
    }

    static func gradients(_ d: Document) throws -> [(s: [Double], e: [Double])] {
        let lottie = try JSONDecoder().decode(Lottie.self, from: LottieExporter.export(scene: d.scenes[0], symbols: d.symbols))
        return try lottie.layers.flatMap(\.shapes).flatMap(\.gradients).map {
            (try #require($0.s?.k), try #require($0.e?.k))
        }
    }

    /// AddShape and SetShapeFill both refuse the issue's collapsed fill, and
    /// leave the document and undo stack as they were.
    @Test func commandsRejectACollapsedEdge() throws {
        let start = Self.layerDoc(Layer(id: "l", name: "L", shapes: [Shape(points: [Point(x: 0, y: 0)])]))
        var e = CommandEngine(document: start)
        let shape = Shape(points: [Point(x: 0, y: 0)], fill: Self.radial(1e17, 1))
        #expect(throws: (any Error).self) { try e.perform(AddShape(owner: .scene("s"), layerID: "l", shape: shape)) }
        #expect(throws: (any Error).self) {
            try e.perform(SetShapeFill(owner: .scene("s"), layerID: "l", index: 0, fill: Self.radial(-1e17, 4)))
        }
        #expect(e.document == start)
        #expect(!e.canUndo)
    }

    /// A drag of a valid gradient to where its radius no longer moves the edge
    /// is rejected at the step that collapses it; the coalesced drag before it
    /// stays, still validates and still exports e != s.
    @Test func dragThatCollapsesTheEdgeIsRejected() throws {
        let start = Self.layerDoc(Layer(id: "l", name: "L", shapes: [Shape(points: [Point(x: 0, y: 0)], fill: Self.radial(0, 8))]))
        var e = CommandEngine(document: start)
        let move = { (dx: Double) in TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: dx, dy: 0) }
        try e.perform(move(1e16), coalesceKey: "drag")        // ulp(1e16) = 2: radius 8 still moves it
        #expect(throws: CommandError.self) { try e.perform(move(9e16), coalesceKey: "drag") } // ulp(1e17) = 16
        try FlareFormat.validate(e.document)
        for g in try Self.gradients(e.document) { #expect(g.e != g.s) }
        try e.undo()
        #expect(e.document == start)
    }

    /// Text fills share the check: a collapsed radial on text is rejected too.
    @Test func textFillWithACollapsedEdgeIsRejected() {
        let text = TextShape(string: "a", fontFamily: "F", fontSize: 12, position: Point(x: 0, y: 0), fill: Self.radial(1e17, 1))
        #expect(throws: FormatError.invalid(Self.message)) {
            try FlareFormat.validate(Self.layerDoc(Layer(id: "l", name: "L", texts: [text])))
        }
        var e = CommandEngine(document: Self.layerDoc())
        #expect(throws: (any Error).self) { try e.perform(AddTextShape(owner: .scene("s"), layerID: "l", text: text)) }
        #expect(!e.canUndo)
    }

    /// A symbol layer is checked as well, and a valid symbol gradient drawn
    /// through an instance keeps e != s in the nested Lottie groups.
    @Test func symbolGradientIsCheckedAndExportsANonZeroLength() throws {
        func doc(_ fill: Fill) -> Document {
            let symbol = Symbol(id: "sym", name: "Sym", layers: [Layer(id: "sl", name: "SL", shapes: [Shape(points: [Point(x: 0, y: 0)], fill: fill)])])
            var d = Self.layerDoc(Layer(id: "l", name: "L", instances: [Instance(symbolID: "sym")]))
            d.symbols = [symbol]
            return d
        }
        #expect(throws: FormatError.invalid(Self.message)) { try FlareFormat.validate(doc(Self.radial(1e17, 1))) }
        let ok = doc(Self.radial(1e17, 16))
        try FlareFormat.validate(ok)
        let found = try Self.gradients(ok)
        #expect(found.count == 1)
        for g in found { #expect(g.e == [1e17 + 16, 0] && g.e != g.s) }
    }

    /// Fills at the boundary survive a save and reload bit for bit, so a file
    /// that validated on save validates on load; a collapsed one fails to load
    /// with a typed error.
    @Test(arguments: [(1e17, 16.0), (-1e17, 16), (1, 0x1p-52), (-1, 0x1p-52), (0x1p-1022, 0x1p-1074),
                      (-0.0, .leastNonzeroMagnitude), (Double.greatestFiniteMagnitude.nextDown, Double.greatestFiniteMagnitude.ulp)])
    func boundaryFillsRoundTripExactly(x: Double, r: Double) throws {
        let d = FillRadialEdgeOffCenterTests.doc(x, r)
        let back = try FlareFormat.decode(FlareFormat.encode(d))
        #expect(back.scenes.first?.layers.first?.shapes.first?.fill == Self.radial(x, r))
        for g in try Self.gradients(back) { #expect(g.e != g.s) }
    }

    @Test func collapsedFillFailsToLoad() throws {
        var json = String(decoding: try FlareFormat.encode(FillRadialEdgeOffCenterTests.doc(1e17, 16)), as: UTF8.self)
        #expect(json.contains("\"radius\" : 16"))
        json = json.replacingOccurrences(of: "\"radius\" : 16", with: "\"radius\" : 1")
        #expect(throws: FormatError.self) { try FlareFormat.decode(Data(json.utf8)) }
    }

    /// Seeded fuzz over the whole Double range, special values included:
    /// validation accepts exactly when the radius is finite and > 0 and both
    /// edges are finite and differ from center.x, and nothing it accepts
    /// exports a zero-length Lottie gradient.
    @Test(arguments: [UInt64(7), 2350])
    func fuzzAcceptsExactlyTheMovingEdges(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let specials: [Double] = [0, -0.0, .nan, .infinity, -.infinity, .leastNonzeroMagnitude, .leastNormalMagnitude,
                                  .greatestFiniteMagnitude, -.greatestFiniteMagnitude, 1, -1, 1e17, -1e17]
        func value() -> Double {
            if Int.random(in: 0..<5, using: &rng) == 0 { return specials[Int.random(in: 0..<specials.count, using: &rng)] }
            let bits = rng.next()
            return Double(bitPattern: bits)
        }
        var (accepted, rejected) = (0, 0)
        for _ in 0..<600 {
            let x = value()
            let r: Double = Bool.random(using: &rng) ? value()
                : x.ulp * [0.25, 0.5, 0.75, 1, 2][Int.random(in: 0...4, using: &rng)]
            let d = FillRadialEdgeOffCenterTests.doc(x, r)
            let ok = x.isFinite && r.isFinite && r > 0 && (x - r).isFinite && (x + r).isFinite && x - r < x && x + r > x
            guard ok else {
                rejected += 1
                #expect(throws: FormatError.self, "\(x) \(r)") { try FlareFormat.validate(d) }
                continue
            }
            accepted += 1
            try FlareFormat.validate(d)
            for g in try Self.gradients(d) { #expect(g.e != g.s, "\(x) \(r)") }
        }
        #expect(accepted > 50)
        #expect(rejected > 50)
    }
}
