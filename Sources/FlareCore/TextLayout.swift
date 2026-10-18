// TextLayout.swift: the text-engine contract (TE-1). Runs resolve into styles
// that tile the string (`resolvedRuns`); the platform measures each into
// `GlyphRunMetrics`; `lay` (stub until TE-5) sets lines; `FixedAdvances` is the
// platform-free measurer. Offsets count graphemes, never UTF-16 units or bytes.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// One style over graphemes `start ..< start + length` of a text shape, every
/// field filled in: a run's own value where it sets one, else the shape's.
/// Weight is 400, italic false, and tracking and baseline shift 0 where no run sets them.
public struct ResolvedRun: Sendable, Hashable {
    public var start: Int, length: Int, fontFamily: String, fontSize: Double
    public var weight: Int, italic: Bool, fill: Fill, tracking: Double, baselineShift: Double

    public init(start: Int, length: Int, fontFamily: String, fontSize: Double, weight: Int = 400,
                italic: Bool = false, fill: Fill, tracking: Double = 0, baselineShift: Double = 0) {
        (self.start, self.length, self.fontFamily, self.fontSize, self.weight) = (start, length, fontFamily, fontSize, weight)
        (self.italic, self.fill, self.tracking, self.baselineShift) = (italic, fill, tracking, baselineShift)
    }
}

extension TextShape {
    /// The shape's styles as runs that tile its string in order, with no gap
    /// or overlap: each of `runs` (clipped to the string and to what earlier
    /// runs cover) with its nil fields taken from the shape, and every gap
    /// between them as a run in the shape's own style. Empty for an empty string.
    public var resolvedRuns: [ResolvedRun] {
        let count = string.count
        let plain = { (start: Int, end: Int) in
            ResolvedRun(start: start, length: end - start, fontFamily: fontFamily, fontSize: fontSize, fill: fill)
        }
        var out: [ResolvedRun] = []
        var cursor = 0
        for run in runs.sorted(by: { $0.start < $1.start }) {
            let start = max(run.start, cursor)
            let (end, overflow) = run.start.addingReportingOverflow(run.length)
            let stop = overflow ? count : min(end, count)
            guard start < stop else { continue }
            if cursor < start { out.append(plain(cursor, start)) }
            out.append(ResolvedRun(
                start: start, length: stop - start, fontFamily: run.fontFamily ?? fontFamily,
                fontSize: run.fontSize ?? fontSize, weight: run.weight ?? 400, italic: run.italic ?? false,
                fill: run.fill ?? fill, tracking: run.tracking ?? 0, baselineShift: run.baselineShift ?? 0))
            cursor = stop
        }
        if cursor < count { out.append(plain(cursor, count)) }
        return out
    }
}

/// What the platform measured for one resolved run: one advance per grapheme
/// (points) and the run's font ascent and descent (points, both positive).
public struct GlyphRunMetrics: Sendable, Hashable {
    public var advances: [Double], ascent: Double, descent: Double

    /// Throws `ModelError.invalidText` when any value is NaN, infinite or negative.
    public init(advances: [Double], ascent: Double, descent: Double) throws {
        for (i, a) in advances.enumerated() where !(a.isFinite && a >= 0) {
            throw ModelError.invalidText("glyph advance \(i) is \(a); advances must be finite and >= 0")
        }
        guard ascent.isFinite, ascent >= 0, descent.isFinite, descent >= 0 else {
            throw ModelError.invalidText("ascent \(ascent) and descent \(descent) must be finite and >= 0")
        }
        (self.advances, self.ascent, self.descent) = (advances, ascent, descent)
    }
}

/// One laid-out line: the graphemes it holds, its baseline y, each
/// grapheme's x (from the shape's position), and its width without trailing spaces.
public struct LaidLine: Sendable, Hashable {
    public var graphemes: Range<Int>, baseline: Double, x: [Double], width: Double
}

/// A text shape set into lines, and the rect they fill.
public struct TextLayout: Sendable, Hashable {
    public var lines: [LaidLine], bounds: Rect
    /// The most graphemes `lay` and `onPath` accept; more throws.
    public static let maxGraphemes = 100_000

    /// Lays `text` out from `measured`, one metrics per `text.resolvedRuns`.
    /// Stub: throws `CommandError.notBuilt` until TE-5 gives it a body.
    public static func lay(_ text: TextShape, measured: [GlyphRunMetrics]) throws -> TextLayout {
        throw notBuilt("TextLayout.lay")
    }

    /// What a text-engine stub named `name` throws until its task builds it.
    static func notBuilt(_ name: String) -> CommandError { .notBuilt("\(name) is not built yet (text-engine)") }
}

/// The platform-free measurer: every grapheme advances 0.5 em, and each run's
/// ascent is 0.8 em and descent 0.2 em, an em being the run's font size
/// (0 when that size is not finite and positive).
public enum FixedAdvances {
    /// One metrics per `text.resolvedRuns`, in order.
    public static func measure(_ text: TextShape) -> [GlyphRunMetrics] {
        text.resolvedRuns.compactMap { run in
            let em = run.fontSize.isFinite && run.fontSize > 0 ? run.fontSize : 0
            return try? GlyphRunMetrics(advances: Array(repeating: 0.5 * em, count: run.length),
                                        ascent: 0.8 * em, descent: 0.2 * em)
        }
    }
}
