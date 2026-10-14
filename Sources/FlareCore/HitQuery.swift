// HitQuery.swift: the topmost item of a render list under a scene-space point.
//
// Items are walked from the last painted to the first, so the one on top
// wins. Locked and text items are skipped; hidden layers are already absent
// from the list. At tolerance 0 the test is exactly `Shape.hits` in the
// item's local space, so it agrees with `Layer.hits`. A positive tolerance
// (the zoom slop of a pointer) also accepts a point within `tolerance` plus
// the scaled half stroke of the outline in scene space. Before the exact
// test, an item whose `worldBounds` widened by `tolerance` misses the point is
// rejected; that box holds everything the exact test can accept, so the
// result is the same, only cheaper for the many items far from the pointer.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension RenderList {
    /// The topmost unlocked, non-text item under `point` (scene space), with
    /// `tolerance` added to the stroke reach and to the fill edge. A negative
    /// or non-finite tolerance gives nil; an item whose matrix can't be
    /// inverted is skipped.
    public func hit(_ point: Point, tolerance: Double = 0, rule: FillRule = .nonZero) -> RenderAddress? {
        guard tolerance.isFinite, tolerance >= 0 else { return nil }
        for item in items.reversed() where !item.isLocked && !item.isText {
            guard let box = item.worldBounds, box.contains(point, widenedBy: tolerance) else { continue }
            guard let inverse = try? item.matrix.inverted() else { continue }
            let shape = Shape(points: [], path: item.outline, stroke: item.stroke)
            if shape.hits(inverse.apply(point), rule: rule) { return item.address }
            if tolerance > 0, item.isNear(point, tolerance: tolerance) { return item.address }
        }
        return nil
    }
}

extension RenderItem {
    /// Whether `point` is within `tolerance` plus the scaled half stroke of
    /// the outline drawn in scene space.
    fileprivate func isNear(_ point: Point, tolerance: Double) -> Bool {
        var halfStroke = 0.0
        if let width = stroke?.width, width.isFinite, width > 0 { halfStroke = width / 2 * scale(of: matrix) }
        let reach = tolerance + halfStroke
        guard reach.isFinite,
              let lines = try? outline.transformed(by: matrix).flattened(tolerance: max(tolerance / 8, 1e-3)) else {
            return false
        }
        for line in lines {
            for (a, b) in zip(line, line.dropFirst()) where distance(point, a, b) <= reach { return true }
        }
        return false
    }
}

extension Rect {
    /// Whether `point` lies in the rect grown by `margin` on every side,
    /// edges included.
    fileprivate func contains(_ point: Point, widenedBy margin: Double) -> Bool {
        point.x >= minX - margin && point.x <= maxX + margin && point.y >= minY - margin && point.y <= maxY + margin
    }
}

/// The larger axis scale of `m`, so a scaled stroke reach is never short.
private func scale(of m: Matrix) -> Double {
    max(m.a * m.a + m.b * m.b, m.c * m.c + m.d * m.d).squareRoot()
}
