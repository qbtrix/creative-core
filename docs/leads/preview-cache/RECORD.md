# preview-cache lead record

Issue: #440 · Packet: docs/blueprints/core/features/preview-cache.md
Run: act-1a14de006be-1kmq · Session: https://claude.ai/code/session_01WN1jNn5SUWJXTALMBvtq64 · Started: 2026-10-18T07:20Z
Line lead for: preview-cache (#440), vector-import (#439), layered-codecs (#438)
Stage: 3 wave 3; Anatomy round 1 on finished slices
Base: b80c0871a391e1729578b0344c8884c10471c8ca
Next: PC-4, PC-5 building (PC-3 #498 merged with round-2 recovery header); PC-hash fixer R2-1 (n7); PC-8 after PC-4, PC-5 and the fixer

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
| PC-2 | 2 | store, recovery, offline suites written and disabled | Tests/CoreAssetTests/{ThumbnailStoreTests,ThumbnailStoreRecoveryTests,OfflineVolumeTests}.swift | suites compile | – | #487 (41434d1) | merged |
| PC-3 | 3 | write/read/remove, budget LRU, lock, atomic replace | ThumbnailStore.swift, PreviewFiles.swift, ThumbnailStoreTests | ThumbnailStoreTests | CoreAsset.ThumbnailStore (3) | #498 | merged (3/3, recovery header) |
| PC-4 | 4 | index codec and recovery | PreviewIndex.swift, ThumbnailStoreRecoveryTests | ThumbnailStoreRecoveryTests | CoreAsset.PreviewIndex (2) | | building |
| PC-5 | 4 | volumes and availability | OfflineVolumes.swift, OfflineVolumeTests | OfflineVolumeTests | CoreAsset.OfflineVolumes (2) | | building |
| PC-6 | after EC-a | PerceptualHash | Sources/CoreRaster/Hash/PerceptualHash.swift, PerceptualHashTests | PerceptualHashTests | CoreRaster.PerceptualHash (3) | #473 (cd93e06) | merged |
| PC-7 | after PC-6 | DuplicateGroups | Sources/CoreRaster/Hash/DuplicateGroups.swift, DuplicateGroupsTests | DuplicateGroupsTests | CoreRaster.DuplicateGroups (5, 5/5 caught) | #486 (f12484c) | merged |
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
- Wave 2 gate runs failed on FlareCore wall-clock budgets (`StageBudgetTests.hitWithinBudget`, `EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget`) while six builders shared the 4-core box; both pass alone. From wave 3 builders run `scripts/ci` and `scripts/mutate` under one shared `flock`, so the gate measures an unloaded box.
- PC-6 (#473): the DC-kept mutant is caught by `differentPicturesFar` and `hashIsDeterministic`, not `exposureIsNear` (an exposure scale keeps coefficient order); the 16×16 mutant by `differentPicturesFar`, not `resizeIsNear`. 3/3 caught; notes name the real catcher.

## Open
- PC-6 `differentPicturesFar` seed 624 has zero margin (closest pair = 20) and `hashIsDeterministic` pins 0xFF0CB51C37665241; both rest on identical floating point on macOS. PC-hash Anatomy reviews this.

- 2026-10-18T13:44:23Z round 2: dev 8e258c5, gate PASS (EngineStress flake rerun), mutants 37/37, lenses 5, clean=no; majors n2/11/16 recovery header (PC-3 builder), n7 DuplicateGroups quadratic (fixer lead/preview-cache-R2-1)

- 14:26Z: PC-hash fixer R2-1 opened #502 (866346b, 8/8, 284 lines): multi-index table, max distance 16 to 10, 100k in 0.62 to 0.73 s (was 248 s), random grouping 0.1%. Closes n7 on merge.

- 14:31Z: #502 merged (n7 closed). PC-hash waits on a dev CI run with a green Linux job.

- 14:43Z: PC-4 opened #510 (3597824, 6/6 CoreAsset.PreviewIndex, 399 lines). rebuiltEntriesKeepTheirVolume disabled until PC-5; PC-5 told to enable it and merge the C4 sentence. PC-8 note: relaunch 40 ms budget at 2,000 entries not measured yet.
- 2026-10-18T14:54:08Z PC-4 #510 merged (14:43:48Z). Dev CI run 364 (c294adb) queued; holds #502 and #510.
- 2026-10-18T15:17:10Z Belt-Slice-Done: PC-hash https://github.com/qbtrix/creative-core/actions/runs/39137820117 (Linux green at c294adb; macOS red on SIGBUS, see #453).
- 2026-10-18T15:18:31Z PC-5 #516 opened (01522cf, 3/3 CoreAsset.OfflineVolumes, 8/8 changed-since; rebuiltEntriesKeepTheirVolume enabled). PC-8 launches once it merges.
