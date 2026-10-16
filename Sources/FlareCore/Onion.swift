// Onion.swift: the frames an onion skin shows around the playhead.
//
// A pure query beside `Timeline.playbackFrame`: it reads no layer, only the
// owner's `durationFrames` (a scene's, or a symbol's when editing in place).
// It never throws: negative counts count as 0, frames outside
// `0..<durationFrames` are dropped, and the window edges use saturating
// arithmetic so no count or frame overflows Int.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Timeline {
    /// The frames an onion skin shows around `frame`: up to `before` frames
    /// before it and `after` after it, ascending, without `frame` itself,
    /// clamped to `0..<durationFrames` (frames past an edge are dropped).
    /// Negative counts count as 0.
    public static func onionFrames(at frame: Int, before: Int, after: Int, durationFrames: Int) -> [Int] {
        guard durationFrames > 0 else { return [] }
        let back = frame.subtractingReportingOverflow(max(before, 0))
        let ahead = frame.addingReportingOverflow(max(after, 0))
        let lo = max(0, back.overflow ? Int.min : back.partialValue)
        let hi = min(durationFrames - 1, ahead.overflow ? Int.max : ahead.partialValue)
        guard lo <= hi else { return [] }
        return (lo...hi).filter { $0 != frame }
    }
}
