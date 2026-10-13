// FillColorAdversarialTests.swift: adversarial and fuzz tests for the finite
// fill color check (#189). Random channels drawn from finite, huge, subnormal,
// NaN and infinite values: a fill is accepted exactly when every channel is
// finite, a rejected command leaves the engine untouched, and an accepted one
// saves, reloads and undoes exactly. Also covers long gradients, groups,
// coalescing and lookups that would fail anyway.
@testable import FlareCore
import Testing

@Suite struct FillColorAdversarialTests {
    static let channels: [Double] = [
        0, -0.0, 0.5, 1, -3, 7, 1e308, -.greatestFiniteMagnitude, .leastNonzeroMagnitude,
        .nan, -.nan, .signalingNaN, .infinity, -.infinity,
    ]
    static let owners: [(LayerOwner, String)] = [(.symbol("sym"), "wing"), (.scene(Fixtures.sceneID), "ball")]

    static func color(_ rng: inout SplitMix64) -> Color {
        func pick() -> Double { channels.randomElement(using: &rng) ?? 0 }
        return Color(r: pick(), g: pick(), b: pick(), a: pick())
    }

    static func isFinite(_ c: Color) -> Bool { [c.r, c.g, c.b, c.a].allSatisfy(\.isFinite) }

    /// A random fill and whether every color in it is finite.
    static func fill(_ rng: inout SplitMix64) -> (Fill, Bool) {
        let kind = Int.random(in: 0...2, using: &rng)
        if kind == 0 {
            let c = color(&rng)
            return (.solid(c), isFinite(c))
        }
        let count = Int.random(in: 0...4, using: &rng)
        let stops = (0..<count).map { i in
            GradientStop(offset: Double(i) / Double(max(count - 1, 1)), color: color(&rng))
        }
        let ok = stops.allSatisfy { isFinite($0.color) }
        return kind == 1
            ? (.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 4, y: 3)), ok)
            : (.radial(stops: stops, center: Point(x: 1, y: 1), radius: 5), ok)
    }

    static func command(_ rng: inout SplitMix64, fill: Fill) -> any Command {
        let (owner, layer) = owners[Int.random(in: 0..<owners.count, using: &rng)]
        switch Int.random(in: 0...2, using: &rng) {
        case 0: return SetShapeFill(owner: owner, layerID: layer, index: 0, fill: fill)
        case 1: return AddShape(owner: owner, layerID: layer, shape: Shape(points: [Point(x: 1, y: 2)], fill: fill))
        default:
            var text = TextCommandsTests.hello
            text.fill = fill
            return AddTextShape(owner: owner, layerID: layer, text: text)
        }
    }

    @Test(arguments: [UInt64(1), 7, 189, 0xDEAD_BEEF])
    func fuzzAcceptsExactlyFiniteColors(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        var history = [e.document]
        for _ in 0..<300 {
            let (fill, ok) = Self.fill(&rng)
            let cmd = Self.command(&rng, fill: fill)
            let (before, depth) = (e.document, e.undoStack.count)
            if ok {
                try e.perform(cmd)
                let saved = try FlareFormat.encode(e.document)
                #expect(try FlareFormat.decode(saved) == e.document)
                history.append(e.document)
            } else {
                #expect(throws: CommandError.invalidDocument("color channels must be finite"), "\(fill)") {
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

    @Test func oneBadStopInALongGradientIsRejected() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        var stops = (0...1000).map { GradientStop(offset: Double($0) / 1000, color: .white) }
        stops[1000].color.a = .nan
        for fill in [Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0)),
                     .radial(stops: stops, center: Point(x: 0, y: 0), radius: 1)] {
            #expect(throws: CommandError.self) {
                try e.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: fill))
            }
        }
        stops[1000].color.a = 1
        try e.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0,
                                   fill: .linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: 1, y: 0))))
        _ = try FlareFormat.encode(e.document)
    }

    @Test func badFillInsideAGroupRollsBackTheWholeGroup() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let before = e.document
        #expect(throws: CommandError.self) {
            try e.group("Recolor") { g in
                try g.perform(SetShapeFill(owner: .scene(Fixtures.sceneID), layerID: "ball", index: 0,
                                           fill: .solid(Color(r: 0, g: 1, b: 0))))
                try g.perform(SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0,
                                           fill: .solid(Color(r: .infinity, g: 0, b: 0))))
            }
        }
        #expect(e.document == before)
        #expect(!e.canUndo && !e.canRedo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test func badFillDoesNotJoinACoalescedEdit() throws {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let good = SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: .solid(Color(r: 0, g: 0, b: 1)))
        try e.perform(good, coalesceKey: "drag")
        let after = e.document
        let bad = SetShapeFill(owner: .symbol("sym"), layerID: "wing", index: 0, fill: .solid(Color(r: 0, g: .nan, b: 1)))
        #expect(throws: CommandError.self) { try e.perform(bad, coalesceKey: "drag") }
        #expect(e.document == after)
        #expect(e.undoStack.count == 1)
        try e.undo()
        #expect(e.document == ShapeTextOwnerTests.start())
    }

    @Test(arguments: [(LayerOwner.symbol("nope"), "wing"), (.scene(Fixtures.sceneID), "nope"), (.scene("nope"), "ball")])
    func badFillOnAMissingTargetThrowsWithoutCrashing(_ owner: LayerOwner, _ layer: String) {
        var e = CommandEngine(document: ShapeTextOwnerTests.start())
        let nan = Fill.solid(Color(r: .nan, g: 0, b: 0))
        for index in [-1, 0, Int.max] {
            #expect(throws: CommandError.self) {
                try e.perform(SetShapeFill(owner: owner, layerID: layer, index: index, fill: nan))
            }
        }
        #expect(e.document == ShapeTextOwnerTests.start())
    }
}
