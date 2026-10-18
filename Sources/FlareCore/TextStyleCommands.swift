// TextStyleCommands.swift: the family for commands that edit W1 text runs and
// their paragraph and path-text styles. Empty today: it is the seam the text
// style commands land in, so each one touches only this file and
// TextStyleCommandsTests.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The text run and style commands, registered in `CommandRegistry.builtIn`.
public enum TextStyleCommands {
    /// Every text-style command type, in registration order; empty until the first lands.
    public static let all: [any Command.Type] = []
}
