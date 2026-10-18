// TrackCommands.swift: the family for commands that edit W1 colour and shape
// tracks. Empty today: it is the seam the track commands land in, so each one
// touches only this file and TrackCommandsTests.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The colour and shape track commands, registered in `CommandRegistry.builtIn`.
public enum TrackCommands {
    public static let all: [any Command.Type] = []
}
