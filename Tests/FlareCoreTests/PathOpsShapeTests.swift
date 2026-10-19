// PathOpsShapeTests.swift: the PathOps contract exists with the packet's
// signatures. Each entry point whose body has not landed throws
// GeometryError.notBuilt naming itself; a slice that builds a body removes
// its row here and its own suite takes over.
import FlareCore
import Testing

@Suite struct PathOpsShapeTests {
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

    /// (expected name, call) for every stubbed entry point.
    static let stubs: [(String, @Sendable () throws -> Void)] = [
        ("length(tolerance:)", { _ = try square.length(tolerance: 0.1) }),
        ("sample(atLength:tolerance:)", { _ = try square.sample(atLength: 5, tolerance: 0.1) }),
        ("trimmed(start:end:offset:mode:tolerance:)", {
            _ = try square.trimmed(start: 0, end: 0.5, offset: 0, mode: .together, tolerance: 0.1)
        }),
        ("dashed(_:phase:tolerance:)", { _ = try square.dashed([10, 5], phase: 0, tolerance: 0.1) }),
        ("outlined(width:join:cap:miterLimit:tolerance:)", {
            _ = try square.outlined(width: 4, join: .round, cap: .butt, miterLimit: 4, tolerance: 0.1)
        }),
    ]

    @Test(arguments: 0..<stubs.count)
    func stubThrowsNotBuiltNamingItself(_ index: Int) {
        let (name, call) = Self.stubs[index]
        #expect(throws: GeometryError.notBuilt(name)) { try call() }
    }

    @Test func anchorsViewAndValueTypes() {
        let contours: [PathContour] = Self.square.contours
        _ = Path(contours: contours).elements
        let anchor = PathAnchor(point: Point(x: 1, y: 2), handleIn: Point(x: 0, y: 2), handleOut: nil, kind: .smooth)
        #expect(anchor.handleIn == Point(x: 0, y: 2) && anchor.handleOut == nil)
        #expect(PathAnchor(point: Point(x: 1, y: 2)).kind == .corner)
        #expect(PathContour(anchors: [anchor], closed: true).anchors == [anchor])
        #expect(TrimMode(rawValue: "eachContour") == .eachContour && BooleanOp(rawValue: "exclude") == .exclude)
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
