# Feature packet: preview-cache

**Feature:** previews that survive a relaunch, and duplicates found by
pixels. CoreAsset gets a disk preview store (`ThumbnailStore`): encoded
preview bytes keyed by the caller's asset key, content token and size
class, written atomically under a lock, read back after a relaunch, held to
a byte budget by least-recently-used eviction, with each entry's volume and
relative path so a photo on an unplugged drive still shows its preview and
says it is offline. CoreRaster gets a 64-bit perceptual hash, its Hamming
distance, and grouping of near-identical hashes into duplicate sets.
CoreAsset stays dependency-free: it stores opaque `Data` and takes the hash
as a number, never importing CoreRaster.
**Line:** `line:core` · **Wave:** 5 (`waves.md`) · **Lead branch:** `lead/preview-cache`
**Status:** planned

**Covers:** beta-80 plan row E12 ("preview cache, offline drives, duplicate
hash"); Library map rows 9 (duplicate finder), 12 (disk preview cache) and
its "browse and search offline drives" row; the guard that Library's
in-memory LRU moves here.

**Depends on:** nothing for the store. The hash slice needs
`engine-contracts:EC-a` (the `Hash/` folder in `image-ops`). Base:
`origin/dev` 4f91e04.

**C4:** container `coreasset`, ✚ new component `thumbnail-store`
(`docs/c4/parts/creative-core/coreasset/thumbnail-store.json`, `paths:
["Sources/CoreAsset/Thumbnails/"]`, `order` 20), added by PC-1; container
`coreraster`, component `image-ops` (`Sources/CoreRaster/Hash/`). ⚠
`corecatalog/catalog-store` is named in the plan, but CoreCatalog is still
a skeleton (creative-core#157 open: only `CatalogError` exists), so the
offline-volume facts live with the preview entries here; the catalog takes
them over when its schema lands (see Not in this packet).

**Clean-room.** LRU eviction, atomic replace and the DCT-based perceptual
hash are public techniques; no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| PC-a | `ThumbnailStore`, `PreviewKey`, `PreviewEntry`, `VolumeRef`, `PerceptualHash` and `DuplicateGroups` exist as documented stubs, with the new `thumbnail-store` part and every check written and disabled. | PC-1, PC-2 | `ThumbnailStoreShapeTests` | nothing |
| PC-store | Previews written to the store read back after a new store opens the same folder, writes are atomic under a lock, the byte budget evicts the least recently used first, a damaged index is rebuilt from the files, and entries name their volume so offline previews still read and say offline. | PC-3, PC-4, PC-5 | `ThumbnailStoreTests`, `ThumbnailStoreRecoveryTests`, `OfflineVolumeTests` | PC-a |
| PC-hash | A buffer's perceptual hash is stable under resize, re-encode and small tone changes and far for different pictures, and duplicate groups collect every hash within a distance, each picture in one group. | PC-6, PC-7 | `PerceptualHashTests`, `DuplicateGroupsTests` | PC-a; engine-contracts:EC-a (PC-6) |
| PC-z | A walk fills a store with 2,000 previews, relaunches, unplugs a volume, evicts under a smaller budget and groups duplicates, the budgets hold, and the feature is built. | PC-8, PC-9 | `PreviewWalkTests`, `DuplicateWalkTests` | PC-store, PC-hash |

`ui_slice: none`: engine only. Its screens: Library's grid and loupe
(fast relaunch and scroll, offline badges) and its duplicate finder (W3);
Home's recents and the shared asset library later.

## Journey steps

Engine only. KJ-PC (`PreviewWalkTests.walk`, PC-8): a store in a scratch
folder; 2,000 previews of three size classes written; a second store on the
same folder reads all of them back `==`; volume "Card A" marked offline:
its 600 entries still read and report `.offline`; the budget halved: the
least recently read half is gone and the rest read; 50 seeded pictures plus
resized and tone-shifted copies group into 50 duplicate sets with no
picture in two.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreAsset/Thumbnails/ThumbnailStore.swift (PC-1 stubs, PC-3 and PC-4 bodies)
public struct VolumeRef: Hashable, Codable, Sendable { public var id: String; public var name: String }        // the caller's volume identity
public enum SizeClass: Int, Codable, Sendable, CaseIterable { case small = 256, medium = 1024, large = 2560 }
public struct PreviewKey: Hashable, Codable, Sendable { public var asset: String; public var content: String; public var size: SizeClass }
public struct PreviewEntry: Hashable, Codable, Sendable { public var key: PreviewKey; public var byteCount: Int; public var volume: VolumeRef?
    public var relativePath: String?; public var lastRead: Date }
public enum Availability: Hashable, Sendable { case online, offline(VolumeRef) }
public final class ThumbnailStore: @unchecked Sendable {   // a store, not a model value: one lock inside (CoreRender's `Locked` is the precedent)
    public init(folder: URL, budgetBytes: Int) throws(AssetError)
    public func write(_ data: Data, for key: PreviewKey, volume: VolumeRef?, relativePath: String?) throws(AssetError)
    public func read(_ key: PreviewKey) throws(AssetError) -> Data?                                       // nil when absent; bumps lastRead
    public func entries(on volume: VolumeRef) -> [PreviewEntry]
    public func availability(of key: PreviewKey, mounted: Set<String>) -> Availability?
    public func remove(asset: String) throws(AssetError)
    public var usedBytes: Int { get } }
// Sources/CoreRaster/Hash/PerceptualHash.swift (PC-6)
public struct PerceptualHash: Hashable, Codable, Sendable { public let bits: UInt64
    public init(of buffer: PixelBuffer) throws; public func distance(to other: PerceptualHash) -> Int }
// Sources/CoreRaster/Hash/DuplicateGroups.swift (PC-7)
public enum DuplicateGroups { public static func group(_ hashes: [(id: String, hash: PerceptualHash)], within distance: Int) -> [[String]] }  // 0...16
```

## Pseudocode

- **Layout on disk.** `folder/index.json` (entries, a version, the budget)
  and `folder/p/<2 hex>/<key digest>.bin`, the digest a stable 64-bit
  FNV-1a of the key's fields (written here, Foundation only), so names
  never carry user text. Writes go to a temp file then an atomic rename,
  under an exclusive lock file (the suite's `FileStore` rule), and the
  index is rewritten after the file.
- **Budget.** After a write, while `usedBytes > budgetBytes`, remove the
  entry with the oldest `lastRead` (ties: the larger size class first).
  `lastRead` updates on read in memory and is flushed at most every 2 s and
  on deinit, so a scroll doesn't rewrite the index per thumbnail.
- **Recovery.** An index that fails to decode or names a newer version is
  set aside (`index.damaged.json`) and rebuilt from the files present,
  with `lastRead` from their modification dates; files the index names but
  that are missing are dropped.
- **Offline.** The caller passes the volumes mounted now; an entry whose
  `volume.id` isn't in the set reads as `.offline(volume)` and its bytes
  still read.
- **PerceptualHash.** Luma, area-resampled to 32 × 32, a 2D DCT-II, the
  8 × 8 lowest frequencies without the DC term, each bit = coefficient >
  their median. `distance` is the popcount of the XOR.
- **DuplicateGroups.** A BK-tree over the hashes; union-find over pairs
  within `distance`; groups of 2 or more, each sorted by id, the list
  sorted by its first id.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| PC-1 | feature issue | The store's types and stubs, the new `thumbnail-store` part; the hash stubs wait for PC-6 (they live in CoreRaster's folder, which EC-1 adds); `ThumbnailStoreShapeTests` | `Sources/CoreAsset/Thumbnails/ThumbnailStore.swift`, `Tests/CoreAssetTests/ThumbnailStoreShapeTests.swift`, `docs/c4/parts/creative-core/coreasset/thumbnail-store.json` | – | ~180, 3 |
| PC-2 | – | Checks first: the store, recovery and offline suites disabled by name | `Tests/CoreAssetTests/ThumbnailStoreTests.swift`, `Tests/CoreAssetTests/ThumbnailStoreRecoveryTests.swift`, `Tests/CoreAssetTests/OfflineVolumeTests.swift` | PC-1 | ~300, 3 |
| PC-3 | – | Write, read, remove, the budget and LRU, the lock and atomic replace; turns on `ThumbnailStoreTests` | `Sources/CoreAsset/Thumbnails/ThumbnailStore.swift`, `Sources/CoreAsset/Thumbnails/PreviewFiles.swift`, `Tests/CoreAssetTests/ThumbnailStoreTests.swift`, `Tests/mutations/CoreAsset.ThumbnailStore.json` | PC-2 | ~360, 4 |
| PC-4 | – | The index codec and recovery in their own file; turns on `ThumbnailStoreRecoveryTests` | `Sources/CoreAsset/Thumbnails/PreviewIndex.swift`, `Tests/CoreAssetTests/ThumbnailStoreRecoveryTests.swift`, `Tests/mutations/CoreAsset.PreviewIndex.json` | PC-3 | ~240, 3 |
| PC-5 | – | Volume entries and `availability`; turns on `OfflineVolumeTests` | `Sources/CoreAsset/Thumbnails/OfflineVolumes.swift`, `Tests/CoreAssetTests/OfflineVolumeTests.swift`, `Tests/mutations/CoreAsset.OfflineVolumes.json` | PC-3 | ~140, 3 |
| PC-6 | – | `PerceptualHash` with its checks | `Sources/CoreRaster/Hash/PerceptualHash.swift`, `Tests/CoreRasterTests/PerceptualHashTests.swift`, `Tests/mutations/CoreRaster.PerceptualHash.json` | PC-1, engine-contracts:EC-a | ~220, 3 |
| PC-7 | – | `DuplicateGroups` with its checks | `Sources/CoreRaster/Hash/DuplicateGroups.swift`, `Tests/CoreRasterTests/DuplicateGroupsTests.swift`, `Tests/mutations/CoreRaster.DuplicateGroups.json` | PC-6 | ~200, 3 |
| PC-8 | – | KJ-PC walk and budgets (release, `.serialized`), the store half and the hash half | `Tests/CoreAssetTests/PreviewWalkTests.swift`, `Tests/CoreRasterTests/DuplicateWalkTests.swift` | PC-4, PC-5, PC-7 | ~200, 2 |
| PC-9 | – | The part's final words; the packet's status line; `feature-done` | `docs/c4/parts/creative-core/coreasset/thumbnail-store.json`, `docs/blueprints/core/features/preview-cache.md` | PC-8 | ~20, 2 |

The walk is two files because CoreAsset and CoreRaster have separate test
targets and neither imports the other: the store half in `CoreAssetTests`,
the hash-and-group half in `CoreRasterTests`, joined by the fixture ids. No
`Package.swift` edit.

## Build waves

- Wave 1: PC-1. Independent in this wave: PC-1 alone.
- Wave 2: PC-2, PC-6. Independent in this wave: both (PC-6 once engine-contracts' EC-a has merged).
- Wave 3: PC-3, PC-7. Independent in this wave: both.
- Wave 4: PC-4, PC-5. Independent in this wave: both.
- Wave 5: PC-8. Independent in this wave: PC-8 alone.
- Wave 6: PC-9 (`feature-done`, final). Independent in this wave: PC-9 alone.

Longest chain: PC-1 → PC-2 → PC-3 → PC-4 → PC-8 → PC-9 (6). Chain of 6:
the checks need the stubs, recovery rebuilds what the store writes, the
walk relaunches through recovery, PC-9 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| PC-1 | `ThumbnailStoreShapeTests`: stubs throw `AssetError`; values are `Codable` | a signature is missing | none |
| PC-2 | suites compile, disabled | – | – |
| PC-3 | `ThumbnailStoreTests`: write then read `==`; a second store on the folder reads it; a budget of 3 entries' bytes keeps the 3 most recently read; a read bumps recency; `remove(asset:)` drops every size class; a write interrupted before rename leaves the old bytes; two stores writing under the lock never lose an entry | an entry is lost or eviction picks the wrong one | `CoreAsset.ThumbnailStore`: evict newest first → `ThumbnailStoreTests.evictsLeastRecentlyRead`; read doesn't bump → `.readBumpsRecency`; temp file renamed before it is complete → `.interruptedWriteKeepsOld` |
| PC-4 | `ThumbnailStoreRecoveryTests`: a truncated index is set aside and rebuilt with every file; a newer version is set aside, not read; files missing from disk drop out; flush at most every 2 s (a 1,000-read scroll writes the index ≤ 2 times) | a damaged index loses previews or the index churns | `CoreAsset.PreviewIndex`: newer version accepted → `ThumbnailStoreRecoveryTests.newerSetAside`; flush on every read → `.scrollFlushesRarely` |
| PC-5 | `OfflineVolumeTests`: an entry on an unmounted volume reads its bytes and reports `.offline`; `entries(on:)` lists only that volume; no volume means always online | offline previews disappear | `CoreAsset.OfflineVolumes`: mounted check inverted → `OfflineVolumeTests.unmountedIsOffline`; nil volume reported offline → `.noVolumeIsOnline` |
| PC-6 | `PerceptualHashTests`: a picture and its 0.5× resize, its 8-bit round trip and a +0.1-stop exposure are within distance 6; 100 seeded different pictures are pairwise ≥ 20; the hash is deterministic | near copies drift apart or different pictures collide | `CoreRaster.PerceptualHash`: DC term kept → `PerceptualHashTests.exposureIsNear`; mean for median → `.differentPicturesFar`; DCT over 16 × 16 → `.resizeIsNear` |
| PC-7 | `DuplicateGroupsTests`: three near copies of one picture form one group; a chain a~b~c groups all three; singletons are left out; each id is in at most one group; output order is stable | a picture lands in two groups | `CoreRaster.DuplicateGroups`: union by pair only (no transitivity) → `DuplicateGroupsTests.chainsGroup`; singletons kept → `.singletonsDropped` |
| PC-8 | `PreviewWalkTests.walk` and `DuplicateWalkTests.walk` (KJ-PC); their budget cases: a relaunch reading 2,000 entries' index ≤ 40 ms; a read ≤ 0.3 ms; hashing 1,000 previews ≤ 1.5 s; grouping 100,000 hashes ≤ 2 s (release, reported) | the walk's checks fail | none |
| PC-9 | the part's words; status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Fast relaunch | index of 2,000 entries opens ≤ 40 ms | `PreviewWalkTests.relaunchBudget` (release, reported) |
| Scroll | a cached read ≤ 0.3 ms; the index flushes ≤ once per 2 s | `PreviewWalkTests.readBudget`, `ThumbnailStoreRecoveryTests.scrollFlushesRarely` |
| Duplicates at catalogue size | 100,000 hashes grouped ≤ 2 s | `DuplicateWalkTests.groupManyBudget` |
| Never loses a preview | atomic writes, recovery rebuilds from files | `ThumbnailStoreTests`, `ThumbnailStoreRecoveryTests` |
| No new dependency | CoreAsset imports only Foundation | `scripts/ci` |

## Done check

Per slice as usual; PC-z's budgets on the Mac (`Mac-Finish-Wanted: PC-z`).

## Adopted later

**W3:** Library's thumbnails and loupe move from the in-memory LRU onto
`ThumbnailStore` (L+3.2 for previews and offline), its duplicate finder on
`DuplicateGroups`; Home's recents and the shared asset library later cost
one adopt slice each. Library's `LoupeViewport` LRU goes (beta-80 plan:
"LRU → E12").

## Not in this packet

Catalog schema for volumes and duplicates (CoreCatalog, creative-core#157
and its L-issues); encoding the preview images (the app's ImageIO, through
creative-apps `shell-media`); face and scene similarity (S6's
`shell-vision`).
