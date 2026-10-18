// OfflineVolumes.swift: previews of originals on removable volumes. The store
// never probes the file system for volumes; the caller says which volume ids
// are mounted now, and an entry whose volume is not among them reports
// `.offline(volume)` while `read` still returns its bytes.
// Invariants: volumes match on `VolumeRef.id` alone, so a renamed volume keeps
// its entries; an entry with no volume is always online and on no volume.
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ThumbnailStore {
    /// Every entry whose original lives on a volume with `volume.id`, whatever
    /// name that entry recorded for it, in no particular order. Entries with
    /// no volume are on no volume and never listed.
    public func entries(on volume: VolumeRef) -> [PreviewEntry] {
        currentEntries.values.filter { $0.volume?.id == volume.id }
    }

    /// Whether `key`'s original is reachable now. `mounted` holds the
    /// `VolumeRef.id` of every volume the caller can reach at this moment
    /// (not names). An entry whose volume id is not in `mounted` is
    /// `.offline` with the volume it recorded; an entry with no volume is
    /// always `.online`, whatever `mounted` holds. Nil when the store has no
    /// entry for `key`.
    public func availability(of key: PreviewKey, mounted: Set<String>) -> Availability? {
        guard let entry = currentEntries[key] else { return nil }
        guard let volume = entry.volume else { return .online }
        return mounted.contains(volume.id) ? .online : .offline(volume)
    }
}
