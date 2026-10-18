// PreviewIndex.swift: the preview store's index codec and its recovery.
// `index.json` holds a version, the budget and the entries. An index that
// fails to decode, names a version other than 1 or an impossible size is
// renamed to `index.damaged.json` (kept, never deleted) and rebuilt from the
// preview files: key, volume and path from each file's header, `byteCount`
// from its payload, `lastRead` from its modification date. A file whose header
// doesn't decode, or that sits under another key's name, is skipped and left
// on disk. Opening also deletes orphan `.tmp` files a crash left and drops
// entries whose file is gone. Invariants: everything here runs under the
// folder lock (PreviewFiles.withLock), and every failure is an `AssetError`.
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

extension PreviewFiles {
    var damagedIndex: URL { folder.appendingPathComponent("index.damaged.json") }

    /// The entries an index's bytes list; throws when they are damaged, name
    /// another version or an impossible size.
    static func decodeIndex(_ data: Data) throws(AssetError) -> [PreviewKey: PreviewEntry] {
        let decoded: PreviewIndexFile
        do { decoded = try JSONDecoder().decode(PreviewIndexFile.self, from: data) } catch {
            throw .invalid("the preview index is damaged")
        }
        guard decoded.version == PreviewIndexFile.currentVersion else { throw .invalid("preview index version \(decoded.version) is not supported") }
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

    /// The index's entries and whether they were rebuilt: a missing index is
    /// rebuilt from the files, a damaged one set aside first. `present` is the
    /// sweep's result when the caller already has it.
    func loadIndex(present: Set<String>? = nil) throws(AssetError) -> (entries: [PreviewKey: PreviewEntry], rebuilt: Bool) {
        let data: Data
        do { data = try Data(contentsOf: index) } catch {
            guard !FileManager.default.fileExists(atPath: index.path) else { throw .invalid("cannot read the preview index") }
            return (try rebuild(from: present ?? sweep()), true)
        }
        do throws(AssetError) { return (try Self.decodeIndex(data), false) } catch {
            guard rename(index.path, damagedIndex.path) == 0 else { throw .invalid("cannot set the damaged preview index aside") }
            return (try rebuild(from: present ?? sweep()), true)
        }
    }

    /// At open: deletes orphan temp files, loads (or rebuilds) the index, drops
    /// entries whose file is gone, and saves the index when that changed it.
    func openIndex(budgetBytes: Int) throws(AssetError) -> [PreviewKey: PreviewEntry] {
        try? FileManager.default.removeItem(atPath: index.path + ".tmp")
        let present = sweep()
        let (loaded, rebuilt) = try loadIndex(present: present)
        let entries = loaded.filter { present.contains(Self.name(for: $0.key)) }
        if rebuilt || entries.count != loaded.count { try saveIndex(entries, budgetBytes: budgetBytes) }
        return entries
    }

    /// The `.bin` files under `p/` as `<2 hex>/<16 hex>.bin`; deletes every
    /// `.tmp` there, which under the lock only a crash can have left.
    func sweep() -> Set<String> {
        let names = (try? FileManager.default.subpathsOfDirectory(atPath: previews.path)) ?? []
        for name in names where name.hasSuffix(".tmp") {
            try? FileManager.default.removeItem(at: previews.appendingPathComponent(name))
        }
        return Set(names.filter { $0.hasSuffix(".bin") })
    }

    /// Entries for the files `present`, from each one's header and payload.
    func rebuild(from present: Set<String>) throws(AssetError) -> [PreviewKey: PreviewEntry] {
        var entries: [PreviewKey: PreviewEntry] = [:]
        for name in present.sorted() {
            let url = previews.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let decoded = try? Self.decode(data) else { continue }  // skipped, left on disk
            let header = decoded.0
            guard Self.name(for: header.key) == name else { continue }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            entries[header.key] = PreviewEntry(key: header.key, byteCount: decoded.1.count, volume: header.volume,
                                               relativePath: header.relativePath, lastRead: modified ?? .distantPast)
        }
        return entries
    }
}
