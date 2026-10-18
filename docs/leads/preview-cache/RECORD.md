# preview-cache lead record

Issue: #440 · Packet: docs/blueprints/core/features/preview-cache.md
Run: act-1a14de006be-1kmq · Session: https://claude.ai/code/session_01WN1jNn5SUWJXTALMBvtq64 · Started: 2026-10-18T07:20Z
Line lead for: preview-cache (#440), vector-import (#439), layered-codecs (#438)
Stage: 3 wave 2
Base: 9e826ac8550b77b623909bd02758ad282558dfcc
Next: wave 2 builders PC-2 and PC-6 running; PC-a Anatomy round once PC-2 merges

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| PC-a | PC-1, PC-2 | nothing | open | | |
| PC-store | PC-3, PC-4, PC-5 | PC-a | open | | |
| PC-hash | PC-6, PC-7 | PC-a; engine-contracts:EC-a (met: #443, #450, #456) | open | | |
| PC-z | PC-8, PC-9 | PC-store, PC-hash | open | | wanted (budgets) |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| PC-1 | 1 | store types and stubs, `thumbnail-store` part | Sources/CoreAsset/Thumbnails/ThumbnailStore.swift, Tests/CoreAssetTests/ThumbnailStoreShapeTests.swift, docs/c4/parts/creative-core/coreasset/thumbnail-store.json | ThumbnailStoreShapeTests | none | #445 (e53d151) | merged |
| PC-2 | 2 | store, recovery, offline suites written and disabled | Tests/CoreAssetTests/{ThumbnailStoreTests,ThumbnailStoreRecoveryTests,OfflineVolumeTests}.swift | suites compile | – | | building |
| PC-3 | 3 | write/read/remove, budget LRU, lock, atomic replace | ThumbnailStore.swift, PreviewFiles.swift, ThumbnailStoreTests | ThumbnailStoreTests | CoreAsset.ThumbnailStore (3) | | open |
| PC-4 | 4 | index codec and recovery | PreviewIndex.swift, ThumbnailStoreRecoveryTests | ThumbnailStoreRecoveryTests | CoreAsset.PreviewIndex (2) | | open |
| PC-5 | 4 | volumes and availability | OfflineVolumes.swift, OfflineVolumeTests | OfflineVolumeTests | CoreAsset.OfflineVolumes (2) | | open |
| PC-6 | after EC-a | PerceptualHash | Sources/CoreRaster/Hash/PerceptualHash.swift, PerceptualHashTests | PerceptualHashTests | CoreRaster.PerceptualHash (3) | | building |
| PC-7 | after PC-6 | DuplicateGroups | Sources/CoreRaster/Hash/DuplicateGroups.swift, DuplicateGroupsTests | DuplicateGroupsTests | CoreRaster.DuplicateGroups (2) | | open |
| PC-8 | after PC-4,5,7 | KJ-PC walk and budgets | PreviewWalkTests, DuplicateWalkTests | walks | none | | open |
| PC-9 | last | part words, status line, `feature-done` | thumbnail-store.json, packet | – | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- One wave plan across the three features (rule 19); wave 1 is PC-1, VI-1, LC-1 (disjoint files).
- Builders run as worktree subagents (the playbook's fallback), one PR each via the GitHub MCP tools (the container's `gh` token is not valid).
- PC-6 waited on engine-contracts EC-a (not merged at 9d01972): CoreRaster's `Hash/` folder path in `image-ops` comes from it.

- Builder branches are `lead/<feature>-<task>` (a ref `lead/<feature>/<task>` cannot sit beside `lead/<feature>`).
- Wave 2 (9e826ac): PC-2, PC-6, VI-2, LC-2, LC-3, LC-5, disjoint files. `Hash/` is owned by `image-ops` and `Codecs/` by `codecs` on dev, so wave 2 needs no C4 edits.
- engine-contracts EC-a merged (#443, #450, #456), so PC-6 starts in wave 2.

## Open
- none
