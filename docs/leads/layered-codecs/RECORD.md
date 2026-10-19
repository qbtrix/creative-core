# layered-codecs lead record

Issue: #438 · Packet: docs/blueprints/core/features/layered-codecs.md
Run: act-1a14de006be-1kmq · Session: https://claude.ai/code/session_01WN1jNn5SUWJXTALMBvtq64 · Started: 2026-10-18T07:20Z
Line lead for: preview-cache (#440), vector-import (#439), layered-codecs (#438)
Stage: 3 wave 3; Anatomy round 1 on finished slices
Base: b80c0871a391e1729578b0344c8884c10471c8ca
Next: LC-7 #497 in lane; LC-8 launches on its merge (notes: no-profile images, composite present, 8-bit only); round-2 LC verdicts pending

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| LC-a | LC-1, LC-2 | nothing | open | | |
| LC-psd | LC-3, LC-4 | LC-a | open | | |
| LC-ora | LC-5, LC-6 | LC-a | open | | |
| LC-write | LC-7, LC-8 | LC-psd, LC-ora | open | | |
| LC-z | LC-9, LC-10 | LC-write | open | | wanted (budgets) |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| LC-1 | 1 | values, CodecError, PixelCodec, RawPixelCodec, PSD/ORA stubs, `codecs` part | Sources/CoreRaster/Codecs/{LayeredImage,PixelCodec,PSD,OpenRaster}.swift, Tests/CoreRasterTests/CodecShapeTests.swift, docs/c4/parts/creative-core/coreraster/codecs.json | CodecShapeTests | none | #446 (84d4b47) | merged |
| LC-2 | 2 | PSD byte builder, fixtures, suites disabled | PSDBytes.swift, Fixtures/codecs/, six suites | suites compile | – | #475 (33d046a) | merged |
| LC-3 | 2 | ByteReader and PackBits | Codecs/ByteReader.swift, Codecs/PackBits.swift, PackBitsTests | PackBitsTests | CoreRaster.PackBits (2) | #472 (da9d377) | merged |
| LC-5 | 2 | ZipStore (stored zip) | Codecs/ZipStore.swift, ORAContainerTests | ORAContainerTests | CoreRaster.ZipStore (2) | #474 (12e0d7a) | merged |
| LC-4 | 3 | PSD read | PSD.swift, PSDRead.swift, PSDReadTests, PSDFuzzTests | both | CoreRaster.PSDRead (11, 11/11 caught) | #493 (f33e8f3) | merged |
| LC-6 | 3 | ORA read | OpenRaster.swift, StackXML.swift, ORAReadTests, ORAFuzzTests | both | CoreRaster.StackXML (9, 9/9 caught) | #492 (8137c10) | merged |
| LC-7 | 4 | PSD write | PSDWrite.swift, PSDWriteTests | PSDWriteTests | CoreRaster.PSDWrite (2) | #497 | merged 21824da (7/7; 405 lines, captain merged) |
| LC-8 | 5 | ORA write | OpenRasterWrite.swift, CodecRoundTripTests | CodecRoundTripTests | CoreRaster.ORAWrite (2) | | open |
| LC-9 | 6 | KJ-LC walk and budgets | CodecWalkTests, CodecBudgetTests | walk | none | | open |
| LC-10 | 7 | part words, status, `feature-done` | codecs.json, packet | – | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 (LC-a) | b80c087 | PASS | PackBits 4/4, ZipStore 4/4 | - | clarity, contract, undo, robustness, tests | 6 major: read-notes field missing (packet), PSD pixel budget, ORA limits, ZipStore overlap total, unbalanced dividers untested, mask fields untested; 2 downgraded (RasterError doc, LayeredImage invariants) | builders LC-4, LC-6 + R1 doc batch (packet notes, RasterError header, ZipStore total if LC-6 leaves it) | no |

## Decisions
- One wave plan across the three features (rule 19); wave 1 is PC-1, VI-1, LC-1.
- LC-5 "moved from Photo's PhotoZip": this session can read only creative-core, so `ZipStore` is written here from the PKWARE APPNOTE with the packet's container rules (stored entries, `mimetype` first with its name at offset 30, other paths sorted, fixed DOS date). `sameBytesAsPhoto` pins golden bytes derived from those rules; Photo's W3 adoption checks its own bytes against it and reports any difference as a gap.

- Builder branches are `lead/<feature>-<task>` (a ref `lead/<feature>/<task>` cannot sit beside `lead/<feature>`).
- Wave 2 (9e826ac): PC-2, PC-6, VI-2, LC-2, LC-3, LC-5, disjoint files. `Hash/` is owned by `image-ops` and `Codecs/` by `codecs` on dev, so wave 2 needs no C4 edits.
- #458 (color-profiles) added a `profile` field to `LayeredImage`; LC builders carry it through read and write.
- LC-3 (#472): repeat-length mutant is `-header` (the literal `n` traps instead of failing); 4 mutants. `ByteReader` has LE reads for ZipStore.
- LC-5 (#474): self-contained LE reads, 4/4 mutants; does not use ByteReader yet (both merged in parallel).
- LC-2 (#475): ORA suites read entries through a test-side `StoredZip`; LC-6 switches them to `ZipStore`. Dropped to fit the cap: unbalanced-divider read test, compression value 3 (LC-4 may add back). `everyChannelIsRLE` checks size.
- From wave 3 builders run `scripts/ci` under one shared `flock`.

## Open
- LC-5's byte equality with Photo is unproven until W3 adoption (version fields and the UTF-8 flag are the likely differences).
- ZipStore and ByteReader both read little-endian; a fixer may fold ZipStore onto ByteReader if the duplicate check or a critic asks.

- 2026-10-18T13:44:23Z round 2: dev 8e258c5, gate PASS (EngineStress flake rerun), mutants 37/37, lenses 5, clean=no; majors n3/5/6/10/13/17 awaiting verifier
- 2026-10-18T14:04:16Z round 2 LC verdicts: majors n3 StackXML abs trap, n5 ORA total budget, n13 golden unproven -> fixer lead/layered-codecs-R2-1; n6 PSD merged channels -> fixer lead/layered-codecs-R2-2; n10/17 downgraded minor (mask term test, R2-2)

- 14:24Z: LC-7 #497 merged as 21824da (lost fast-lane at 405 lines, merged on review; trim dropped). LC-8 launched.
- 2026-10-18T15:03:59Z LC R2-1 #513 opened (cea5d91, 13/13: StackXML 11/11, ZipStore 1/1, CoreRaster 1/1). Closes round-2 n3, n5, n13 once merged.
- 2026-10-18T15:17:10Z LC R2-1 #513 merged 15:03Z (n3, n5, n13 closed). LC-8 #514 opened (b524600, 10/10 ORAWrite; footer stripped). macOS SIGBUS on deep recursion (ORA maxDepth 256, #453): fixer R2-3 launched.
- 2026-10-18T15:24:19Z LC-8 #514 merged 168c73d (11/11: ORAWrite 6/6, StackXML 5/5; writer follows #513's offset and depth rules). LC-9 next.
- 2026-10-18T15:40Z heartbeat: checking merges, dev CI and agents.
- 2026-10-18T15:43Z incident: the disk filled up at about 15:39Z. I deleted the .build caches of finished worktrees and told the running agents to rerun any gate that failed. No dev CI run newer than 364 yet. #518 (LC R2-2) needs a rebase onto 168c73d.
- 2026-10-18T16:01Z #518 (round-2 fix 2, the PSD budget) is rebased onto 168c73d. Head 342f910, scripts/ci CI: PASS (1373 tests), mutations 17/17 caught. It is waiting on the lane. When it merges, n6 and n10/17 close. New minor for round 3: the PSD writer has no depth cap, while the reader now stops at maxDepth 256.
- 2026-10-18T16:05Z heartbeat.
- 2026-10-18T16:05Z #518 merged at 16:01Z as 035b7d8. n6 and n10/17 are closed.
- 2026-10-18T16:05Z Another session's PRs fix the macOS stack-depth SIGBUS: #520 (ORA read, write and ==), #521 (Lottie JSON), #522 (SVG groups). They are open and checked together on ci/macos-reds-combined. My R2-3 fixer is stood down so it doesn't duplicate them. VI-svg, VI-lottie and LC-ora merged-done still need a green Linux job on a dev run that holds their PRs.
- 2026-10-18T16:27Z LC-9 #526 merged (16:25Z). Walk: layers.psd ORA save throws unsupported (masks/clipping), stated deviation; budget fixture 100 tiles of 400x300. Open 438-493 ms / 1500 ms, peak 682 MB / 1300 MB pass. **Save 5.2-5.6 s / 2 s misses (about 5 s thread CPU): PSD.write perf fixer queued.** Next: LC-10 feature-done.
- 2026-10-18T16:28Z Round 3: fixer lead/layered-codecs-R3-1 launched for the PSD.write save budget (5.2 s vs 2 s). LC-10 feature-done waits on it. #520 ORA iterative merged 16:08Z. Dev CI run 370 queued.
- 2026-10-18T16:51Z Heartbeat. Dev CI 369 Linux green, macOS red only on a preview-cache budget test (fixer launched); ORA/PSD suites passed on macOS. R3-1 PSD save fixer running.
- 16:54Z Belt-Slice-Done posted for LC-a, LC-psd, LC-ora and LC-write (#497 merged 14:21) on run 39143654502. LC-z waits on run 370 and feature-done.
- 17:16Z Heartbeat: run 370 (7fcd04d) has Linux green. macOS is red only on EngineStressTests (7.0 s vs 5 s), which is outside this lead; groupManyBudget passed. All round-3 agents are gating, queued on the CI lock. No new lead PRs since #525 and #526. LC-z waits on LC-10 (feature-done).
- 17:38Z Heartbeat: all five round-3 agents are gating, serialized on the CI lock. No lead PR is open. Dev run 373 (66bd163, #535 engine-stress perf) is queued. Disk: 17 GB free.
- 18:00Z Heartbeat: five agents, one CI-lock waiter each and no duplicates; LC R3-1 was resumed after stopping early. No lead PR is open. Dev run 373 is still queued. Disk: 17 GB free.
- 18:21Z heartbeat: 18G free; dev CI 373 (66bd163) green but predates #542-#544; no open lead PRs; LC R3-1 and PC R3-2 queued on gate, VI-8 building
- 18:26Z #545 merged (ff484f0), saveDeep 1353 ms vs 2000; openDeep over budget since #523, fixer R3-2 launched; LC-10 after it
- 18:43Z heartbeat: 18G free; dev CI 374 (bd50d5b, has #544 #545 #546 #548) Linux running; no open lead PRs; VI-8 and LC R3-2 working
- 19:00Z heartbeat 18:59: run 374 Linux green; LC R3-2 (openDeep) working; LC-10 after it
- 19:22Z heartbeat: LC R3-2 committed 7e244f4 (openDeep perf) locally, gating; no PR yet
- 19:44Z heartbeat: LC R3-2 idle since 18:42 with local 7e244f4, resumed with foreground-gate instruction
- 20:01Z LC R3-2 still stalled at 20:00 (7e244f4 local); stopped and relaunched a finisher on the same worktree
- 20:15Z #555 merged: openDeep 394 ms vs 1500; LC-10 (feature-done) launched
- 20:22Z heartbeat: LC-10 builder gating (flock held, load 8); no open lead PRs
- 20:33Z LC-10 #557 merged d715348 with feature-done (codecs C4 part rewritten, packet status built, rows and journey match code). Full CI #375 (39163834423) queued; Slice-Done LC-z waits on its Linux job.
- 20:45Z CI #375 (39163834423, d715348) Linux green. Posted on #438: Belt-Slice-Done LC-z, Mac-Finish-Wanted LC-z, Belt-Contact-Sheet (footers stripped, verified). layered-codecs complete.
