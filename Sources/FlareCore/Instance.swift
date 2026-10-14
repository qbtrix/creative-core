// Instance.swift: a placement of a Symbol on a layer. An instance names its
// symbol by id, places it with a Transform, and says how the symbol's own
// timeline maps onto the host timeline.
//
// Invariants (checked by the format layer on load):
// - symbolID names a symbol in Document.symbols
// - firstFrame >= 0
// - every transform component is finite
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct Instance: Codable, Sendable, Hashable {
    /// How the symbol's timeline plays inside the host timeline.
    public enum LoopMode: String, Codable, Sendable, Hashable {
        /// Repeats the symbol's timeline forever.
        case loop
        /// Plays the symbol's timeline once, then holds its last frame.
        case playOnce
        /// Always shows `firstFrame`.
        case singleFrame
    }

    public var symbolID: String
    public var transform: Transform
    /// The symbol frame shown when the host timeline reaches this instance.
    public var firstFrame: Int
    public var loop: LoopMode

    public init(symbolID: String, transform: Transform = .identity, firstFrame: Int = 0, loop: LoopMode = .loop) {
        self.symbolID = symbolID
        self.transform = transform
        self.firstFrame = firstFrame
        self.loop = loop
    }
}

extension Transform {
    /// True if every component is finite (no NaN or infinity).
    var isFinite: Bool {
        [x, y, scaleX, scaleY, rotation].allSatisfy(\.isFinite)
    }
}
