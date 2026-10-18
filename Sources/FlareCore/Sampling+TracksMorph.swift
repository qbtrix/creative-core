// Sampling+TracksMorph.swift: a shape track's path at a frame (AP-6), morphed
// anchor by anchor between the two keys around the frame with the left key's
// easing. Invariants: a key's own frame draws exactly that key (t is 0 there,
// and a + (b - a) * 0 is a); a line's missing handles count as the points it
// joins, so a line morphs into a curve smoothly; keys whose elements do not
// pair up (a file AP-4's compatibility rule never saw) hold the left key.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Layer {
    /// The path at `frame` of the shape at index `shape` into the layer's
    /// `shapes` (the track's `shapeIndex`, not a `Shape` value), morphed anchor
    /// by anchor between its keys with each key's easing; the end keys hold
    /// outside the track. nil when the shape has no track or `frame` is not
    /// finite (use the static path).
    public func sampledPath(shape: Int, at frame: Double) -> Path? {
        guard frame.isFinite, let keys = shapeTracks.first(where: { $0.shapeIndex == shape })?.keys,
              let first = keys.first, let last = keys.last else { return nil }
        if frame <= Double(first.frame) { return first.path }
        if frame >= Double(last.frame) { return last.path }
        // The first key after `frame`. first.frame < frame < last.frame, so it is in 1..<count.
        var lo = 1
        var hi = keys.count - 1
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if frame < Double(keys[mid].frame) { hi = mid } else { lo = mid + 1 }
        }
        guard hi > 0, hi < keys.count else { return last.path }
        let (a, b) = (keys[hi - 1], keys[hi])
        let span = Double(b.frame) - Double(a.frame)
        guard span > 0 else { return b.path }
        let t = a.easing.value(at: (frame - Double(a.frame)) / span)
        return Path.morph(a.path, b.path, t) ?? a.path
    }
}

extension Path {
    /// `a` moved toward `b` by `t`, element by element, or nil when their
    /// elements do not pair up (a different count, or a move, close or
    /// drawing element against another kind).
    static func morph(_ a: Path, _ b: Path, _ t: Double) -> Path? {
        guard a.elements.count == b.elements.count else { return nil }
        func lerp(_ p: Point, _ q: Point) -> Point { Point(x: p.x + (q.x - p.x) * t, y: p.y + (q.y - p.y) * t) }
        var pens = (MorphPen(), MorphPen())
        var out: [PathElement] = []
        out.reserveCapacity(a.elements.count)
        for (ea, eb) in zip(a.elements, b.elements) {
            let (p0a, p0b) = (pens.0.current, pens.1.current)
            pens.0.advance(ea)
            pens.1.advance(eb)
            switch (ea, eb) {
            case (.move(let pa), .move(let pb)): out.append(.move(to: lerp(pa, pb)))
            case (.close, .close): out.append(.close)
            case (.line(let pa), .line(let pb)): out.append(.line(to: lerp(pa, pb)))
            case (.quad(let ca, let pa), .quad(let cb, let pb)): out.append(.quad(control: lerp(ca, cb), to: lerp(pa, pb)))
            default:
                guard let (ha, pa) = ea.cubicHandles(from: p0a), let (hb, pb) = eb.cubicHandles(from: p0b) else { return nil }
                out.append(.cubic(control1: lerp(ha.0, hb.0), control2: lerp(ha.1, hb.1), to: lerp(pa, pb)))
            }
        }
        return Path(elements: out)
    }
}

/// The pen of one side of a morph: where the next segment starts.
private struct MorphPen {
    var start: Point?
    var current: Point?
    mutating func advance(_ element: PathElement) {
        switch element {
        case .move(let to): (start, current) = (to, to)
        case .close: current = start
        case .line(let to), .quad(_, let to), .cubic(_, _, let to): current = to
        }
    }
}

extension PathElement {
    /// A drawing element as a cubic from `p0` (its end when there is no pen):
    /// its handles and end. A line's handles are the points it joins and a
    /// quad's are its exact cubic ones. nil for move and close.
    fileprivate func cubicHandles(from p0: Point?) -> ((Point, Point), Point)? {
        switch self {
        case .line(let to):
            return ((p0 ?? to, to), to)
        case .quad(let c, let to):
            // Each handle sits two thirds of the way from its end point to the control.
            let handle = { (p: Point) in Point(x: p.x + 2 * (c.x - p.x) / 3, y: p.y + 2 * (c.y - p.y) / 3) }
            return ((handle(p0 ?? to), handle(to)), to)
        case .cubic(let c1, let c2, let to):
            return ((c1, c2), to)
        case .move, .close:
            return nil
        }
    }
}
