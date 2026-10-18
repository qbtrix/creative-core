// ThumbnailStore.swift: the disk preview store's public contract. Encoded
// preview bytes are keyed by the caller's asset key, content token and size
// class, held to a byte budget by least-recently-used eviction, and each entry
// names its volume and relative path so a preview of a file on an unplugged
// drive still reads and reports offline. CoreAsset stays dependency-free: the
// store keeps opaque `Data` and never decodes images.
// Invariants: every failure is an `AssetError`; writes and removes reload the
// index under the folder lock (PreviewFiles.swift) and leave `usedBytes <=
// budgetBytes`, counting payloads only; a read checks its file's header names
// its key; reads flush the index at most every 2 s and on deinit, merged with
// the index on disk (PreviewIndex.swift recovers a damaged one). PC-5 volumes.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

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

    private let files: PreviewFiles
    private let queue = DispatchQueue(label: "CoreAsset.ThumbnailStore")
    private var entries: [PreviewKey: PreviewEntry]
    private var clock = Date.distantPast
    private var lastFlush = Date()
    private var unflushed = false
    private static let flushInterval: TimeInterval = 2

    /// Opens (or, from PC-3, creates) the store in `folder`.
    public init(folder: URL, budgetBytes: Int) throws(AssetError) {
        guard budgetBytes >= 0 else { throw .invalid("a preview budget cannot be negative") }
        let files = PreviewFiles(folder: folder)
        try files.createFolders()
        entries = try files.withLock { () throws(AssetError) in try files.openIndex(budgetBytes: budgetBytes) }
        self.folder = folder
        self.budgetBytes = budgetBytes
        self.files = files
    }

    /// Stores `data` as the preview for `key`, replacing any earlier one.
    public func write(_ data: Data, for key: PreviewKey, volume: VolumeRef?, relativePath: String?) throws(AssetError) {
        try changeFolder { (current: inout [PreviewKey: PreviewEntry]) throws(AssetError) in
            let header = PreviewFileHeader(key: key, volume: volume, relativePath: relativePath)
            try files.replace(files.file(for: key), with: PreviewFiles.encode(header, payload: data))
            current[key] = PreviewEntry(key: key, byteCount: data.count, volume: volume,
                                        relativePath: relativePath, lastRead: tick())
            evict(&current)
        }
    }

    /// The preview bytes for `key`, or nil when absent; a read bumps `lastRead`.
    public func read(_ key: PreviewKey) throws(AssetError) -> Data? {
        try locked { () throws(AssetError) -> Data? in
            guard entries[key] != nil else { return nil }
            let file = files.file(for: key)
            let data: Data
            do { data = try Data(contentsOf: file) } catch {
                guard FileManager.default.fileExists(atPath: file.path) else { entries[key] = nil; return nil }
                throw .invalid("cannot read preview file \(file.lastPathComponent)")
            }
            let (header, payload) = try PreviewFiles.decode(data)
            guard header.key == key else { throw .invalid("preview file \(file.lastPathComponent) is another key's") }
            entries[key]?.lastRead = tick()
            unflushed = true
            if Date().timeIntervalSince(lastFlush) >= Self.flushInterval { try? syncFolder { _ in } }
            return payload
        }
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
        try changeFolder { (current: inout [PreviewKey: PreviewEntry]) throws(AssetError) in
            for key in current.keys.filter({ $0.asset == asset }) {
                current[key] = nil
                files.removeFile(for: key)
            }
        }
    }

    /// The bytes of preview files the store holds now.
    public var usedBytes: Int {
        queue.sync { entries.values.reduce(0) { $0 + $1.byteCount } }
    }

    /// Runs `body` on the serial queue.
    private func locked<T>(_ body: () throws(AssetError) -> T) throws(AssetError) -> T {
        let result: Result<T, AssetError> = queue.sync { Result { () throws(AssetError) -> T in try body() } }
        return try result.get()
    }

    /// Under the queue and the folder lock: reloads the index (keeping this
    /// store's newer reads), lets `body` change it and its files, then writes it.
    private func changeFolder(_ body: (inout [PreviewKey: PreviewEntry]) throws(AssetError) -> Void) throws(AssetError) {
        try locked { () throws(AssetError) in try syncFolder(body) }
    }

    /// `changeFolder`'s work, for a caller already on the queue; it also
    /// flushes this store's reads.
    private func syncFolder(_ body: (inout [PreviewKey: PreviewEntry]) throws(AssetError) -> Void) throws(AssetError) {
        try files.withLock { () throws(AssetError) in
            var current = try files.loadIndex().entries
            for (key, mine) in entries where current[key].map({ $0.lastRead < mine.lastRead }) == true {
                current[key]?.lastRead = mine.lastRead
            }
            try body(&current)
            try files.saveIndex(current, budgetBytes: budgetBytes)
            entries = current
            lastFlush = Date()
            unflushed = false
        }
    }

    /// Flushes reads not yet in the index.
    deinit {
        if unflushed { try? changeFolder { _ in } }
    }

    /// While over budget, drops the entry read longest ago and its file.
    private func evict(_ current: inout [PreviewKey: PreviewEntry]) {
        var used = current.values.reduce(0) { $0 + $1.byteCount }
        for victim in current.values.sorted(by: Self.evictsBefore) where used > budgetBytes {
            current[victim.key] = nil
            used -= victim.byteCount
            files.removeFile(for: victim.key)
        }
    }

    /// Eviction order: older `lastRead` first, then the larger size class.
    private static func evictsBefore(_ a: PreviewEntry, _ b: PreviewEntry) -> Bool {
        a.lastRead != b.lastRead ? a.lastRead < b.lastRead : a.key.size.rawValue > b.key.size.rawValue
    }

    /// Now, nudged past the last stamp this store gave so stamps never tie.
    private func tick() -> Date {
        let now = Date()
        clock = now > clock ? now : clock.addingTimeInterval(0.000_001)
        return clock
    }
}
