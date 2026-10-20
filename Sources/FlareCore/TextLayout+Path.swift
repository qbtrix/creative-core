// TextLayout+Path.swift: type on a path (TE-6). `onPath` places each grapheme
// of a text shape along its `TextOnPath`: the glyph's centre sits on the path
// at the start offset plus its pen x plus half its advance, turned to the
// path's tangent there, the way SVG's `textPath` sets glyphs.
//
// Invariants:
// - a glyph's centre is `startOffset * length + x + advance / 2` along the path
// - flipped walks the path from its end, the tangent reversed
// - an open path drops a glyph whose centre falls outside 0...length; a closed one wraps it
// - the centre lies on the curve itself and the tangent is the curve's own
//   derivative there, not a chord of the flattened polyline
// - bad text, metrics, offset, tolerance or path points throw; nothing traps
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// One grapheme set on a path: its index in the string, its baseline point
/// `position` in the path's coordinates (the layer's space, not an offset
/// from the text's position), and `degrees`, the angle of the path's tangent
/// there from +x, clockwise in y-down document space.
public struct PlacedGlyph: Sendable, Hashable {
    public var index: Int, position: Point, degrees: Double
}

extension TextLayout {
    /// Places `text`'s graphemes along `text.onPath`, flattening the path to
    /// `tolerance`, the maximum distance in points between the flattened path
    /// and the curve; graphemes past the end of an open path are left out.
    /// Each glyph's `position` is its pen point: the centre on the path, moved
    /// back half the advance along the tangent. A path whose last element is
    /// `close` wraps; its contours are measured end to end.
    ///
    /// Throws `ModelError.invalidText` on more than `maxGraphemes` graphemes,
    /// no `onPath`, a non-finite start offset, metrics or paragraph values
    /// `lay` refuses, or a non-finite glyph distance; `GeometryError` for a bad
    /// tolerance, a non-finite path point or length, or more than
    /// `Path.maxMeasurePoints` flattened steps.
    public static func onPath(_ text: TextShape, measured: [GlyphRunMetrics], tolerance: Double) throws -> [PlacedGlyph] {
        guard text.string.dropFirst(maxGraphemes).isEmpty else {
            throw ModelError.invalidText("more than \(maxGraphemes) graphemes; onPath takes at most \(maxGraphemes)")
        }
        guard let spec = text.onPath else { throw ModelError.invalidText("text has no onPath to place along") }
        guard spec.startOffset.isFinite else {
            throw ModelError.invalidText("path start offset \(spec.startOffset) must be finite")
        }
        let style = text.paragraph ?? ParagraphStyle()
        try check(style)
        let (adv, _) = try advances(text.resolvedRuns, measured: measured, tracking: style.tracking)
        let track = try PathTrack(spec.path, tolerance: tolerance)
        let total = track.total
        guard total > 0 else { return [] }
        let flip = spec.flipped
        let closed = spec.path.elements.last == .close
        let s = spec.startOffset * total
        var glyphs: [PlacedGlyph] = [], x = 0.0
        glyphs.reserveCapacity(adv.count)
        for (i, a) in adv.enumerated() {
            defer { x += a }
            var centre = s + x + a / 2
            guard centre.isFinite else { throw ModelError.invalidText("glyph \(i) lies a non-finite distance along the path") }
            if closed { centre -= (centre / total).rounded(.down) * total }
            guard centre >= 0, centre <= total else { continue }
            let (point, ahead) = flip ? track.sample(total - centre, entering: true) : track.sample(centre, entering: false)
            let t = flip ? Point(x: -ahead.x, y: -ahead.y) : ahead
            glyphs.append(PlacedGlyph(index: i, position: Point(x: point.x - t.x * a / 2, y: point.y - t.y * a / 2),
                                      degrees: atan2(t.y, t.x) * 180 / Double.pi))
        }
        return glyphs
    }
}

/// A path flattened into steps that keep their curve and parameter span, so
/// a sample lands on the curve itself with its exact tangent, not on a chord.
private struct PathTrack {
    enum Curve {
        case line(Point, Point), quad(Point, Point, Point), cubic(Point, Point, Point, Point)

        func at(_ t: Double) -> Point {
            switch self {
            case .line(let a, let b): Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            case .quad(let a, let c, let b): quadAt(a, c, b, t)
            case .cubic(let a, let c1, let c2, let b): cubicAt(a, c1, c2, b, t)
            }
        }

        /// The derivative at `t`.
        func velocity(_ t: Double) -> Point {
            let u = 1 - t
            switch self {
            case .line(let a, let b):
                return Point(x: b.x - a.x, y: b.y - a.y)
            case .quad(let a, let c, let b):
                return Point(x: 2 * (u * (c.x - a.x) + t * (b.x - c.x)), y: 2 * (u * (c.y - a.y) + t * (b.y - c.y)))
            case .cubic(let a, let c1, let c2, let b):
                let (w0, w1, w2) = (3 * u * u, 6 * u * t, 3 * t * t)
                return Point(x: w0 * (c1.x - a.x) + w1 * (c2.x - c1.x) + w2 * (b.x - c2.x),
                             y: w0 * (c1.y - a.y) + w1 * (c2.y - c1.y) + w2 * (b.y - c2.y))
            }
        }

        /// Equal parameter steps that keep the curve within `tolerance` of its chords.
        func steps(_ tolerance: Double) -> Int {
            switch self {
            case .line: 1
            case .quad(let a, let c, let b):
                Path.segmentCount((0.25 * norm(a.x - 2 * c.x + b.x, a.y - 2 * c.y + b.y) / tolerance).squareRoot())
            case .cubic(let a, let c1, let c2, let b): Path.cubicSegments(a, c1, c2, b, tolerance: tolerance)
            }
        }
    }

    /// Parameters `t0...t1` of `curve`, from `start` to `end` along the path (`end > start`).
    struct Step { var curve: Curve, t0: Double, t1: Double, start: Double, end: Double }

    var steps: [Step] = [], total = 0.0

    init(_ path: Path, tolerance: Double) throws {
        guard tolerance.isFinite, tolerance > 0 else { throw GeometryError.invalidTolerance }
        var last: Point?, first: Point?, tried = 0
        func add(_ curve: Curve) throws {
            let n = curve.steps(tolerance)
            var p0 = curve.at(0)
            for i in 1...n {
                tried += 1
                guard tried <= Path.maxMeasurePoints else { throw GeometryError.tooComplex(Path.maxMeasurePoints) }
                let t0 = Double(i - 1) / Double(n), t1 = Double(i) / Double(n), p1 = curve.at(t1)
                let length = norm(p1.x - p0.x, p1.y - p0.y)
                guard p0.isFinite, p1.isFinite, length.isFinite, (total + length).isFinite else { throw GeometryError.nonFinite }
                if length > 0 { steps.append(Step(curve: curve, t0: t0, t1: t1, start: total, end: total + length)) }
                total += length
                p0 = p1
            }
        }
        for element in path.elements {
            switch element {
            case .move(let to):
                (first, last) = (to, to)
                continue
            case .close:
                if let from = last, let to = first { try add(.line(from, to)) }
                last = nil
                continue
            default:
                break
            }
            guard let from = last ?? first, let end = element.endPoint else {
                (first, last) = (element.endPoint, element.endPoint)
                continue
            }
            switch element {
            case .line: try add(.line(from, end))
            case .quad(let c, _): try add(.quad(from, c, end))
            case .cubic(let c1, let c2, _): try add(.cubic(from, c1, c2, end))
            case .move, .close: break
            }
            last = end
        }
    }

    /// The point `s` along the path (0...total, total > 0) and the unit
    /// tangent there. At a step boundary it takes the step leaving the point,
    /// or with `entering` the step arriving at it.
    func sample(_ s: Double, entering: Bool) -> (Point, Point) {
        var lo = 0, hi = steps.count - 1
        while lo < hi {
            let mid = entering ? (lo + hi) / 2 : (lo + hi + 1) / 2
            if entering {
                if steps[mid].end >= s { hi = mid } else { lo = mid + 1 }
            } else {
                if steps[mid].start <= s { lo = mid } else { hi = mid - 1 }
            }
        }
        let step = steps[lo]
        let u = Swift.min(Swift.max((s - step.start) / (step.end - step.start), 0), 1)
        let t = step.t0 + (step.t1 - step.t0) * u
        var d = step.curve.velocity(t)
        if !(norm(d.x, d.y) > 0) {
            let a = step.curve.at(step.t0), b = step.curve.at(step.t1)
            d = Point(x: b.x - a.x, y: b.y - a.y)
        }
        let n = norm(d.x, d.y)
        return (step.curve.at(t), Point(x: d.x / n, y: d.y / n))
    }
}
