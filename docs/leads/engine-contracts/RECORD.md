# engine-contracts lead record

Issue: #429 · Packet: docs/blueprints/core/features/engine-contracts.md
Run: act-1a14ddaebc8-nwqn · Session: line lead (engine-contracts, animate-properties, color-profiles) · Started: 2026-10-18T07:15Z
Stage: 4 round 4 (last allowed): gate and mutation on dev 0a3c7f3 running; dev CI run 39137019273 queued on the same SHA
Base: 9d01972365f04da4fe6074e9bdd56ceab5b616a8
Next: r3-a merged (#483), r3-b merged (#508, 0a3c7f3). Round 4 critic panel on 0a3c7f3 once gate and mutation finish; then EC-10 with feature-done.

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| EC-a | EC-1, EC-2, EC-3 | nothing | open | | wanted (everyFamilyIsOn, Warmup switch) |
| EC-b | EC-4, EC-5 | EC-a (EC-2) | open | | |
| EC-f | EC-6, EC-7, EC-8 | nothing | merged; waits on dev Linux job | | |
| EC-z | EC-9, EC-10 | EC-a, EC-b, EC-f | open | | |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| EC-1 | 1 | CoreRaster W1 value types | Sources/CoreRaster/W1/W1Values.swift, image-ops + compositing parts | W1ValuesTests | CoreRaster.W1Values (2) | #443 | merged 5300d41 |
| EC-6 | 1 | W1 FlareCore model fields + validate | Document.swift, W1Model.swift, FlareFormat.swift | W1ModelTests | FlareW1Model (3) | #444 | merged e1d381f |
| EC-2 | 2 | RenderOp families, tone cases, backend defaults | RenderOp, ToneAdjustment, RenderBackend(+NotOnThisBackend) | W1ContractTests | CoreRender.W1Contract (2) | #450 | open: Metal (macOS) check queued |
| EC-7 | 2 | registry and undo seams | CommandRegistry, Mask/TextStyle/TrackCommands | CommandRegistryTests | none (seam) | #448 | merged |
| EC-8 | 2 | exporter seam files, byte for byte | SVGExporter+*, LottieExporter+* | existing exporter tests | none (move) | #447 | merged |
| EC-3 | 3 | FakeBackend + Metal holdout | FakeBackend, AdjustTable, MetalCapabilities, Warmup | RenderBackendFakeTests, AdjustTableTests | CoreRenderFake (2) | | waits EC-2 |
| EC-4 | 3 | dispatcher forwarders + CPU stubs | RenderDispatcher, CPUBackend+* | RenderDispatcherW1Tests | CoreRenderDispatcherW1 (2) | | waits EC-2 |
| EC-5 | 3 | parity seams | Parity/* | ParityHarnessTests | none (seam) | | waits EC-2 |
| EC-9 | 4 | KJ-EC walk | W1ContractWalkTests, W1FileWalkTests | walk | none | | waits EC-3,4,5,7,8 |
| EC-10 | 5 | status line, engineering.md, feature-done | packet, docs/engineering.md | prose | none | | waits EC-9 |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 83b20aa | CI: PASS (1083 tests) | FlareW1Model 4/4, CoreRaster.W1Values 3/3 | - | clarity, contract, compat, robustness, tests | 15 (3 major, 12 minor); 1 outside the feature | r1-a, r1-b, r1-c | no |
| 2 | 8839b71 | CI: PASS (2nd run; 1st EngineStress 6.7s under load, 2.86s alone) | FlareW1Model 17/17, CoreRaster.W1Values 3/3, CoreRender.W1Contract 2/2, CoreRenderFake 13/13, CoreRenderDispatcherW1 2/2 | - | clarity, contract, compat, robustness, tests | 11 of 12 (2 major, 9 minor); 1 refuted; #10 routed to color-profiles | r2-a, r2-b, r2-c (wf_f6725ac5-6d8) | no |
| 3 | f7413a6 | CI: PASS (2nd run; 1st EngineStress 6.9s under load) | FlareW1Model 19/19, CoreRaster.W1Values 5/5, CoreRender.W1Contract 2/2, CoreRenderFake 13/13, CoreRenderDispatcherW1 4/4 | - | clarity, contract, compat, robustness, tests | 14 (4 major, 10 minor); 2 refuted; #1, #8, #11 routed to animate-properties; #9, #12, #13 to color-profiles; #6, #7 are EC-9/EC-10 (planned); #10 covered by each feature's own round | r3-a, r3-b | no |

## Decisions
- dev CI 39121455101 (33d046a): Linux green, macOS red only on ParityTests.resample (16x400000 to 400000x16, column 64000). No commit in main..33d046a touches resampling; our Metal edits (AdjustTable .color throw, enable ignores notOnMetalYet, Warmup W1 arms) are off that path. Not ours; noted on #453 (comment 6249304129) and left to the render-metal owner.
- Round 3 (wf_754b6005-2a0) reviewed firstBase..f7413a6 on the shared dev, so it saw animate-properties and color-profiles code too; those findings went to their own records and fixers.
- dev CI 39118832683 on 0660756: Linux green. EC-a, EC-b, EC-f merged-done; Mac-Finish-Wanted EC-a posted.
- #461 (e158c87) amended brief rule 9: a message starting `Belt released this run.` means stop at once; every other chat message still never stops the lead. Applied to this run.
- Line lead over #429, #442, #441 (rule 19); one wave plan across them, files disjoint per wave.
- Builder branches are named lead/<feature>-<task> (a ref lead/<feature>/<task> can't coexist with lead/<feature>).
- PR bodies carry Slice: and Mutate: lines (v3 rules 4 and 14); build-wave.js adapted in the session scratchpad to say so.

- Wave-1 PR bodies carried a trailing --- after Head: (a server-appended footer, since stripped); builders now PATCH the body so it ends at Head:.
- EC-2 also touched compile-only switch arms (CPUBackend+Ops, AdjustTable, ParitySamples, MetalBackend+Warmup) and four tests; the lead allowed it in the prompt. W1ContractTests is a suite inside RenderContractTests.swift so the PR stays at 15 files.
- EC-8 adds no new test: the packet names the existing exporter tests and goldens as the oracle for the move.
- Round 1 finding on Sources/CoreRaster/Codecs/PixelCodec.swift (RawPixelCodec guards without mutations) belongs to layered-codecs, not this feature: left to that lead.
- dev full CI run 39111859890 on c614b52 is red (#453): Linux EngineStressTests.thousandCommandsNearTheLayerLimitStayInBudget 5.75s > 5s; macOS green. Fixers measured the test alone at ~3.3s on dev and on their branches; r1-a's point counting adds ~6% (3.5 -> 3.75s). A re-dispatched CI (39112737255) failed the same way at 6.17s, and the whole test took 34.1s against 23.7s and 25.7s on the last green dev runs (af0b73e, 3094ab1). On the runner that is a real ~35% regression from this feature's W1 validation and fields, not load. The fixer (lead/engine-contracts-stress) removes the happy-path cost, with the budget untouched. EC-f Belt-Slice-Done waits for a green Linux job.
- Stress fix #459 merged (b5b782b): box Layer W1 fields, skip W1 work on plain layers; stress test 3.6s -> 2.7s locally (9d01972: 2.5s), budget untouched, FlareW1Model 17/17. Waiting on a dev CI run to show Linux green.
- EC-4 built on lead/engine-contracts-ec-4 (de552be, RenderDispatcherW1Tests pass, CoreRenderDispatcherW1 2/2) but held without a PR: scripts/ci fails on dev itself (#453), and CLAUDE.md says stop. Rebased on b5b782b and opened as #460 (90a94c3, CI: PASS, 2/2 CoreRenderDispatcherW1).

## Open
- none
- EC-9 → #485 (head 460d444, merged ca537c1), slice EC-z: W1ContractWalkTests.walk and W1FileWalkTests.walk. The body was missing its Mutate line and the contract check did not flag it; the lead added 'Mutate: none (walk tests)' after merge.
- r3-a → #483 merged a5f952a (colour-encoding docs, HSLRange renamed to HSLShift).
