# render-backend lead record

Issue: #347 · Packet: docs/blueprints/core/features/render-backend.md
Run: act-1a14644b047-dxwc · Session: see the Belt run page · Started: 2026-10-16T19:52Z
Stage: 3 wave 2 (RB-2 contract), held on the gate question
Base: 9ba4c2b (origin/dev; RB-1 landed as #349)
Next: supervisor rules on the budget tests (no ruling on #347 yet). dev is 90924cb (generated model only, after 4f11af8). On a ruling, lead starts RB-2 from origin/dev.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-1 | 1 | two targets, Linux-empty Metal module, C4 parts | Package.swift, Sources/CoreRender/CoreRender.swift, Sources/CoreRenderMetal/MetalBackend.swift, Tests/CoreRenderTests/TargetsTests.swift, Tests/CoreRenderMetalTests/TargetsTests.swift, docs/c4/parts/creative-core/corerender/* | TargetsTests | none | – | superseded: RB-1 landed on dev as #349; #350 conflicts (dirty) |
| RB-2 | 2 | RenderOp, RenderError, RenderSurface, RenderBackend, ToneAdjustment, FakeBackend | Sources/CoreRender/{RenderOp,RenderSurface,RenderBackend,ToneAdjustment,FakeBackend}.swift, Tests/CoreRenderTests/RenderBackendFakeTests.swift | RenderBackendFakeTests | none | – | waiting on RB-1 |
| RB-3 | 3 | CPUBackend and CPUSurface: surface, read, release, display, composite | Sources/CoreRender/CPU/CPUBackend.swift, Sources/CoreRender/CPU/CPUSurface.swift, Tests/CoreRenderTests/CPUBackendTests.swift, Tests/mutations/CoreRenderCPUBackend.json | CPUBackendTests | CoreRenderCPUBackend | – | waiting on RB-2 |
| RB-4 | 4 | CPUBackend transform, resample, blur, adjust, retouch | Sources/CoreRender/CPU/CPUBackend+Ops.swift, Tests/CoreRenderTests/CPUBackendOpsTests.swift, Tests/mutations/CoreRenderCPUBackendOps.json | CPUBackendOpsTests | CoreRenderCPUBackendOps | – | waiting on RB-3 |
| RB-5 | 4 | RenderDispatcher: routing, health, lastFallback, cross-backend surfaces | Sources/CoreRender/RenderDispatcher.swift, Tests/CoreRenderTests/RenderDispatcherTests.swift, Tests/mutations/CoreRenderDispatcher.json | RenderDispatcherTests | CoreRenderDispatcher | – | waiting on RB-3 |
| RB-6 | 5 | ParityTolerance, ParityHarness (sample sets, compare, golden read/write) | Sources/CoreRender/Parity/*.swift, Tests/CoreRenderTests/ParityHarnessTests.swift, Tests/mutations/CoreRenderParity.json | ParityHarnessTests | CoreRenderParity | – | waiting on RB-4 |
| RB-7 | 6 | CPU goldens, RenderBudgetTests, waves.md status, feature-done | Tests/CoreRenderTests/Golden/, CPUGoldenTests.swift, RenderBudgetTests.swift, docs/blueprints/core/features/waves.md | CPUGoldenTests, RenderBudgetTests | none | – | waiting on RB-5, RB-6 |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Lead loop: v2 with the packet's Slices table (RB-a, RB-b, RB-c) as the release units, per the packet's Open note and the tracker's expected outcome. Per slice: done on a green ci.yml run holding its last PR; at most 2 fix rounds per slice.
- Branches: RECORD and timeline on lead/render-backend (Belt's status channel). Builder PR branches come from origin/dev, per CLAUDE.md. The session's designated branch claude/render-backend-lead-ivarpe is not used for PRs.
- Identity: "Prakash Dalai" / 86671543+prakashUXtech@users.noreply.github.com (contract rule 9).
- Builders are plain subagents with worktree isolation, not the Workflow tool, because the user did not ask for a workflow in their own words. The playbook allows this fallback.
- Toolchain: cloud-setup.sh installs Swift 6.3.3 (pinned there). scripts/ci runs here once the install finishes.
- gh CLI auth fails (GH_TOKEN). Issue and PR actions go through the GitHub MCP tools instead.

## Open
- RB-1 touches the protected path Package.swift. The fast lane refuses it. A human must review and merge. Without it, nothing in RB-2..RB-7 can build.
- Packet Base says origin/dev cae920b; the brief and the live dev are 6967968. The brief's SHA is used.
- Gate on dev 6967968 (this sandbox, 4 cores): scripts/ci fails in `swift test` at two wall-clock budgets under parallel load: RetouchBoundsTests `smallDabOn12MegapixelsIsFast` (2.1 to 2.6 s against 1.5 s; passes alone at 0.97 s) and EngineStressTests `thousandCommandsNearTheLayerLimitStayInBudget` (5.37 s against 5.0 s). `swift test --no-parallel` passes all 901 tests. GitHub runs for dev are green (cae920b, success). Until the budgets hold here, no PR can honestly carry `Fast-Check: pass`; the sandbox gate is not a substitute for the runner's.
- RB-1 PR #350 (branch render-backend/rb-1, head 426a411b7c26852ce02c78c46ba11e2a70fcbf82): swift build passes. scripts/ci fails on two budgets. swift test --no-parallel shows 903 tests with one failure: thousandCommandsNearTheLayerLimitStayInBudget at 5.62 s against 5.0 s. So the budget fails serially too, not only under parallel load. Fast-Check is marked "not run". c4-assemble --check reports drift from the new parts; the Generated workflow on dev regenerates model.json.
- Resume at 2026-10-16T20:2xZ: dev moved to 9ba4c2b. #349 (human) added the RB-1 targets and the render-backend C4 parts, and moved lead.md to the v3 loop. #350 is superseded and conflicts. Its comment says so; not closed, for the captain to close.
- Gate on 9ba4c2b (detached worktree, 4 cores): scripts/ci fails on the same two budgets (smallDab 1.96 s against 1.5 s; stress 5.33 s against 5.0 s). It is dev's own state, not the lead's. RB-2 is pure contract code and its tests pass serially, but there is no honest Fast-Check on this sandbox. Not starting RB-2 until the supervisor rules.
- 2026-10-16T21:37Z: dev is now 4f11af8 (#351 landed). Idle-box gate (detached worktree, nothing else running): scripts/ci fails on both budgets, 909 tests, 2 issues. Reported on #347 with the numbers. Still waiting for the supervisor.
