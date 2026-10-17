# render-backend lead record

Issue: #347 · Packet: docs/blueprints/core/features/render-backend.md
Run: act-1a149b544ea-emiq (line lead: render-backend, motion-tracks) · Started: 2026-10-17 (prior runs act-1a14644b047-dxwc)
Stage: 3 waves (v3 loop, slices RB-a, RB-b, RB-c)
Base: 24fd483 (origin/dev)
Next: wait for RB-2b (FakeBackend + SurfaceStore) and RB-6 (parity harness) PRs to merge; then start RB-3 (CPUBackend on SurfaceStore).

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| RB-a | RB-1, RB-2a, RB-2b | nothing | open (RB-2b building) | – | – |
| RB-b | RB-3, RB-4, RB-5 | RB-a | open | – | – |
| RB-c | RB-6, RB-7 | RB-b (RB-7 only) | open (RB-6 building) | – | – |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-1 | – | targets, Linux-empty Metal module, C4 parts | Package.swift, ... | TargetsTests | none | #349 (human) | merged |
| RB-2a | – | RenderOp, RenderError, RenderSurface, RenderBackend, ToneAdjustment | Sources/CoreRender/{RenderOp,RenderSurface,RenderBackend,ToneAdjustment}.swift | RenderContractTests | none | #352 (opened by metal-backend lead) | merged |
| RB-2b | 1 | FakeBackend recording calls; shared locked SurfaceStore | Sources/CoreRender/{FakeBackend,SurfaceStore}.swift, Tests/CoreRenderTests/RenderBackendFakeTests.swift, Tests/mutations/CoreRenderFake.json, corerender C4 part | RenderBackendFakeTests | CoreRenderFake | – | building |
| RB-6 | 1 | ParityTolerance, ParityHarness (compare, sampleSet, goldens) | Sources/CoreRender/Parity/*, Tests/CoreRenderTests/ParityHarnessTests.swift, Tests/mutations/CoreRenderParity.json, parity.json part | ParityHarnessTests | CoreRenderParity | – | building |
| RB-3 | 2 | CPUBackend: surface, read, release, display, composite in place | Sources/CoreRender/CPU/CPUBackend.swift, Tests/CoreRenderTests/CPUBackendTests.swift, Tests/mutations/CoreRenderCPUBackend.json, cpu-backend.json part | CPUBackendTests | CoreRenderCPUBackend | – | waits RB-2b |
| RB-4 | 3 | CPUBackend transform, resample, blur, adjust, retouch | Sources/CoreRender/CPU/CPUBackend+Ops.swift, CPUBackendOpsTests, CoreRenderCPUBackendOps.json | CPUBackendOpsTests | CoreRenderCPUBackendOps | – | waits RB-3 |
| RB-5 | 3 | RenderDispatcher routing, health, lastFallback, cross-backend surfaces | Sources/CoreRender/RenderDispatcher.swift, RenderDispatcherTests, CoreRenderDispatcher.json, dispatcher.json part | RenderDispatcherTests | CoreRenderDispatcher | – | waits RB-3 |
| RB-7 | 4 | CPU goldens, RenderBudgetTests, waves.md status; feature-done | Tests/CoreRenderTests/Golden/, CPUGoldenTests, RenderBudgetTests, waves.md | CPUGoldenTests, RenderBudgetTests | none | – | waits RB-4, RB-5, RB-6 |

## Rounds
| round | slice | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|---|

## Decisions
- Recorder question (asked 02:55Z, no ruling): backends keep the non-mutating protocol and hold storage behind a lock, as MetalBackend on dev (#354) already does. The CPU backend needs the same thing anyway (the packet's CPUSurface is a class), so this is the backend pattern, not a model type. FakeBackend stays a struct as the packet spells it; its call log and surfaces live in a shared reference-typed store. One store type (SurfaceStore) serves the fake and the CPU backend (rule 16).
- RB-2 was split: RB-2a (contract types) landed as #352 from the metal-backend lead; RB-2b is FakeBackend.
- CPU and dispatcher acceptance tests land with their code (RB-3, RB-5) instead of disabled in RB-2: disabled tests cannot compile without the types, and stubs would double RB-2's size. Rule 13 allows "with the slice's first code task".
- RB-6 runs in wave 1 beside RB-2b: the harness needs only the protocol and CoreRaster, not CPUBackend.
- Builders are subagents with worktree isolation (no Workflow: the user did not opt in).
- gh CLI auth fails; issue and PR work goes through the GitHub MCP tools.

## Open
- Sandbox gate: two pre-existing wall-clock tests can fail under load on this 4-core box; builders retry on a quiet box and never claim Fast-Check without CI: PASS.
