// MaskContours.swift: a mask's outlines at a coverage level (marching
// squares) and its covered bounds.
// Samples sit at pixel centres, ringed by 0 samples so every outline closes;
// a sample is inside when it is at least `level`. Each cell gives 0 to 2
// segments between interpolated edge crossings (a saddle joins the corners
// its mean sides with), the inside on their left, chained into rings by edge.
// A pass over row flags first lists the mixed cells, so the rest grows with
// the outlines, not the area.
// Invariants: each crossing ends one segment and starts one, so every chain
// closes, and a walk removes each link it follows, so it ends; at most
// `maxContourSegments` segments are kept, so the link tables stay bounded.

extension Mask {
    /// The most segments `contours` builds: 4,000,000, tens of MB of links.
    /// An ordinary shape's outline is about its perimeter in pixels (a disc
    /// filling 4096 x 4096 gives about 13,000), so only noise reaches it.
    public static let maxContourSegments = 4_000_000

    /// The closed outlines where coverage crosses `level`, each a ring of
    /// points whose last joins its first. Outer rings have positive shoelace
    /// area in y-down pixel coordinates (clockwise as seen on screen); holes
    /// negative. A level of 0 or less, above 1, or NaN has none; a ring of
    /// fewer than three points is left out. Throws `RasterError.invalid` once
    /// the outlines pass `maxContourSegments` segments.
    public func contours(level: Float = 0.5) throws -> [[Mask.Point]] {
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
        for index in try mixedCells(level: level) {
            let cx = index % (w + 1) - 1, cy = index / (w + 1) - 1
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
            // A cell adds at most 2 segments, so the tables stop growing just past the cap.
            if starts.count > Self.maxContourSegments {
                throw RasterError.invalid("mask contours: more than \(Self.maxContourSegments) segments")
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

    /// The cells, as (cy + 1)(w + 1) + cx + 1 in row order, whose four corner
    /// samples are not all on one side of `level`: the only cells that add a
    /// segment. One pass over a row of inside flags at a time, so the work
    /// after it grows with the outlines, not the area. Throws as `contours`
    /// once there are more than `maxContourSegments` (each adds a segment).
    private func mixedCells(level: Float) throws -> [Int] {
        let w = width, h = height
        // The ring of samples outside the mask reads 0, inside when 0 >= level.
        let pad: UInt8 = 0 >= level ? 1 : 0
        var cells: [Int] = []
        // Two padded rows of flags: `top` holds sample row y - 1 and `bottom` row y.
        var flags = [UInt8](repeating: pad, count: 2 * (w + 2))
        try storage.withUnsafeBufferPointer { s in
            try flags.withUnsafeMutableBufferPointer { f in
                guard var top = f.baseAddress else { return }
                var bottom = top + (w + 2)
                for y in 0...h {
                    if y == h {
                        bottom.update(repeating: pad, count: w + 2)
                    } else if let row = s.baseAddress.map({ $0 + y * w }) {
                        for x in 0..<w { bottom[x + 1] = row[x] >= level ? 1 : 0 }
                    }
                    for i in 0...w where top[i] != top[i + 1] || bottom[i] != bottom[i + 1] || top[i] != bottom[i] {
                        cells.append(y * (w + 1) + i)
                    }
                    if cells.count > Self.maxContourSegments {
                        throw RasterError.invalid("mask contours: more than \(Self.maxContourSegments) segments")
                    }
                    swap(&top, &bottom)
                }
            }
        }
        return cells
    }

    /// The smallest rectangle holding every pixel with nonzero coverage, or
    /// nil when no pixel has any.
    public var coveredBounds: (x: Int, y: Int, width: Int, height: Int)? {
        coveredRect.map { ($0.x, $0.y, $0.width, $0.height) }
    }
}
