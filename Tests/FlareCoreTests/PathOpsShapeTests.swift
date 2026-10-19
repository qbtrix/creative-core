// PathOpsShapeTests.swift: the PathOps contract exists with the packet's
// signatures. Each entry point whose body has not landed throws
// GeometryError.notBuilt naming itself; a slice that builds a body removes
// its row here and its own suite takes over.
import FlareCore
import Testing

@Suite struct PathOpsShapeTests {
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)
    static let location = PathLocation(element: 1, t: 0.5, point: Point(x: 5, y: 0), distance: 0)

    /// (expected name, call) for every stubbed entry point.
    static let stubs: [(String, @Sendable () throws -> Void)] = [
        ("nearest(to:tolerance:)", { _ = try square.nearest(to: Point(x: 1, y: 1), tolerance: 0.1) }),
        ("inserting(at:)", { _ = try square.inserting(at: location) }),
        ("removingAnchor(contour:index:)", { _ = try square.removingAnchor(contour: 0, index: 1) }),
        ("converting(contour:index:to:)", { _ = try square.converting(contour: 0, index: 1, to: .smooth) }),
        ("length(tolerance:)", { _ = try square.length(tolerance: 0.1) }),
        ("sample(atLength:tolerance:)", { _ = try square.sample(atLength: 5, tolerance: 0.1) }),
        ("trimmed(start:end:offset:mode:tolerance:)", {
            _ = try square.trimmed(start: 0, end: 0.5, offset: 0, mode: .together, tolerance: 0.1)
        }),
        ("dashed(_:phase:tolerance:)", { _ = try square.dashed([10, 5], phase: 0, tolerance: 0.1) }),
        ("outlined(width:join:cap:miterLimit:tolerance:)", {
            _ = try square.outlined(width: 4, join: .round, cap: .butt, miterLimit: 4, tolerance: 0.1)
        }),
        ("combine(_:_:_:rule:tolerance:)", {
            _ = try Path.combine(.union, square, square, rule: .nonZero, tolerance: 0.1)
        }),
    ]

    @Test(arguments: 0..<stubs.count)
    func stubThrowsNotBuiltNamingItself(_ index: Int) {
        let (name, call) = Self.stubs[index]
        #expect(throws: GeometryError.notBuilt(name)) { try call() }
    }

    @Test func stubNamesAreDistinct() {
        #expect(Set(Self.stubs.map(\.0)).count == Self.stubs.count)
    }

    @Test func anchorsViewSignatures() {
        let contours: [PathContour] = Self.square.contours
        let rebuilt: Path = Path(contours: contours)
        _ = rebuilt.elements
    }

    @Test func valueTypesHoldTheirFields() {
        let anchor = PathAnchor(point: Point(x: 1, y: 2), handleIn: Point(x: 0, y: 2), handleOut: nil, kind: .smooth)
        #expect(anchor.handleIn == Point(x: 0, y: 2))
        #expect(anchor.handleOut == nil)
        #expect(PathAnchor(point: Point(x: 1, y: 2)).kind == .corner)
        let contour = PathContour(anchors: [anchor], closed: true)
        #expect(contour.anchors == [anchor] && contour.closed)
        #expect(Self.location.element == 1 && Self.location.t == 0.5)
        #expect(TrimMode(rawValue: "eachContour") == .eachContour)
        #expect(BooleanOp(rawValue: "exclude") == .exclude)
        #expect(AnchorKind(rawValue: "symmetric") == .symmetric)
        #expect(Path.maxBooleanVertices == 200_000)
    }

    @Test func newGeometryErrorsAreEquatable() {
        #expect(GeometryError.notBuilt("a") == .notBuilt("a"))
        #expect(GeometryError.notBuilt("a") != .notBuilt("b"))
        #expect(GeometryError.tooComplex(5) == .tooComplex(5))
        #expect(GeometryError.tooComplex(5) != .tooComplex(6))
        #expect(GeometryError.invalidLocation == .invalidLocation)
        #expect(GeometryError.invalidPattern != .invalidLocation)
    }
}
