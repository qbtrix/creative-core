// FillRadialEdgeRoundingTests.swift: the radial edge check (#200, kept by #233)
// at the rounding boundary. center.x ± radius is a rounded sum, so the limit
// sits half an ulp past the largest Double, not at it. An edge must also
// differ from center.x (#235), so a center at ±max never validates. The check,
// the Lottie edge and the load path must agree there; dragging a gradient near
// the limit is accepted exactly when its moved edges stay finite.
@testable import FlareCore
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct FillRadialEdgeRoundingTests {
    static let max = Double.greatestFiniteMagnitude
    static let halfUlp = max.ulp / 2
    static let edgeMessage = "radial gradient center ± radius must be finite"

    static func radial(_ x: Double, _ r: Double) -> Fill { FillRadialExtentAdversarialTests.radial(x, 0, r) }

    static func edgesFinite(_ x: Double, _ r: Double) -> Bool { (x + r).isFinite && (x - r).isFinite }

    /// The message validation gives for this center and radius, or nil if it passes.
    static func edgeError(_ x: Double, _ r: Double) -> String? {
        guard edgesFinite(x, r) else { return edgeMessage }
        return x - r < x && x + r > x ? nil : FillRadialEdgeOffCenterTests.message
    }

    /// From the step below max, max + half an ulp ties to even and overflows;
    /// anything below rounds back to max.
    @Test(arguments: [max.nextDown, -max.nextDown])
    func halfAnUlpPastTheLimitIsTheCutoff(x: Double) throws {
        let below = FillRadialExtentAdversarialTests.doc(Self.radial(x, (Self.max.ulp + Self.halfUlp).nextDown))
        try FlareFormat.validate(below)
        _ = try LottieExporter.export(scene: below.scenes[0])
        _ = try SVGExporter.export(scene: below.scenes[0], frame: 0)
        #expect(throws: ModelError.invalidFill(Self.edgeMessage)) {
            try Self.radial(x, Self.max.ulp + Self.halfUlp).validate()
        }
    }

    /// Seeded fuzz a few ulps either side of the limit: the check accepts
    /// exactly when both edges are finite and off the center, and every
    /// accepted fill round-trips and exports.
    @Test(arguments: [UInt64(1), 200, 233])
    func checkMatchesTheEdgeSumNearTheLimit(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var (accepted, rejected) = (0, 0)
        for _ in 0..<500 {
            var x = Self.max
            for _ in 0..<Int.random(in: 0...4, using: &rng) { x = x.nextDown }
            if Bool.random(using: &rng) { x = -x }
            let scale = [1, 0.5, 2, 1e-292, 1e-300, 1e-308][Int.random(in: 0...5, using: &rng)]
            var r = Self.halfUlp * scale
            let up = Bool.random(using: &rng)
            for _ in 0..<Int.random(in: 0...3, using: &rng) { r = up ? r.nextUp : r.nextDown }
            let d = FillRadialExtentAdversarialTests.doc(Self.radial(x, r))
            if let message = Self.edgeError(x, r) {
                rejected += 1
                #expect(throws: FormatError.invalid(message), "\(x) \(r)") { try FlareFormat.validate(d) }
                continue
            }
            accepted += 1
            try FlareFormat.validate(d)
            #expect(try FlareFormat.decode(FlareFormat.encode(d)) == d)
            _ = try LottieExporter.export(scene: d.scenes[0])
            _ = try SVGExporter.export(scene: d.scenes[0], frame: 0)
        }
        #expect(accepted > 50)
        #expect(rejected > 10)
    }

    /// A file whose radial edge overflows only on the minus side, in a shape or
    /// in a text, fails to load with the typed edge error; the same file one
    /// step inside the limit loads.
    @Test func loadPathRejectsOverflowOnEitherSideInShapesAndTexts() throws {
        var doc = ShapeTextOwnerTests.start()
        let marked = Fill.radial(stops: FillRadialExtentAdversarialTests.stops,
                                 center: Point(x: 12345.5, y: 0), radius: 54321.5)
        doc.scenes[0].layers[1].shapes[0].fill = marked
        doc.symbols[0].layers[0].texts[0].fill = marked
        let text = String(decoding: try FlareFormat.encode(doc), as: UTF8.self)
        #expect(text.components(separatedBy: "12345.5").count == 3)
        func load(_ x: String, _ r: String) throws -> Document {
            try FlareFormat.decode(Data(text.replacingOccurrences(of: "12345.5", with: x)
                .replacingOccurrences(of: "54321.5", with: r).utf8))
        }
        for x in ["-1.7976931348623157e308", "1.7976931348623157e308"] {
            #expect(throws: FormatError.invalid(Self.edgeMessage), "\(x)") {
                try load(x, "1.7976931348623157e308")
            }
        }
        let loaded = try load("-8.988465674311579e307", "8.988465674311579e307")
        #expect(loaded.scenes[0].layers[1].shapes[0].fill
            == Self.radial(-Self.max / 2, Self.max / 2))
    }

    /// Seeded fuzz of drags on a gradient near the limit: a move is accepted
    /// exactly when the moved center and edges are finite (the shape's own
    /// points stay small), and a rejected move changes nothing. Undo restores all.
    @Test(arguments: [UInt64(3), 211])
    func dragNearTheLimitIsAcceptedExactlyWhenEdgesStayFinite(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        let start = FillRadialExtentAdversarialTests.doc(Self.radial(Self.max / 4, Self.max / 2))
        var e = CommandEngine(document: start)
        var history = [start]
        let steps: [Double] = [1e306, -1e306, Self.max / 4, -Self.max / 4, Self.max / 2, -Self.max, 1, 0, -0.0]
        for _ in 0..<300 {
            let dx = steps.randomElement(using: &rng) ?? 0
            guard case .radial(_, let center, let r) = e.document.scenes[0].layers[0].shapes[0].fill else {
                Issue.record("fill is no longer radial")
                return
            }
            let x = center.x + dx
            let (before, depth) = (e.document, e.undoStack.count)
            let move = TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: dx, dy: 0)
            if x.isFinite, Self.edgesFinite(x, r) {
                try e.perform(move)
                history.append(e.document)
            } else {
                #expect(throws: CommandError.self, "\(x) \(r)") { try e.perform(move) }
                #expect(e.document == before)
                #expect(e.undoStack.count == depth)
            }
        }
        #expect(history.count > 10)
        while e.canUndo {
            try e.undo()
            history.removeLast()
            #expect(e.document == history.last)
        }
        #expect(e.document == start)
    }
}
