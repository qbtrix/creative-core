// WorldBounds.swift: scene-space boxes of render items, stroke included.
//
// An item's box is the tight `Path.bounds` of its outline mapped into scene
// space, widened on every side by half the stroke width times the matrix's
// larger axis scale, so the box never clips the painted stroke. Text items
// have no outline and no box. An item whose matrix or stroke width is not
// finite has no box either, rather than a NaN or infinite one.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Matrix {
    /// How much the matrix stretches its longer axis: sqrt(max(a² + b², c² + d²)).
    /// A stroke of width w paints at most w * maxAxisScale wide in scene space.
    var maxAxisScale: Double {
        (Swift.max(a * a + b * b, c * c + d * d)).squareRoot()
    }

    fileprivate var isFinite: Bool {
        [a, b, c, d, tx, ty].allSatisfy(\.isFinite)
    }
}

extension RenderItem {
    /// The item's scene-space box, stroke included; nil for text, for an empty
    /// outline, and for a non-finite matrix or stroke width. A nil box means
    /// "no finite box", never "nothing to hit": callers must not skip on it.
    public var worldBounds: Rect? {
        guard var box = sceneOutlineBounds, let half = sceneHalfStroke else { return nil }
        box.minX -= half
        box.minY -= half
        box.maxX += half
        box.maxY += half
        return box
    }

    /// The scene-space box of the outline alone, no stroke; nil for text, for
    /// an empty outline and for a non-finite matrix.
    var sceneOutlineBounds: Rect? {
        guard !isText, matrix.isFinite else { return nil }
        return outline.transformed(by: matrix).bounds
    }

    /// Half the stroke width in scene space: the width times the matrix's
    /// larger axis scale, halved. 0 with no stroke or a negative width; nil
    /// when the width or the result is not finite. `worldBounds` and the
    /// tolerance reach of `RenderList.hit` both use it, so the hit prefilter
    /// box always holds the reach the exact test measures.
    var sceneHalfStroke: Double? {
        let width = stroke?.width ?? 0
        guard width.isFinite else { return nil }
        let half = Swift.max(width, 0) * matrix.maxAxisScale / 2
        guard half.isFinite else { return nil }
        return half
    }
}

extension RenderList {
    /// The union of the boxes of the items at `addresses`; nil when none of
    /// them has a box (an empty list, text only, or addresses not in the list).
    public func worldBounds(of addresses: [RenderAddress]) -> Rect? {
        let wanted = Set(addresses)
        var corners: [Point] = []
        for item in items where wanted.contains(item.address) {
            guard let box = item.worldBounds else { continue }
            corners.append(Point(x: box.minX, y: box.minY))
            corners.append(Point(x: box.maxX, y: box.maxY))
        }
        return Rect(enclosing: corners)
    }
}
