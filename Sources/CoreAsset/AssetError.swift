// AssetError.swift: the one error type of CoreAsset, the shared asset module
// (the Asset model and its manifest codec, used by every app). CoreAsset is
// Linux-safe, Foundation only, and depends on no other target. Every throwing
// API in this module throws this.
public enum AssetError: Error, Equatable, Sendable {
    /// A field, size or manifest is malformed or out of its allowed range.
    case invalid(String)
}
