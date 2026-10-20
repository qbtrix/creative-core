// TextBudgetTests.swift: the text-engine budgets (TE-9). Laying out the
// 10,000-grapheme paragraph (TextFixtures.longParagraph) in a 300-point box
// takes at most 4 ms, one keystroke in a long paragraph; placing 500 glyphs
// on the walk's circle takes at most 2 ms. The packet's budgets are release,
// reported: a debug build, which `scripts/ci` runs, times one call and only
// prints; an optimized build prints the median of `runs` after one untimed
// call and records a miss as a known issue, so the miss shows in the results
// without disabling the check or flaking the gate. Inputs are the packet's
// sizes in both builds. Lines read `budget <row>: <ms> ms (budget <ms> ms)`.
// Run: swift test -c release -Xswiftc -enable-testing --filter TextBudgetTests
import FlareCore
import Foundation
import Testing

#if DEBUG
private let optimized = false
#else
private let optimized = true
#endif

/// Debug times one run: it only reports, and its loops are slow.
private let runs = optimized ? 5 : 1

/// Serialized, so no two timed runs share cores.
@Suite(.serialized) struct TextBudgetTests {
    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1e3 + Double(d.components.attoseconds) / 1e15
    }

    /// Runs `body` once untimed (optimized builds), prints the median of
    /// `runs` timings and, optimized, records a time over `budget` as a known issue.
    static func report<T>(_ row: String, budget: Duration, _ body: () throws -> T) throws -> T {
        let clock = ContinuousClock()
        var last: T?
        if optimized { last = try body() }
        var wall: [Duration] = []
        for _ in 0..<runs { wall.append(try clock.measure { last = try body() }) }
        let result = try #require(last, "\(row) did not run")
        let time = wall.sorted()[runs / 2]
        let shown = (ms(time) * 1000).rounded() / 1000
        print("budget \(row): \(shown) ms (\(optimized ? "" : "report only, debug; ")budget \(ms(budget)) ms)")
        if optimized && time > budget {
            withKnownIssue("text budget missed, reported not gated") {
                Issue.record("\(row): median \(shown) ms over \(ms(budget)) ms")
            }
        }
        return result
    }

    @Test func layParagraph() throws {
        let text = TextFixtures.text(TextFixtures.longParagraph, paragraph: ParagraphStyle(boxWidth: 300))
        let measured = FixedAdvances.measure(text)
        let laid = try Self.report("lay out 10,000 graphemes", budget: .milliseconds(4)) {
            try TextLayout.lay(text, measured: measured)
        }
        // 12 per grapheme: five words ("word " × 5 = 25 graphemes) fill a 300 box.
        #expect(laid.lines.count == 400 && laid.lines.last?.graphemes.upperBound == 10_000)
    }

    @Test func glyphsOnPath() throws {
        let string = String(repeating: "glyph", count: 100)
        let text = TextFixtures.text(string, onPath: TextOnPath(path: TextWalkTests.circle(), startOffset: 0.25))
        let measured = FixedAdvances.measure(text)
        let glyphs = try Self.report("500 glyphs on a path", budget: .milliseconds(2)) {
            try TextLayout.onPath(text, measured: measured, tolerance: 0.01)
        }
        // The closed circle wraps, so every glyph is placed.
        #expect(glyphs.map(\.index) == Array(0..<500))
    }
}
