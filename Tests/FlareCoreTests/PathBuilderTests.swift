// PathBuilderTests.swift: PathBuilders.rectangle and ellipse give closed
// paths of the right elements, stay inside their rect, clamp the corner
// radius to the short side, reject non-finite input and survive the format.
import FlareCore
import Testing

@Suite struct PathBuilderTests {
    static let ellipseRect = Rect(minX: 10, minY: 20, maxX: 210, maxY: 120)
    static let wide = Rect(minX: 0, minY: 0, maxX: 100, maxY: 40)

    static func expectBounds(_ path: Path, equal rect: Rect, tolerance: Double = 1e-6) {
        guard let b = path.bounds else {
            Issue.record("no bounds")
            return
        }
        #expect(abs(b.minX - rect.minX) <= tolerance)
        #expect(abs(b.minY - rect.minY) <= tolerance)
        #expect(abs(b.maxX - rect.maxX) <= tolerance)
        #expect(abs(b.maxY - rect.maxY) <= tolerance)
    }

    static func allPoints(_ path: Path) -> [Point] {
        path.elements.flatMap { element -> [Point] in
            switch element {
            case .move(let p), .line(let p): [p]
            case .quad(let c, let p): [c, p]
            case .cubic(let c1, let c2, let p): [c1, c2, p]
            case .close: []
            }
        }
    }

    @Test func ellipseIsFourCubics() throws {
        let path = try PathBuilders.ellipse(in: Self.ellipseRect)
        #expect(path.elements.count == 6)
        #expect(path.elements.first == .move(to: Point(x: 110, y: 20)))
        let cubics = path.elements.filter { if case .cubic = $0 { true } else { false } }
        #expect(cubics.count == 4)
        #expect(path.elements.last == .close)
    }

    @Test func ellipseBoundsEqualTheRect() throws {
        Self.expectBounds(try PathBuilders.ellipse(in: Self.ellipseRect), equal: Self.ellipseRect)
    }

    @Test func ellipseFlattensOntoTheEllipse() throws {
        let path = try PathBuilders.ellipse(in: Self.ellipseRect)
        let (cx, cy, rx, ry) = (110.0, 70.0, 100.0, 50.0)
        let lines = try path.flattened(tolerance: 0.01)
        #expect(lines.count == 1)
        #expect(lines[0].count > 20)
        for p in lines[0] {
            let u = (p.x - cx) / rx, v = (p.y - cy) / ry
            #expect(abs(u * u + v * v - 1) <= 1e-3)
        }
    }

    @Test func cornerRadiusClampsToHalfTheShortSide() throws {
        let path = try PathBuilders.rectangle(in: Self.wide, cornerRadius: 999)
        #expect(path.elements.first == .move(to: Point(x: 20, y: 0)))
        #expect(path == (try PathBuilders.rectangle(in: Self.wide, cornerRadius: 20)))
        Self.expectBounds(path, equal: Self.wide)
        for p in Self.allPoints(path) {
            #expect(p.x >= 0 && p.x <= 100 && p.y >= 0 && p.y <= 40)
        }
    }

    @Test func roundedCornersAreQuarterCircles() throws {
        let path = try PathBuilders.rectangle(in: Self.wide, cornerRadius: 10)
        #expect(path.elements.count == 10)
        guard case .cubic(let c1, let c2, let to) = path.elements[2] else {
            Issue.record("top-right corner is not a cubic")
            return
        }
        #expect(abs(c1.x - 95.522847498) <= 1e-9 && c1.y == 0)
        #expect(c2.x == 100 && abs(c2.y - 4.477152502) <= 1e-9)
        #expect(to == Point(x: 100, y: 10))
        for p in try path.flattened(tolerance: 0.001)[0] {
            // Points in the top-right corner lie on the circle centred (90, 10).
            guard p.x > 90, p.y < 10 else { continue }
            let d = ((p.x - 90) * (p.x - 90) + (p.y - 10) * (p.y - 10)).squareRoot()
            #expect(abs(d - 10) <= 0.01)
        }
    }

    @Test func radiusZeroGivesFourLines() throws {
        let path = try PathBuilders.rectangle(in: Self.wide)
        #expect(path == Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .line(to: Point(x: 100, y: 0)),
            .line(to: Point(x: 100, y: 40)),
            .line(to: Point(x: 0, y: 40)),
            .line(to: Point(x: 0, y: 0)),
            .close,
        ]))
        #expect(try PathBuilders.rectangle(in: Self.wide, cornerRadius: -5) == path)
    }

    @Test func nonFiniteInputThrows() {
        for bad in [Double.nan, .infinity, -.infinity] {
            let rects = [
                Rect(minX: bad, minY: 0, maxX: 10, maxY: 10), Rect(minX: 0, minY: bad, maxX: 10, maxY: 10),
                Rect(minX: 0, minY: 0, maxX: bad, maxY: 10), Rect(minX: 0, minY: 0, maxX: 10, maxY: bad),
            ]
            for rect in rects {
                #expect(throws: GeometryError.nonFinite) { try PathBuilders.rectangle(in: rect) }
                #expect(throws: GeometryError.nonFinite) { try PathBuilders.ellipse(in: rect) }
            }
            #expect(throws: GeometryError.nonFinite) { try PathBuilders.rectangle(in: Self.wide, cornerRadius: bad) }
        }
    }

    @Test func zeroSizeAndHugeRectsGiveFinitePoints() throws {
        let rects = [
            Rect(minX: 5, minY: 5, maxX: 5, maxY: 5), Rect(minX: 0, minY: 3, maxX: 0, maxY: 50),
            Rect(minX: 0, minY: 3, maxX: 80, maxY: 3), Rect(minX: -1e308, minY: -1e308, maxX: 1e308, maxY: 1e308),
        ]
        for rect in rects {
            for path in [
                try PathBuilders.rectangle(in: rect, cornerRadius: 4), try PathBuilders.ellipse(in: rect),
            ] {
                #expect(Self.allPoints(path).allSatisfy { $0.x.isFinite && $0.y.isFinite })
            }
        }
    }

    @Test func builtShapesSurviveTheFormat() throws {
        var doc = Fixtures.document()
        for path in [
            try PathBuilders.rectangle(in: Self.wide), try PathBuilders.rectangle(in: Self.wide, cornerRadius: 7.25),
            try PathBuilders.ellipse(in: Self.ellipseRect),
        ] {
            doc.scenes[0].layers[0].shapes.append(Shape(points: [], path: path))
        }
        let data = try FlareFormat.encode(doc)
        #expect(try FlareFormat.decode(data) == doc)
    }
}
