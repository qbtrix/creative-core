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
- 2026-10-18T15:24:19Z PC-5 #516 merged (f7e5f0d). PC-8 builder launched (walk and budgets; relaunch 40 ms to be measured).
- 2026-10-18T15:40Z heartbeat: checking merges, dev CI and agents.
- 2026-10-18T15:43Z incident: the disk filled up at about 15:39Z. I deleted the .build caches of finished worktrees and told the running agents to rerun any gate that failed. No dev CI run newer than 364 yet. #518 (LC R2-2) needs a rebase onto 168c73d.
- 2026-10-18T16:05Z heartbeat.
- 2026-10-18T16:22Z #525 (PC-8, the walk and budgets) is open: head e6b2056, scripts/ci CI: PASS (1386 tests). Release timings against their budgets, Linux under load:

  | case | release | budget |
  |---|---|---|
  | relaunch, 2,000 entries | 37.3 ms | 40 ms |
  | read | 0.018 ms | 0.3 ms |
  | hash 1,000 | 1.21 s | 1.5 s |
  | group 100k | 1.09 s | 2 s |

  The debug walk uses 200 previews.

  Round-3 finding for PC-a: ThumbnailStore rewrites its whole index on every write, so filling it is quadratic. A debug fill of 2,000 took 284 s. Relaunch has only 7% to spare, so the Mac budgets need checking at PC-z.
- 2026-10-18T16:28Z PC-8 #525 merged 16:21Z. Round 3: fixer lead/preview-cache-R3-1 launched for the ThumbnailStore quadratic index rewrite (PC-a). PC-9 feature-done waits on it. Dev CI run 370 (7fcd04d) queued.
- 2026-10-18T16:51Z Heartbeat. Dev CI 369 (4eba850): Linux green; macOS red on DuplicateGroupsTests.groupManyBudget (debug 10k: 3.0 s vs 2 s, loaded runner). SIGBUS is gone. PC-hash owns it: fixer lead/preview-cache-R3-2 launched (release-only wall clock, deterministic debug guard). Run 370 queued.
- 16:54Z Belt-Slice-Done posted for PC-a and PC-store on run 39143654502 (Linux green). Stripped the attribution footers from the earlier lead comments.
- 17:16Z Heartbeat: run 370 (7fcd04d) has Linux green. macOS is red only on EngineStressTests (7.0 s vs 5 s), which is outside this lead; groupManyBudget passed. All round-3 agents are gating, queued on the CI lock. No new lead PRs since #525 and #526. PC-z waits on PC-9 (feature-done).
- 17:38Z Heartbeat: all five round-3 agents are gating, serialized on the CI lock. No lead PR is open. Dev run 373 (66bd163, #535 engine-stress perf) is queued. Disk: 17 GB free.
- 18:00Z Heartbeat: five agents, one CI-lock waiter each and no duplicates; LC R3-1 was resumed after stopping early. No lead PR is open. Dev run 373 is still queued. Disk: 17 GB free.
- 18:08Z PC R3-1 #543 merged: the thumbnail index is now an append-only index.journal with periodic compaction, so index I/O per write is constant on average; v1 indexes upgrade on open. Relaunch with 2,000 entries: 32 ms against a 40 ms budget. One read: 0.019 ms against 0.3 ms. Mutate 1/1. PC-9 waits on R3-2.
- 18:21Z heartbeat: 18G free; dev CI 373 (66bd163) green but predates #542-#544; no open lead PRs; LC R3-1 and PC R3-2 queued on gate, VI-8 building
