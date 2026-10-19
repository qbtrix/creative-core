// TextLayout.swift: the text-engine contract (TE-1). Runs resolve into styles
// that tile the string (`resolvedRuns`); the platform measures each into
// `GlyphRunMetrics`; `lay` sets them into lines; `FixedAdvances` is the
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
/// grapheme's x (both offsets from the shape's position), and its width
/// without trailing spaces.
public struct LaidLine: Sendable, Hashable {
    public var graphemes: Range<Int>, baseline: Double, x: [Double], width: Double
}

/// A text shape set into lines, and the rect they fill (offsets from the
/// shape's position, like the lines).
public struct TextLayout: Sendable, Hashable {
    public var lines: [LaidLine], bounds: Rect
    /// The most graphemes `lay` and `onPath` accept; more throws.
    public static let maxGraphemes = 100_000

    /// Lays `text` out from `measured`, one metrics per `text.resolvedRuns`:
    /// greedy lines that break after whitespace, after a hyphen and at a
    /// newline (which also adds `paragraphSpacing`), a word wider than the box
    /// breaking by grapheme. Linear in the graphemes. Throws
    /// `ModelError.invalidText` on more than `maxGraphemes` graphemes, metrics
    /// that don't match the runs, or a non-finite or out-of-range paragraph value.
    public static func lay(_ text: TextShape, measured: [GlyphRunMetrics]) throws -> TextLayout {
        let chars = Array(text.string)
        guard chars.count <= maxGraphemes else {
            throw ModelError.invalidText("\(chars.count) graphemes; layout takes at most \(maxGraphemes)")
        }
        let style = text.paragraph ?? ParagraphStyle()
        guard style.lineHeight.isFinite, style.lineHeight >= 0, style.tracking.isFinite,
              style.paragraphSpacing.isFinite, style.boxWidth.map({ $0.isFinite && $0 > 0 }) ?? true else {
            throw ModelError.invalidText("paragraph line height, tracking, spacing and box width must be finite (box > 0)")
        }
        let runs = text.resolvedRuns
        guard measured.count == runs.count else {
            throw ModelError.invalidText("\(measured.count) glyph run metrics for \(runs.count) runs")
        }
        var adv: [Double] = [], runOf: [Int] = []
        adv.reserveCapacity(chars.count)
        runOf.reserveCapacity(chars.count)
        for (r, (run, metrics)) in zip(runs, measured).enumerated() {
            guard metrics.advances.count == run.length else {
                throw ModelError.invalidText("run \(r) has \(metrics.advances.count) advances for \(run.length) graphemes")
            }
            let track = run.tracking + style.tracking
            for a in metrics.advances {
                guard (a + track).isFinite else { throw ModelError.invalidText("run \(r) tracking \(run.tracking) is not finite") }
                adv.append(a + track)
                runOf.append(r)
            }
        }
        guard adv.count == chars.count else { throw ModelError.invalidText("runs do not cover the string") }
        let pieces = breakLines(chars, adv, box: style.boxWidth)
        return place(pieces, chars: chars, adv: adv, runOf: runOf, runs: runs, measured: measured, style: style)
    }

    /// A line before placement: graphemes `start ..< end`, ink up to `inkEnd`
    /// (trailing whitespace after), and its width without and with that whitespace.
    struct Piece {
        var start: Int, end: Int, inkEnd: Int, ink = 0.0, full = 0.0, endsParagraph = false
        init(at start: Int) { (self.start, self.end, self.inkEnd) = (start, start, start) }
    }

    /// Greedy line breaking over words: a word is non-whitespace up to and
    /// including a hyphen, then the whitespace after it.
    static func breakLines(_ chars: [Character], _ adv: [Double], box: Double?) -> [Piece] {
        let slop = 1e-9
        var pieces: [Piece] = [], line = Piece(at: 0), i = 0
        while i < chars.count {
            var j = i, inkW = 0.0
            while j < chars.count, !chars[j].isWhitespace {
                inkW += adv[j]
                j += 1
                if chars[j - 1] == "-" { break }
            }
            if let box, inkW > 0, line.end > line.start, line.full + inkW > box + slop {
                pieces.append(line)
                line = Piece(at: i)
            }
            let byGrapheme = box.map { inkW > $0 + slop } ?? false
            for k in i..<j {
                if byGrapheme, let box, line.end > line.start, line.full + adv[k] > box + slop {
                    pieces.append(line)
                    line = Piece(at: k)
                }
                line.full += adv[k]
                (line.ink, line.end, line.inkEnd) = (line.full, k + 1, k + 1)
            }
            while j < chars.count, chars[j].isWhitespace {
                line.full += adv[j]
                line.end = j + 1
                j += 1
                if chars[j - 1].isNewline {
                    line.endsParagraph = true
                    pieces.append(line)
                    line = Piece(at: j)
                    break
                }
            }
            i = j
        }
        if line.end > line.start || chars.last?.isNewline == true {
            line.endsParagraph = true
            pieces.append(line)
        }
        return pieces
    }

    /// Sets each piece's baseline, aligned x and width, and the bounds.
    static func place(_ pieces: [Piece], chars: [Character], adv: [Double], runOf: [Int], runs: [ResolvedRun],
                      measured: [GlyphRunMetrics], style: ParagraphStyle) -> TextLayout {
        let container = style.boxWidth ?? pieces.reduce(0) { max($0, $1.ink) }
        var lines: [LaidLine] = [], y = 0.0, bottom = 0.0, minX = Double.infinity, maxX = -Double.infinity
        for (n, p) in pieces.enumerated() {
            // An empty line (after a final newline) takes the newline's run.
            let first = p.end > p.start ? p.start : p.start - 1
            var ascent = 0.0, descent = 0.0
            if runOf.indices.contains(first) {
                var r = runOf[first]
                while r < runs.count, r < measured.count, runs[r].start < max(p.end, first + 1) {
                    (ascent, descent) = (max(ascent, measured[r].ascent), max(descent, measured[r].descent))
                    r += 1
                }
            }
            let gap = n == 0 ? 0 : style.lineHeight * (ascent + descent)
            let spacing = n > 0 && pieces[n - 1].endsParagraph ? style.paragraphSpacing : 0
            y = n == 0 ? ascent : y + gap + spacing
            bottom = y + descent
            let slack = max(0, container - p.ink)
            var inner = 0
            for k in p.start..<p.inkEnd where chars[k].isWhitespace { inner += 1 }
            let justify = style.alignment == .justified && style.boxWidth != nil && !p.endsParagraph && inner > 0
            let extra = justify ? slack / Double(inner) : 0
            let lead = style.alignment == .center ? slack / 2 : style.alignment == .trailing ? slack : 0
            var cur = lead, x: [Double] = []
            x.reserveCapacity(p.end - p.start)
            for k in p.start..<p.end {
                x.append(cur)
                cur += adv[k]
                if k < p.inkEnd, chars[k].isWhitespace { cur += extra }
            }
            let width = p.ink + extra * Double(inner)
            (minX, maxX) = (min(minX, lead), max(maxX, lead + width))
            lines.append(LaidLine(graphemes: p.start..<p.end, baseline: y, x: x, width: width))
        }
        guard !lines.isEmpty else { return TextLayout(lines: [], bounds: Rect(minX: 0, minY: 0, maxX: 0, maxY: 0)) }
        return TextLayout(lines: lines, bounds: Rect(minX: minX, minY: 0, maxX: maxX, maxY: bottom))
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
