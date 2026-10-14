// Marquee.swift: the items of a render list a scene-space rect touches.
//
// Items are returned in paint order, each address once. Locked and text items
// are skipped; hidden layers are already absent from the list. An item counts
// when its stroke-inclusive `worldBounds` meets the rect, edges included, so a
// rect over only the outer half of a stroke still picks the item. A rect with
// a non-finite edge or no area picks nothing. An item with an outline but no
// finite box (its stroke width, or that width scaled, is not finite) has a
// stroke with no finite reach, so every rect that passes picks it: a nil box
// never hides an item.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension RenderList {
    /// Unlocked, non-text items whose world bounds (with stroke) intersect
    /// `rect`, in paint order, each address once. A rect with a non-finite
    /// edge, or zero width or height once normalised, gives [].
    public func marquee(_ rect: Rect) -> [RenderAddress] {
        guard let area = rect.normalized else { return [] }
        guard area.maxX - area.minX > 0, area.maxY - area.minY > 0 else { return [] }
        var seen: Set<RenderAddress> = []
        var picked: [RenderAddress] = []
        for item in items where !item.isLocked && !item.isText {
            guard item.sceneOutlineBounds != nil else { continue }
            if let box = item.worldBounds, !box.meets(area) { continue }
            if seen.insert(item.address).inserted { picked.append(item.address) }
        }
        return picked
    }
}

extension Rect {
    /// Whether the two closed boxes share a point; touching edges count.
    fileprivate func meets(_ other: Rect) -> Bool {
        minX <= other.maxX && other.minX <= maxX && minY <= other.maxY && other.minY <= maxY
    }
}
