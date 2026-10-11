// Symbols.swift: how an instance maps the host timeline onto its symbol's
// own timeline. Values may come from files, so all arithmetic is
// overflow-safe and never traps.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Instance {
    /// The symbol frame to show when the host timeline is `parentFrame`
    /// frames past the instance's start.
    ///
    /// - `loop` starts at `firstFrame` and wraps into `0..<symbolDuration`.
    /// - `playOnce` starts at `firstFrame` and clamps to `0...symbolDuration - 1`.
    /// - `singleFrame` always returns `firstFrame`.
    ///
    /// A symbol with no frames (`symbolDuration <= 0`) shows frame 0 in
    /// `loop` and `playOnce`.
    public func localFrame(parentFrame: Int, symbolDuration: Int) -> Int {
        switch loop {
        case .singleFrame:
            return firstFrame
        case .loop:
            guard symbolDuration > 0 else { return 0 }
            // Each remainder is in -(d-1)...(d-1), so the sum cannot overflow.
            let wrapped = (firstFrame % symbolDuration + parentFrame % symbolDuration) % symbolDuration
            return wrapped < 0 ? wrapped + symbolDuration : wrapped
        case .playOnce:
            guard symbolDuration > 0 else { return 0 }
            let (sum, overflow) = firstFrame.addingReportingOverflow(parentFrame)
            let frame = overflow ? (parentFrame > 0 ? Int.max : Int.min) : sum
            return min(max(frame, 0), symbolDuration - 1)
        }
    }
}
