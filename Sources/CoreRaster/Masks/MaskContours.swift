// MaskContours.swift: a mask's outlines at a coverage level (marching
// squares) and its covered bounds.
// Samples sit at pixel centres, ringed by 0 samples so every outline closes;
// a sample is inside when it is at least `level`. Each cell gives 0 to 2
// segments between interpolated edge crossings (a saddle joins the corners
// its mean sides with), the inside on their left, chained into rings by edge.
// Invariants: each crossing ends one segment and starts one, so every chain
// closes, and a walk removes each link it follows, so it ends.

extension Mask {
    /// The closed outlines where coverage crosses `level`, each a ring of
    /// points whose last joins its first. Outer outlines run counter-clockwise
    /// in pixel coordinates (positive shoelace area; clockwise on a y-down
    /// screen), holes the other way. A level of 0 or less, above 1, or NaN
    /// has none; a ring of fewer than three points is left out.
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
                let v0 = value(cx + 1, cy), v1 = value(cx + 1, cy + 1), v2 = value(cx, cy + 1), v3 = value(cx, cy)
                // Bit k of `cell` is set when corner k is inside.
                let cell = (v0 >= level ? 1 : 0) | (v1 >= level ? 2 : 0) | (v2 >= level ? 4 : 0) | (v3 >= level ? 8 : 0)
                guard cell != 0, cell != 15 else { continue }
                func inside(_ k: Int) -> Bool { cell & (1 << k) != 0 }
                func edge(_ k: Int) -> (Int, Int, Bool) {
                    switch k {
                    case 0: return (cx, cy, false)
                    case 1: return (cx + 1, cy, true)
                    case 2: return (cx, cy + 1, false)
                    default: return (cx, cy, true)
                    }
                }
                // From edge a to edge b the corner a (the first after a) is on the right,
                // so an inside corner reverses the segment.
                func segment(_ a: Int, _ b: Int) {
                    let (from, to) = inside(a) ? (b, a) : (a, b)
                    let (fx, fy, fv) = edge(from), (tx, ty, tv) = edge(to)
                    let start = key(fx, fy, vertical: fv), end = key(tx, ty, vertical: tv)
                    next[start] = end
                    starts.append(start)
                    if points[start] == nil { points[start] = crossing(fx, fy, vertical: fv) }
                    if points[end] == nil { points[end] = crossing(tx, ty, vertical: tv) }
                }
                if cell == 5 || cell == 10 {
                    // A saddle: a centre on corner 0's side cuts off corners 1 and 3, else 0 and 2.
                    let centerInside = (v0 + v1 + v2 + v3) / 4 >= level
                    if centerInside == inside(0) { segment(1, 2); segment(3, 0) } else { segment(0, 1); segment(2, 3) }
                } else {
                    // Exactly two edges cross; join them in edge order.
                    var first = -1
                    for k in 0..<4 where inside((k + 3) % 4) != inside(k) {
                        if first < 0 { first = k } else { segment(first, k) }
                    }
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
