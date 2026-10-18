// ShapeKeyCompatTests.swift: a shape key is made compatible with its track (AP-4): anchors go on the longest
// segments, existing keys gain anchors, contour counts must match, and the start point is the nearest rotation.
import FlareCore
import Testing

@Suite(.disabled("AP-4 turns this on"))
struct ShapeKeyCompatTests {
    static func p(_ x: Double, _ y: Double) -> Point { Point(x: x, y: y) }
    static func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Path {
        Path(polyline: [p(x0, y0), p(x1, y0), p(x1, y1), p(x0, y1)], closed: true)
    }
    static let star = (try? PathBuilders.star(in: Rect(minX: 0, minY: 0, maxX: 40, maxY: 40), points: 5, innerRatio: 0.5)) ?? Path()

    /// SetShapeKeyframe at frame 24 on ball shape 0 over `keys`: the engine, the document before, and the keys after.
    static func setKey(_ path: Path, on keys: [PathKeyframe]) throws -> (CommandEngine, Document, [PathKeyframe]) {
        var start = Fixtures.document()
        start.scenes[0].layers[1].shapeTracks = [ShapeTrack(shapeIndex: 0, keys: keys)]
        var engine = CommandEngine(document: start)
        try engine.perform(SetShapeKeyframe(owner: .scene(Fixtures.sceneID), layerID: "ball", shape: 0, frame: 24, path: path))
        return (engine, start, engine.document.scenes.first?.layers.first { $0.id == "ball" }?.shapeTracks.first?.keys ?? [])
    }

    /// The end point of every element but a close, less a closing line back to the start.
    static func anchors(_ path: Path) -> [Point] {
        let ends: [Point] = path.elements.compactMap {
            switch $0 {
            case .move(let to), .line(let to), .quad(_, let to), .cubic(_, _, let to): to
            case .close: nil
            }
        }
        return ends.count > 1 && ends.first == ends.last ? Array(ends.dropLast()) : ends
    }

    /// `path` draws rectangle (x0, y0)-(x1, y1): every flattened point on its edges within 1e-9, every corner an anchor.
    static func draws(_ path: Path, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) throws -> Bool {
        let near = { (a: Double, b: Double) in abs(a - b) <= 1e-9 }
        let onEdge = try path.flattened(tolerance: 0.01).joined().allSatisfy { q in
            (near(q.x, x0) || near(q.x, x1) || near(q.y, y0) || near(q.y, y1)) && (x0 - 1e-9...x1 + 1e-9).contains(q.x) && (y0 - 1e-9...y1 + 1e-9).contains(q.y)
        }
        return onEdge && anchors(rect(x0, y0, x1, y1)).allSatisfy(anchors(path).contains)
    }

    @Test func insertsOnLongestSegments() throws {
        let (_, _, keys) = try Self.setKey(Self.rect(0, 0, 40, 10), on: [PathKeyframe(frame: 0, path: Self.star)])
        let added = try #require(keys.last)
        #expect(try added.frame == 24 && Self.anchors(added.path).count == 10 && Self.draws(added.path, 0, 0, 40, 10))
        // The 40-long sides take all six new anchors; the 10-long ones take none.
        #expect(Self.anchors(added.path).allSatisfy { $0.y == 0 || $0.y == 10 })
    }

    @Test func existingKeysGainAnchors() throws {
        let start = [PathKeyframe(frame: 0, path: Self.rect(0, 0, 10, 10)), PathKeyframe(frame: 12, path: Self.rect(0, 0, 40, 10))]
        var (engine, before, keys) = try Self.setKey(Self.star, on: start)
        #expect(keys.map(\.frame) == [0, 12, 24] && keys.map { Self.anchors($0.path).count } == [10, 10, 10])
        #expect(try Self.draws(keys[0].path, 0, 0, 10, 10) && Self.draws(keys[1].path, 0, 0, 40, 10))
        try engine.undo()
        #expect(engine.document == before)
    }

    @Test func differentContourCountsRefused() throws {
        let two = Path(elements: Self.rect(0, 0, 10, 10).elements + Self.rect(20, 0, 30, 10).elements)
        let error = #expect(throws: CommandError.self) { try Self.setKey(two, on: [PathKeyframe(frame: 0, path: Self.rect(0, 0, 10, 10))]) }
        #expect(error.map { "\($0)".contains("Shapes with a different number of parts can't morph") } == true)
    }

    @Test func alignsStartPoint() throws {
        // The same square nudged by 1 and starting at its far corner: rotation 2 is nearest.
        let rotated = Path(polyline: [Self.p(11, 11), Self.p(1, 11), Self.p(1, 1), Self.p(11, 1)], closed: true)
        let (_, _, keys) = try Self.setKey(rotated, on: [PathKeyframe(frame: 0, path: Self.rect(0, 0, 10, 10))])
        #expect(keys.last.map { Self.anchors($0.path) } == Self.anchors(Self.rect(1, 1, 11, 11)))
    }
}
