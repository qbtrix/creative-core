// HitQuery.swift: the topmost item of a render list under a scene-space point.
//
// Items are walked from the last painted to the first, so the one on top
// wins. Locked and text items are skipped; hidden layers are already absent
// from the list. At tolerance 0 the test is exactly `Shape.hits` in the
// item's local space, so it agrees with `Layer.hits`. A positive tolerance
// (the pointer slop in scene units: screen points divided by the zoom) also
// accepts a point within `tolerance` plus the scaled half stroke of the
// outline in scene space. Before the exact
// test, an item whose `worldBounds` widened by `tolerance` misses the point is
// rejected; that box holds everything the exact test can accept, so the
// result is the same, only cheaper for the many items far from the pointer.
// An item with no finite box (a stroke whose scaled width overflows) is never
// rejected by the prefilter; the exact test decides.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension RenderList {
    /// The topmost unlocked, non-text item under `point` (scene space), with
    /// `tolerance` added to the stroke reach and to the fill edge.
    /// `tolerance` is in scene units: pass the pointer slop in screen points
    /// divided by the zoom. `rule` is the fill rule for the inside test (the
    /// exporters fill with nonzero). A negative or non-finite tolerance gives
    /// nil; an item whose matrix can't be inverted is skipped.
    public func hit(_ point: Point, tolerance: Double = 0, rule: FillRule = .nonZero) -> RenderAddress? {
        guard tolerance.isFinite, tolerance >= 0 else { return nil }
        for item in items.reversed() where !item.isLocked && !item.isText {
            if let box = item.worldBounds, !box.contains(point, widenedBy: tolerance) { continue }
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
        let halfStroke = sceneHalfStroke ?? 0
        let reach = tolerance + halfStroke
        guard reach.isFinite else { return false }
        return outline.transformed(by: matrix).isWithin(reach, of: point, flatness: max(tolerance / 8, 1e-3))
    }
}

extension Rect {
    /// Whether `point` lies in the rect grown by `margin` on every side,
    /// edges included.
    fileprivate func contains(_ point: Point, widenedBy margin: Double) -> Bool {
        point.x >= minX - margin && point.x <= maxX + margin && point.y >= minY - margin && point.y <= maxY + margin
    }
}
