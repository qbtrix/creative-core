// WorldBoundsTests.swift: an item's world box follows its matrix (rotation
// included), hugs curves rather than control points, widens by half the
// stroke width times the larger axis scale, and skips text and non-finite
// items; a selection's box is the union of its items' boxes.
@testable import FlareCore
import Testing

@Suite struct WorldBoundsTests {
    static func rectPath(_ w: Double, _ h: Double) -> Path {
        Path(elements: [
            .move(to: Point(x: 0, y: 0)), .line(to: Point(x: w, y: 0)),
            .line(to: Point(x: w, y: h)), .line(to: Point(x: 0, y: h)), .close,
        ])
    }

    static func item(
        _ outline: Path, matrix: Matrix = .identity, stroke: Stroke? = nil, shape: Int = 0, text: Bool = false
    ) -> RenderItem {
        let address = RenderAddress(owner: .scene("s"), hosts: [], layerID: "l",
                                    shapeIndex: text ? nil : shape, textIndex: text ? shape : nil)
        return RenderItem(address: address, outline: text ? Path() : outline, fill: text ? nil : .solid(.black),
                          stroke: stroke, matrix: matrix, opacity: 1, isLocked: false, isText: text)
    }

    static func expectClose(_ r: Rect?, _ e: Rect, _ tol: Double = 1e-9) {
        guard let r else {
            Issue.record("expected a box, got nil")
            return
        }
        #expect(abs(r.minX - e.minX) <= tol && abs(r.minY - e.minY) <= tol)
        #expect(abs(r.maxX - e.maxX) <= tol && abs(r.maxY - e.maxY) <= tol)
    }

    @Test func rotatedRectangleMatchesRotatedCorners() throws {
        let m = Transform(x: 20, y: 30, rotation: 30).matrix
        let corners = [Point(x: 0, y: 0), Point(x: 100, y: 0), Point(x: 100, y: 50), Point(x: 0, y: 50)]
        let expected = try #require(Rect(enclosing: corners.map { m.apply($0) }))
        Self.expectClose(Self.item(Self.rectPath(100, 50), matrix: m).worldBounds, expected)
        // Rotation actually moved the box away from the unrotated one.
        #expect(expected.width > 100 + 1)
    }

    @Test func strokeWidensByHalfWidthTimesScale() {
        let stroke = Stroke(width: 10)
        let path = Self.rectPath(100, 50)
        Self.expectClose(Self.item(path, stroke: stroke).worldBounds,
                         Rect(minX: -5, minY: -5, maxX: 105, maxY: 55))
        Self.expectClose(Self.item(path, matrix: .scale(x: 2, y: 2), stroke: stroke).worldBounds,
                         Rect(minX: -10, minY: -10, maxX: 210, maxY: 110))
        // Non-uniform scale widens every side by the larger axis.
        Self.expectClose(Self.item(path, matrix: .scale(x: 1, y: 2), stroke: stroke).worldBounds,
                         Rect(minX: -10, minY: -10, maxX: 110, maxY: 110))
        #expect(Matrix.scale(x: 3, y: -4).maxAxisScale == 4)
    }

    @Test func cubicBoundsAreTightNotControlBox() {
        let path = Path(elements: [
            .move(to: Point(x: 0, y: 0)),
            .cubic(control1: Point(x: 0, y: 100), control2: Point(x: 100, y: 100), to: Point(x: 100, y: 0)),
        ])
        // The curve peaks at t = 0.5, y = 0.75 * 100; its control points reach 100.
        Self.expectClose(Self.item(path, matrix: .translation(x: 10, y: 20)).worldBounds,
                         Rect(minX: 10, minY: 20, maxX: 110, maxY: 95))
    }

    @Test func emptyAndTextOnlySelectionsAreNil() {
        let text = Self.item(Path(), text: true)
        let list = RenderList(nodes: [], items: [text, Self.item(Self.rectPath(1, 1), shape: 1)])
        #expect(text.worldBounds == nil)
        #expect(list.worldBounds(of: []) == nil)
        #expect(list.worldBounds(of: [text.address]) == nil)
    }

    @Test func selectionIsUnionOfItemBoxes() throws {
        let a = Self.item(Self.rectPath(10, 10), matrix: .translation(x: -5, y: 40), stroke: Stroke(width: 2))
        let b = Self.item(Self.rectPath(30, 5), matrix: Transform(x: 50, rotation: 45).matrix, shape: 1)
        let c = Self.item(Self.rectPath(500, 500), shape: 2)
        let list = RenderList(nodes: [], items: [a, b, c])
        let ra = try #require(a.worldBounds)
        let rb = try #require(b.worldBounds)
        let union = Rect(minX: min(ra.minX, rb.minX), minY: min(ra.minY, rb.minY),
                         maxX: max(ra.maxX, rb.maxX), maxY: max(ra.maxY, rb.maxY))
        #expect(list.worldBounds(of: [a.address, b.address]) == union)
        #expect(list.worldBounds(of: [b.address]) == rb)
    }

    @Test func nonFiniteItemsAreLeftOut() throws {
        var bad = Matrix.identity
        bad.tx = .nan
        let nanMatrix = Self.item(Self.rectPath(10, 10), matrix: bad, shape: 0)
        let infStroke = Self.item(Self.rectPath(10, 10), stroke: Stroke(width: .infinity), shape: 1)
        let good = Self.item(Self.rectPath(10, 10), matrix: .translation(x: 100, y: 0), shape: 2)
        #expect(nanMatrix.worldBounds == nil)
        #expect(infStroke.worldBounds == nil)
        let list = RenderList(nodes: [], items: [nanMatrix, infStroke, good])
        let all = [nanMatrix.address, infStroke.address, good.address]
        #expect(list.worldBounds(of: all) == good.worldBounds)
    }

    /// A finite stroke width can still overflow once the matrix scales it:
    /// 1e308 * 4 is infinite, so the item has no box rather than an infinite one.
    @Test func overflowingStrokeHasNoBox() {
        let item = Self.item(Self.rectPath(10, 10), matrix: .scale(x: 4, y: 4), stroke: Stroke(width: 1e308))
        #expect(item.worldBounds == nil)
    }
}
