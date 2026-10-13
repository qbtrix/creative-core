// FillPointAdversarialTests.swift: adversarial and fuzz tests for the finite
// gradient point check (#192). Random start, end and center coordinates drawn
// from finite, huge, subnormal, NaN and infinite values: a gradient is accepted
// exactly when every point is finite, a rejected command leaves the engine
// untouched, and an accepted one saves, reloads and undoes exactly. Extreme
// finite points also render to SVG. Also covers groups and the load path,
// which can never carry a bad point.
@testable import FlareCore
import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite struct FillPointAdversarialTests {
    static let coordinates: [Double] = [
        0, -0.0, 0.5, -3, 1e15, 1e308, .greatestFiniteMagnitude, -.greatestFiniteMagnitude,
        .leastNonzeroMagnitude, -.leastNormalMagnitude, .nan, -.nan, .signalingNaN, .infinity, -.infinity,
    ]
    static let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]

    static func point(_ rng: inout SplitMix64) -> Point {
        func pick() -> Double { coordinates.randomElement(using: &rng) ?? 0 }
        return Point(x: pick(), y: pick())
    }

    /// A random gradient with finite colors and radius, and whether its points are finite.
    static func fill(_ rng: inout SplitMix64) -> (Fill, Bool) {
        if Bool.random(using: &rng) {
            let (start, end) = (point(&rng), point(&rng))
            return (.linear(stops: stops, start: start, end: end), start.isFinite && end.isFinite)
        }
        let center = point(&rng)
        return (.radial(stops: stops, center: center, radius: Double.random(in: 0.5...50, using: &rng)),
                center.isFinite)
    }

    @Test func pointIsFiniteMatchesBothCoordinates() {
        for x in Self.coordinates {
            for y in Self.coordinates {
                #expect(Point(x: x, y: y).isFinite == (x.isFinite && y.isFinite), "\(x), \(y)")
            }
        }
    }

    @Test(arguments: [UInt64(1), 7, 192, 0xC0FF_EE00])
    func fuzzAcceptsExactlyFinitePoints(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        var history = [e.document]
        for _ in 0..<300 {
            let (fill, ok) = Self.fill(&rng)
            let cmd = FillColorAdversarialTests.command(&rng, fill: fill)
            let (before, depth) = (e.document, e.undoStack.count)
            if ok {
                try e.perform(cmd)
                #expect(try FlareFormat.decode(FlareFormat.encode(e.document)) == e.document)
                history.append(e.document)
            } else {
                #expect(throws: CommandError.invalidDocument("gradient points must be finite"), "\(fill)") {
                    try e.perform(cmd)
                }
                #expect(e.document == before)
                #expect(e.undoStack.count == depth)
            }
        }
        while e.canUndo {
            try e.undo()
            history.removeLast()
            #expect(e.document == history.last)
        }
    }

    @Test func extremeFinitePointsSaveAndReloadExactly() throws {
        let big = Double.greatestFiniteMagnitude
        let fills: [Fill] = [
            .linear(stops: Self.stops, start: Point(x: -big, y: big), end: Point(x: big, y: -big)),
            .linear(stops: Self.stops, start: Point(x: .leastNonzeroMagnitude, y: -0.0), end: Point(x: 0, y: 0)),
            .linear(stops: [], start: Point(x: 3, y: 3), end: Point(x: 3, y: 3)),
            .radial(stops: Self.stops, center: Point(x: -big, y: .leastNonzeroMagnitude), radius: big),
        ]
        for fill in fills {
            var e = CommandEngine(document: ShapeTextOwnerTests.start())
            try e.perform(SetShapeFill(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, fill: fill))
            let decoded = try FlareFormat.decode(FlareFormat.encode(e.document))
            #expect(decoded.scenes[0].layers[1].shapes[0].fill == fill)
            _ = try SVGExporter.export(scene: decoded.scenes[0], frame: 0)
        }
    }

    @Test func badPointWithBadColorOrRadiusStillThrowsAndChangesNothing() throws {
        let nanPoint = Point(x: .nan, y: .nan)
        let fills: [Fill] = [
            .linear(stops: [GradientStop(offset: 0, color: Color(r: .nan, g: 0, b: 0))], start: nanPoint, end: nanPoint),
            .linear(stops: [GradientStop(offset: 2, color: .black)], start: nanPoint, end: Point(x: 0, y: 0)),
            .radial(stops: Self.stops, center: nanPoint, radius: -.infinity),
            .radial(stops: [GradientStop(offset: 1, color: .black), GradientStop(offset: 0, color: .white)],
                    center: Point(x: 0, y: .infinity), radius: 0),
        ]
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        for fill in fills {
            #expect(throws: CommandError.self, "\(fill)") {
                try e.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: fill))
            }
            #expect(e.document == ShapeTextOwnerTests.start())
            #expect(!e.canUndo)
        }
    }

    @Test func badPointInsideGroupRollsBackTheWholeGroup() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let good = Fill.linear(stops: Self.stops, start: Point(x: 0, y: 0), end: Point(x: 5, y: 5))
        let bad = Fill.radial(stops: Self.stops, center: Point(x: -.infinity, y: 0), radius: 1)
        #expect(throws: CommandError.invalidDocument("gradient points must be finite")) {
            try e.group("Recolor") { g in
                try g.perform(SetShapeFill(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0, fill: good))
                try g.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: bad))
            }
        }
        #expect(e.document == ShapeTextOwnerTests.start())
        #expect(!e.canUndo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func loadRejectsOverflowingPointsAndKeepsHugeOnes() throws {
        var doc = Fixtures.document()
        doc.scenes[0].layers[1].shapes[0].fill = .linear(stops: [], start: Point(x: 12345.5, y: 0),
                                                         end: Point(x: 0, y: 0))
        let text = String(decoding: try FlareFormat.encode(doc), as: UTF8.self)
        #expect(text.components(separatedBy: "12345.5").count == 2)
        for x in ["1e400", "-1e400", "1.8e308"] {
            let bytes = Data(text.replacingOccurrences(of: "12345.5", with: x).utf8)
            #expect(throws: (any Error).self, "\(x)") { try FlareFormat.decode(bytes) }
        }
        let huge = Data(text.replacingOccurrences(of: "12345.5", with: "-1.7976931348623157e308").utf8)
        let loaded = try FlareFormat.decode(huge)
        #expect(loaded.scenes[0].layers[1].shapes[0].fill
            == .linear(stops: [], start: Point(x: -.greatestFiniteMagnitude, y: 0), end: Point(x: 0, y: 0)))
    }
}
