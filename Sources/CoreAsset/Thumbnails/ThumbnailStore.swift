// ThumbnailStore.swift: the disk preview store's public contract. Encoded
// preview bytes are keyed by the caller's asset key, content token and size
// class, held to a byte budget by least-recently-used eviction, and each entry
// names its volume and relative path so a preview of a file on an unplugged
// drive still reads and reports offline. CoreAsset stays dependency-free: the
// store keeps opaque `Data` and never decodes images.
// Status: contract and stubs only (PC-1). The throwing members throw
// `AssetError.invalid("not built")` and the others answer empty until PC-3
// (write, read, remove, budget), PC-4 (index and recovery) and PC-5 (volumes)
// build them. Invariant to keep: every failure is an `AssetError`.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The caller's identity for a storage volume: a stable id and a display name.
public struct VolumeRef: Hashable, Codable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A preview's size class; the raw value is its long edge in pixels.
public enum SizeClass: Int, Codable, Sendable, CaseIterable {
    case small = 256, medium = 1024, large = 2560
}

/// What a preview is of: the asset, the content token of the bytes it was
/// made from (a changed file gets a new token), and its size class.
public struct PreviewKey: Hashable, Codable, Sendable {
    public var asset: String
    public var content: String
    public var size: SizeClass

    public init(asset: String, content: String, size: SizeClass) {
        self.asset = asset
        self.content = content
        self.size = size
    }
}

/// One stored preview: its key, encoded size, the volume and path of the
/// original (nil when it has none), and when it was last read.
public struct PreviewEntry: Hashable, Codable, Sendable {
    public var key: PreviewKey
    public var byteCount: Int
    public var volume: VolumeRef?
    public var relativePath: String?
    public var lastRead: Date

    public init(key: PreviewKey, byteCount: Int, volume: VolumeRef?, relativePath: String?, lastRead: Date) {
        self.key = key
        self.byteCount = byteCount
        self.volume = volume
        self.relativePath = relativePath
        self.lastRead = lastRead
    }
}

/// Whether a preview's original is reachable now.
public enum Availability: Hashable, Sendable {
    case online
    case offline(VolumeRef)
}

/// A preview store in one folder. A store, not a model value: it is a class
/// because it owns files and, from PC-3, one lock that guards its index.
public final class ThumbnailStore: @unchecked Sendable {
    /// The folder the store keeps its index and preview files in.
    public let folder: URL
    /// The most bytes of preview files the store keeps before it evicts.
    public let budgetBytes: Int

    /// Opens (or, from PC-3, creates) the store in `folder`.
    public init(folder: URL, budgetBytes: Int) throws(AssetError) {
        self.folder = folder
        self.budgetBytes = budgetBytes
    }

    /// Stores `data` as the preview for `key`, replacing any earlier one.
    public func write(_ data: Data, for key: PreviewKey, volume: VolumeRef?, relativePath: String?) throws(AssetError) {
        throw AssetError.invalid("not built")
    }

    /// The preview bytes for `key`, or nil when absent; a read bumps `lastRead`.
    public func read(_ key: PreviewKey) throws(AssetError) -> Data? {
        throw AssetError.invalid("not built")
    }

    /// Every entry whose original lives on `volume`.
    public func entries(on volume: VolumeRef) -> [PreviewEntry] {
        []
    }

    /// Whether `key`'s original is reachable given the volume ids `mounted`
    /// now; nil when the store has no entry for `key`.
    public func availability(of key: PreviewKey, mounted: Set<String>) -> Availability? {
        nil
    }

    /// Removes every size class of every preview of `asset`.
    public func remove(asset: String) throws(AssetError) {
        throw AssetError.invalid("not built")
    }

    /// The bytes of preview files the store holds now.
    public var usedBytes: Int { 0 }
}
