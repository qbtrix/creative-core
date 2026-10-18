// MaskCommands.swift: the family for commands that edit a layer's W1 masks
// and track matte. Empty today: it is the seam the mask commands land in, so
// each one touches only this file and MaskCommandsTests.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The mask and track-matte commands, registered in `CommandRegistry.builtIn`.
public enum MaskCommands {
    public static let all: [any Command.Type] = []
}
