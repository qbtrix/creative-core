# render-backend lead record

Issue: #347 · Packet: docs/blueprints/core/features/render-backend.md
Run: act-1a149b544ea-emiq (line lead: render-backend, motion-tracks) · Started: 2026-10-17 (prior runs act-1a14644b047-dxwc)
Stage: 3 waves (v3 loop, slices RB-a, RB-b, RB-c)
Base: 3be8939 (origin/dev)
Next: RB-4 and RB-5 builders (wave 4, base 4682eee); RB-a Anatomy round 4 (final); then RB-b Anatomy after RB-5; RB-7 feature-done after RB-6 and RB-5.

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| RB-a | RB-1, RB-2a, RB-2b | nothing | loop ended (4 rounds); last finding rides RB-5; Slice-Done waits for a dev CI run with green Linux | – | – |
| RB-b | RB-3, RB-4, RB-5 | RB-a | building (RB-3 merged; RB-4, RB-5 building) | – | – |
| RB-c | RB-6, RB-7 | RB-b (RB-7 only) | open (RB-6 merged) | – | – |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-1 | – | targets, Linux-empty Metal module, C4 parts | Package.swift, ... | TargetsTests | none | #349 (human) | merged |
| RB-2a | – | RenderOp, RenderError, RenderSurface, RenderBackend, ToneAdjustment | Sources/CoreRender/{RenderOp,RenderSurface,RenderBackend,ToneAdjustment}.swift | RenderContractTests | none | #352 (opened by metal-backend lead) | merged |
| RB-2b | 1 | FakeBackend recording calls; shared locked SurfaceStore | Sources/CoreRender/{FakeBackend,SurfaceStore}.swift, Tests/CoreRenderTests/RenderBackendFakeTests.swift, Tests/mutations/CoreRenderFake.json, corerender C4 part | RenderBackendFakeTests | CoreRenderFake | #361 (9e910ff) | merged |
| RB-6 | 1 | ParityTolerance, ParityHarness (compare, sampleSet, goldens) | Sources/CoreRender/Parity/*, Tests/CoreRenderTests/ParityHarnessTests.swift, Tests/mutations/CoreRenderParity.json, parity.json part | ParityHarnessTests | CoreRenderParity | #364 (bdbd260) | merged |
| RB-3 | 2 | CPUBackend: surface, read, release, display, composite in place | Sources/CoreRender/CPU/CPUBackend.swift, Tests/CoreRenderTests/CPUBackendTests.swift, Tests/mutations/CoreRenderCPUBackend.json, cpu-backend.json part | CPUBackendTests | CoreRenderCPUBackend | #377 (4682eee) | merged |
| RB-4 | 3 | CPUBackend transform, resample, blur, adjust, retouch | Sources/CoreRender/CPU/CPUBackend+Ops.swift, CPUBackendOpsTests, CoreRenderCPUBackendOps.json | CPUBackendOpsTests | CoreRenderCPUBackendOps | – | building |
| RB-5 | 3 | RenderDispatcher routing, health, lastFallback, cross-backend surfaces | Sources/CoreRender/RenderDispatcher.swift, RenderDispatcherTests, CoreRenderDispatcher.json, dispatcher.json part | RenderDispatcherTests | CoreRenderDispatcher | – | building |
| RB-7 | 4 | CPU goldens, RenderBudgetTests, waves.md status; feature-done | Tests/CoreRenderTests/Golden/, CPUGoldenTests, RenderBudgetTests, waves.md | CPUGoldenTests, RenderBudgetTests | none | – | waits RB-4, RB-5, RB-6 |

## Rounds
| round | slice | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|
| 1 | RB-a | 3be8939 | 962/964; 2 known wall-clock flakes under load (StageBudget hit 11.1 ms, EngineStress 10.2 s), 3 builders running alongside | CoreRenderFake 7/7 | 39031409068 (Linux green) | correctness, rules fit, first-use clarity | 6 minor: size check untested (C1), SurfaceStore.replace dead (C2), C4 and doc text claims CPU backend and dispatcher (R1), 4 private SplitMix64 copies (R2), surfaceMismatch doc misses wrong size (U1); C3 (disabled CPU/dispatcher test files) already decided | #371 (C1, R1, R2, U1; merged a6ad242); RB-3 PR (C2) | no |
| 2 | RB-a | a6ad242 | (gate with fixer PR) | (with fixer PR) | 39031409068 (Linux green) | round 1 fixes, whole slice, first-use clarity | 2 minor: five comments still describe the dispatcher and CPU backend as present (R1 incomplete), record-first invariant has no mutation | #373 (merged as ff4ae9f) | no |
| 3 | RB-a | ff4ae9f | 967/967 on e2d3b95 (ff4ae9f adds comments and one entry), CI: PASS | CoreRenderFake 9/9 | – | round 2 fixes, whole slice, first-use clarity | 2 minor: FakeBackend.swift:12 still names a dispatcher as present; SurfaceStore.replace has guards but no caller, test or mutation. #373 mutation verified real | comment: #374 (merged as 4b2aa75; also rewords metal-support comments, comments only); replace: #377 (caller, test, CoreRenderCPUBackend#5) | no |
| 4 | RB-a | 4682eee | 978/978, CI: PASS | CoreRenderFake 9/9, CoreRenderCPUBackend 5/5 | – | round 3 fixes, whole slice, first-use clarity (final round) | 1 minor: CoreRender.swift:10 says the contract does not exist yet; (a) and (b) verified fixed, #377 wording true | RB-5 PR (addendum) | no; loop ends (4 rounds) |

## Decisions
- Recorder question (asked 02:55Z, no ruling): backends keep the non-mutating protocol and hold storage behind a lock, as MetalBackend on dev (#354) already does. The CPU backend needs the same thing anyway (the packet's CPUSurface is a class), so this is the backend pattern, not a model type. FakeBackend stays a struct as the packet spells it; its call log and surfaces live in a shared reference-typed store. One store type (SurfaceStore) serves the fake and the CPU backend (rule 16).
- RB-2 was split: RB-2a (contract types) landed as #352 from the metal-backend lead; RB-2b is FakeBackend.
- CPU and dispatcher acceptance tests land with their code (RB-3, RB-5) instead of disabled in RB-2: disabled tests cannot compile without the types, and stubs would double RB-2's size. Rule 13 allows "with the slice's first code task".
- RB-6 runs in wave 1 beside RB-2b: the harness needs only the protocol and CoreRaster, not CPUBackend.
- Builders are subagents with worktree isolation (no Workflow: the user did not opt in).
- gh CLI auth fails; issue and PR work goes through the GitHub MCP tools.

## Open
- #369 (metal-backend lead) touched FakeBackend, ParityHarness and RenderError (typed parity errors, RenderError.mapping); builders base on 3be8939 or later.
- dev-red #365: macOS MetalPipelinesTests binary-archive tests (from #362); #368 dropped the archive. Triage comment posted; not ours to fix.
- Sandbox gate: two pre-existing wall-clock tests can fail under load on this 4-core box; builders retry on a quiet box and never claim Fast-Check without CI: PASS.
