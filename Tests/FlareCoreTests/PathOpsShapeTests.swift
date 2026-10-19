// PathOpsShapeTests.swift: the PathOps contract exists with the packet's
// signatures. Every entry point has a body now and its own suite; what is
// left here is the value types and errors the slices share.
import FlareCore
import Testing

@Suite struct PathOpsShapeTests {
    static let square = Path(polyline: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], closed: true)

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
