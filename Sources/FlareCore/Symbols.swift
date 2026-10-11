// Symbols.swift: how an instance maps the host timeline onto its symbol's
// own timeline, and how a drawing walk resolves an instance to its symbol
// (shared by export and hit testing). Values may come from files, so all
// arithmetic is overflow-safe and never traps, and the walk stops at cycles
// and at `Instance.maxNestingDepth`.
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

extension Instance {
    /// Deepest symbol nesting that rendering, export and hit testing follow,
    /// so a long chain of nested symbols cannot overflow the stack.
    public static let maxNestingDepth = 64

    /// The symbol this instance shows and its frame when the host is at
    /// `frame`, for drawing the symbol's layers inside the instance. `path`
    /// holds the ids of the symbols already being drawn around this instance.
    /// Nil when `symbols` has no such symbol, when it is on `path` (a cycle),
    /// or when `path` is already `maxNestingDepth` deep. The host frame is
    /// rounded down and clamped to +-9e18; a non-finite frame counts as 0.
    public func resolve(in symbols: [Symbol], frame: Double, path: [String]) -> (symbol: Symbol, frame: Double)? {
        guard path.count < Instance.maxNestingDepth, !path.contains(symbolID),
              let symbol = symbols.first(where: { $0.id == symbolID }) else { return nil }
        // Clamped well inside Int's range, so the conversion cannot trap.
        let host = frame.isFinite ? Int(min(max(frame.rounded(.down), -9e18), 9e18)) : 0
        return (symbol, Double(localFrame(parentFrame: host, symbolDuration: symbol.durationFrames)))
    }
}
