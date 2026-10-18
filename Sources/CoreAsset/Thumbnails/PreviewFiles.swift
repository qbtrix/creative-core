// PreviewFiles.swift: the preview store's layout on disk and the two ways it
// changes it safely. `folder/index.json` lists the entries; each preview is
// `folder/p/<2 hex>/<16 hex>.bin`, named by a 64-bit FNV-1a digest of its key so
// no user text reaches a path. Invariants: every file is replaced by writing
// `<name>.tmp` whole and renaming it over the old one, so a reader sees the old
// bytes or the new, never part; every change to the folder runs under an
// exclusive `flock` on `folder/lock`, which holds between stores in this process
// and in others; an index that is not version 1, names a negative size or sums
// past Int throws `AssetError` (PC-4 replaces that with recovery).
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

/// The index file's contents.
struct PreviewIndexFile: Codable, Sendable {
    static let currentVersion = 1
    var version: Int
    var budgetBytes: Int
    var entries: [PreviewEntry]
}

/// The files of one preview store's folder.
struct PreviewFiles: Sendable {
    let folder: URL

    var index: URL { folder.appendingPathComponent("index.json") }
    private var lockFile: URL { folder.appendingPathComponent("lock") }
    private var previews: URL { folder.appendingPathComponent("p", isDirectory: true) }

    /// Creates the folder and its preview directory when they are missing.
    func createFolders() throws(AssetError) {
        do {
            try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
        } catch {
            throw .invalid("cannot create the preview folder \(folder.path)")
        }
    }

    /// The preview file for `key`.
    func file(for key: PreviewKey) -> URL {
        let name = Self.hex(Self.digest(key))
        return previews.appendingPathComponent(String(name.prefix(2)), isDirectory: true)
            .appendingPathComponent(name + ".bin")
    }

    /// A stable 64-bit FNV-1a over the key's fields, each ended by a zero byte.
    static func digest(_ key: PreviewKey) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for field in [key.asset, key.content, String(key.size.rawValue)] {
            for byte in field.utf8 + [0] {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return hash
    }

    /// `value` as 16 lowercase hex digits.
    static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    /// Replaces `file` with `data`: the bytes go to `<file>.tmp`, which is
    /// renamed over `file` only once it is complete.
    func replace(_ file: URL, with data: Data) throws(AssetError) {
        let temp = URL(fileURLWithPath: file.path + ".tmp")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: temp)
        } catch {
            throw .invalid("cannot write preview file \(temp.lastPathComponent)")
        }
        guard rename(temp.path, file.path) == 0 else {
            throw .invalid("cannot replace preview file \(file.lastPathComponent)")
        }
    }

    /// Runs `body` holding the folder's exclusive lock.
    func withLock<T>(_ body: () throws(AssetError) -> T) throws(AssetError) -> T {
        let descriptor = open(lockFile.path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else { throw .invalid("cannot open the preview lock") }
        defer { _ = close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw .invalid("cannot lock the preview folder") }
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    /// The entries the index on disk lists; none when there is no index yet.
    func loadIndex() throws(AssetError) -> [PreviewKey: PreviewEntry] {
        guard FileManager.default.fileExists(atPath: index.path) else { return [:] }
        let decoded: PreviewIndexFile
        do {
            decoded = try JSONDecoder().decode(PreviewIndexFile.self, from: Data(contentsOf: index))
        } catch {
            throw .invalid("the preview index is damaged")
        }
        guard decoded.version == PreviewIndexFile.currentVersion else {
            throw .invalid("preview index version \(decoded.version) is not supported")
        }
        var entries: [PreviewKey: PreviewEntry] = [:]
        var total = 0
        for entry in decoded.entries {
            let (sum, overflow) = total.addingReportingOverflow(entry.byteCount)
            guard entry.byteCount >= 0, !overflow else { throw .invalid("the preview index names an impossible size") }
            total = sum
            entries[entry.key] = entry
        }
        return entries
    }

    /// Writes `entries` as the index, in a stable order.
    func saveIndex(_ entries: [PreviewKey: PreviewEntry], budgetBytes: Int) throws(AssetError) {
        let sorted = entries.values.sorted { Self.digest($0.key) < Self.digest($1.key) }
        let file = PreviewIndexFile(version: PreviewIndexFile.currentVersion, budgetBytes: budgetBytes, entries: sorted)
        let data: Data
        do { data = try JSONEncoder().encode(file) } catch { throw .invalid("cannot encode the preview index") }
        try replace(index, with: data)
    }

    /// Deletes the preview file for `key`; one already gone is no error.
    func removeFile(for key: PreviewKey) {
        try? FileManager.default.removeItem(at: file(for: key))
    }
}
