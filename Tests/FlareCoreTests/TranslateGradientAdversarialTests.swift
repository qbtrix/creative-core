// TranslateGradientAdversarialTests.swift: edge cases for TranslateShape moving
// a gradient fill with the shape (issue #201). Overflow that only the gradient
// hits is rejected, odd shapes still carry their gradient, drags merge to the
// same fill, and a seeded fuzz keeps the gradient fixed relative to the shape.
import FlareCore
import Testing

@Suite struct TranslateGradientAdversarialTests {
    static let s = Fixtures.sceneID
    static let stops = [GradientStop(offset: 0, color: .black), GradientStop(offset: 1, color: .white)]

    static func doc(_ shape: Shape) -> Document {
        Document(scenes: [Scene(id: "s", name: "S", layers: [Layer(id: "l", name: "L", shapes: [shape])])])
    }

    static func shape(_ e: CommandEngine) throws -> Shape {
        try #require(e.document.scenes.first?.layers.first?.shapes.first)
    }

    static func move(_ dx: Double, _ dy: Double) -> TranslateShape {
        TranslateShape(owner: .scene("s"), layerID: "l", index: 0, dx: dx, dy: dy)
    }

    /// The shape's points are near zero but its gradient sits near the largest
    /// Double, so only the gradient overflows. The move must throw and change nothing.
    @Test(arguments: [
        Fill.linear(stops: stops, start: Point(x: 0, y: 0), end: Point(x: .greatestFiniteMagnitude, y: 0)),
        Fill.linear(stops: stops, start: Point(x: .greatestFiniteMagnitude, y: 0), end: Point(x: 0, y: 0)),
        Fill.radial(stops: stops, center: Point(x: .greatestFiniteMagnitude, y: 0), radius: 1),
    ])
    func overflowOnlyInGradientIsRejected(fill: Fill) throws {
        let start = Self.doc(Shape(points: [Point(x: 0, y: 0), Point(x: 1, y: 1)], fill: fill))
        var e = CommandEngine(document: start)
        #expect(throws: CommandError.self) { try e.perform(Self.move(.greatestFiniteMagnitude, 0)) }
        #expect(e.document == start)
        #expect(!e.canUndo)
        _ = try FlareFormat.encode(e.document)
    }

    @Test(arguments: [(Double.nan, 0.0), (0, .nan), (.infinity, 0), (0, -.infinity)])
    func nonFiniteMoveOfGradientShapeIsRejected(dx: Double, dy: Double) throws {
        let fill = Fill.radial(stops: Self.stops, center: Point(x: 5, y: 5), radius: 4)
        let start = Self.doc(Shape(points: [Point(x: 0, y: 0)], fill: fill))
        var e = CommandEngine(document: start)
        #expect(throws: CommandError.self) { try e.perform(Self.move(dx, dy)) }
        #expect(e.document == start)
    }

    /// A shape with no points and no path still owns its gradient, which moves.
    @Test func emptyShapeStillMovesItsGradient() throws {
        let fill = Fill.linear(stops: Self.stops, start: Point(x: 1, y: 2), end: Point(x: 3, y: 4))
        let start = Self.doc(Shape(points: [], fill: fill))
        var e = CommandEngine(document: start)
        try e.perform(Self.move(10, -10))
        #expect(try Self.shape(e).fill
            == .linear(stops: Self.stops, start: Point(x: 11, y: -8), end: Point(x: 13, y: -6)))
        try e.undo()
        #expect(e.document == start)
    }

    /// A zero-length linear gradient (start == end) and many stops at one
    /// offset are legal; the move keeps them exactly as they were, only shifted.
    @Test func degenerateGradientMovesUnchangedOtherwise() throws {
        let manyStops = (0..<64).map { i in
            GradientStop(offset: 0.5, color: Color(r: Double(i) / 63, g: 0, b: 1))
        }
        let fill = Fill.linear(stops: manyStops, start: Point(x: 7, y: 7), end: Point(x: 7, y: 7))
        var e = CommandEngine(document: Self.doc(Shape(points: [Point(x: 7, y: 7)], fill: fill)))
        try e.perform(Self.move(-7, -7))
        #expect(try Self.shape(e).fill
            == .linear(stops: manyStops, start: Point(x: 0, y: 0), end: Point(x: 0, y: 0)))
    }

    @Test func zeroMoveLeavesGradientIdentical() throws {
        let fill = Fill.radial(stops: Self.stops, center: Point(x: -0.0, y: 1e-300), radius: 1e-300)
        let start = Self.doc(Shape(points: [Point(x: 0, y: 0)], fill: fill))
        var e = CommandEngine(document: start)
        try e.perform(Self.move(0, 0))
        let moved = try Self.shape(e)
        guard case .radial(_, let center, let radius) = moved.fill else {
            Issue.record("fill is no longer radial: \(moved.fill)")
            return
        }
        #expect(center.y == 1e-300)
        #expect(radius == 1e-300)
    }

    /// A coalesced drag of many small steps ends on the same shape, fill
    /// included, as the steps applied one at a time, and one undo restores the start.
    @Test func coalescedDragMovesGradientWithPoints() throws {
        let fill = Fill.linear(stops: Self.stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))
        let start = Self.doc(Shape(points: [Point(x: 0, y: 0)], fill: fill))
        var e = CommandEngine(document: start)
        for _ in 0..<50 { try e.perform(Self.move(0.1, -0.3), coalesceKey: "drag") }
        let dragged = try Self.shape(e)
        var stepped = Shape(points: [Point(x: 0, y: 0)], fill: fill)
        for _ in 0..<50 { stepped = stepped.translated(dx: 0.1, dy: -0.3) }
        #expect(dragged == stepped)
        #expect(stepped.fill != fill)
        try e.undo()
        #expect(e.document == start)
        #expect(!e.canUndo)
        try e.redo()
        #expect(try Self.shape(e) == dragged)
    }

    /// A gradient-filled shape inside a symbol moves its gradient too.
    @Test func symbolShapeMovesGradient() throws {
        var doc = Fixtures.withSymbol()
        let fill = Fill.radial(stops: Self.stops, center: Point(x: 1, y: 1), radius: 2)
        doc.symbols[0].layers[0].shapes = [Shape(points: [Point(x: 0, y: 0)], fill: fill)]
        var e = CommandEngine(document: doc)
        try e.perform(TranslateShape(owner: .symbol("sym"), layerID: "wing", index: 0, dx: 3, dy: 4))
        let moved = try #require(e.document.symbols.first?.layers.first?.shapes.first)
        #expect(moved.fill == .radial(stops: Self.stops, center: Point(x: 4, y: 5), radius: 2))
        try e.undo()
        #expect(e.document == doc)
    }

    /// The moved gradient survives a save and load unchanged, and the SVG
    /// export writes the moved coordinates.
    @Test func movedGradientRoundTripsAndExports() throws {
        let fill = Fill.linear(stops: Self.stops, start: Point(x: 0, y: 0), end: Point(x: 10, y: 0))
        let square = Shape(points: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], fill: fill)
        var e = CommandEngine(document: Self.doc(square))
        try e.perform(Self.move(250, 40))
        let loaded = try FlareFormat.decode(FlareFormat.encode(e.document))
        #expect(loaded == e.document)
        let svg = try SVGExporter.export(scene: try #require(e.document.scenes.first), frame: 0)
        #expect(svg.contains("x1=\"250\" y1=\"40\" x2=\"260\" y2=\"40\""))
    }

    /// Seeded fuzz: random gradient shapes and moves. A move keeps the
    /// gradient's offset from the first point (within rounding), keeps stops
    /// and radius exactly, and undo gives back the exact start.
    @Test(arguments: [UInt64(1), 7, 2026, 0xDEAD_BEEF])
    func fuzzGradientStaysWithShape(seed: UInt64) throws {
        var rng = SplitMix64(seed: seed)
        func coord() -> Double {
            Bool.random(using: &rng) ? Double.random(in: -1e6...1e6, using: &rng)
                : Double.random(in: -1...1, using: &rng)
        }
        for _ in 0..<200 {
            let anchor = Point(x: coord(), y: coord())
            let fill: Fill = Bool.random(using: &rng)
                ? .linear(stops: Self.stops, start: Point(x: coord(), y: coord()), end: Point(x: coord(), y: coord()))
                : .radial(stops: Self.stops, center: Point(x: coord(), y: coord()),
                          radius: Double.random(in: 1e-6...1e6, using: &rng))
            let start = Self.doc(Shape(points: [anchor], fill: fill))
            var e = CommandEngine(document: start)
            let (dx, dy) = (coord(), coord())
            try e.perform(Self.move(dx, dy))
            let moved = try Self.shape(e)
            let p = try #require(moved.points.first)
            func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= 1e-6 * max(1, abs(a), abs(b)) }
            func keepsOffset(_ old: Point, _ new: Point) -> Bool {
                close(new.x - p.x, old.x - anchor.x) && close(new.y - p.y, old.y - anchor.y)
            }
            switch (fill, moved.fill) {
            case (.linear(let s0, let a0, let b0), .linear(let s1, let a1, let b1)):
                #expect(s0 == s1)
                #expect(keepsOffset(a0, a1) && keepsOffset(b0, b1))
            case (.radial(let s0, let c0, let r0), .radial(let s1, let c1, let r1)):
                #expect(s0 == s1 && r0 == r1)
                #expect(keepsOffset(c0, c1))
            default:
                Issue.record("fill kind changed: \(fill) -> \(moved.fill)")
            }
            try e.undo()
            #expect(e.document == start)
        }
    }
}
