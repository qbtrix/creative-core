// MaskContours.swift: a mask's outlines at a coverage level (marching
// squares) and its covered bounds.
// Samples sit at pixel centres (x + 0.5, y + 0.5); a ring of 0 samples
// around the mask closes every outline. A sample is inside when its value is
// at least `level`. Each cell between four samples gives 0, 1 or 2 segments
// whose ends lie on the cell edges an outline crosses, placed by linear
// interpolation; a saddle (diagonal corners inside, the others out) joins the
// pair its mean sides with. Each segment runs with the inside on its left in
// the mask's coordinates, so an outer outline runs counter-clockwise (positive
// shoelace area: on screen, with y down, it reads clockwise) and a hole the
// other way. Segments meet at shared edge crossings, keyed by edge, and are
// chained into closed rings.
// Invariants: every edge crossing ends one segment and starts one, so each
// chain closes; a walk removes the links it follows, so the walks take at
// most one step per segment, at most twice the (width + 1) x (height + 1)
// cells.

extension Mask {
    /// The closed outlines where coverage crosses `level`, each a ring of
    /// points (the last joins back to the first, not repeated). Outer
    /// outlines run counter-clockwise in pixel coordinates (positive
    /// shoelace area) and holes clockwise. Rings come in scan order of their
    /// first segment. A level of 0 or less, above 1, or NaN has no outlines;
    /// an outline that collapses to fewer than three points (a lone pixel
    /// exactly at the level) is left out.
    public func contours(level: Float = 0.5) -> [[Mask.Point]] {
        let w = width, h = height
        func value(_ x: Int, _ y: Int) -> Float {
            x >= 0 && x < w && y >= 0 && y < h ? storage[y * w + x] : 0
        }
        // Edge keys: the horizontal edge from sample (x, y) to (x + 1, y) and the
        // vertical edge from (x, y) to (x, y + 1), for x in -1...w, y in -1...h.
        func key(_ x: Int, _ y: Int, vertical: Bool) -> Int {
            2 * ((y + 1) * (w + 2) + x + 1) + (vertical ? 1 : 0)
        }
        func crossing(_ x: Int, _ y: Int, vertical: Bool) -> Mask.Point {
            let p = value(x, y), q = vertical ? value(x, y + 1) : value(x + 1, y)
            let t = Double((level - p) / (q - p))
            return vertical ? Mask.Point(x: Double(x) + 0.5, y: Double(y) + 0.5 + t)
                            : Mask.Point(x: Double(x) + 0.5 + t, y: Double(y) + 0.5)
        }
        var next: [Int: Int] = [:], points: [Int: Mask.Point] = [:], starts: [Int] = []
        for cy in -1..<h {
            for cx in -1..<w {
                // Corners k = 0...3 are top-right, bottom-right, bottom-left, top-left;
                // edge k (top, right, bottom, left) runs between corners k - 1 and k.
                let v = [value(cx + 1, cy), value(cx + 1, cy + 1), value(cx, cy + 1), value(cx, cy)]
                let inside = v.map { $0 >= level }
                guard inside.contains(true), inside.contains(false) else { continue }
                let edges = [(cx, cy, false), (cx + 1, cy, true), (cx, cy + 1, false), (cx, cy, true)]
                let crossed = (0..<4).filter { inside[($0 + 3) % 4] != inside[$0] }
                var pairs: [(Int, Int)]
                if crossed.count == 2 {
                    pairs = [(crossed[0], crossed[1])]
                } else {
                    // A saddle: when the centre sides with corners 0 and 2 they join,
                    // so corners 1 and 3 are cut off, else 0 and 2 are.
                    let centerInside = v.reduce(0, +) / 4 >= level
                    pairs = centerInside == inside[0] ? [(1, 2), (3, 0)] : [(0, 1), (2, 3)]
                }
                // From edge a to edge b the corner a (the first after a) is on the right,
                // so an inside corner reverses the segment.
                for (a, b) in pairs {
                    let (from, to) = inside[a] ? (b, a) : (a, b)
                    let (fx, fy, fv) = edges[from], (tx, ty, tv) = edges[to]
                    let start = key(fx, fy, vertical: fv), end = key(tx, ty, vertical: tv)
                    next[start] = end
                    starts.append(start)
                    if points[start] == nil { points[start] = crossing(fx, fy, vertical: fv) }
                    if points[end] == nil { points[end] = crossing(tx, ty, vertical: tv) }
                }
            }
        }
        var rings: [[Mask.Point]] = []
        for first in starts where next[first] != nil {
            var ring: [Mask.Point] = [], edge = first
            while let link = next.removeValue(forKey: edge) {
                if let p = points[edge], p != ring.last { ring.append(p) }
                edge = link
            }
            if ring.count > 1, ring.first == ring.last { ring.removeLast() }
            if ring.count >= 3 { rings.append(ring) }
        }
        return rings
    }

    /// The smallest rectangle holding every pixel with nonzero coverage, or
    /// nil when no pixel has any.
    public var coveredBounds: (x: Int, y: Int, width: Int, height: Int)? {
        coveredRect.map { ($0.x, $0.y, $0.width, $0.height) }
    }
}
