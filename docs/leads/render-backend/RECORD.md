# render-backend lead record

Issue: #347 · Packet: docs/blueprints/core/features/render-backend.md
Run: act-1a14644b047-dxwc · Session: see the Belt run page · Started: 2026-10-16T19:52Z
Stage: 3 wave 1 (RB-1, protected: waiting on a human merge)
Base: 6967968ed037539869535c4c22fefeab7cc8ea32 (origin/dev)
Next: RB-1 is a protected-path PR (Package.swift). The lane will not merge it; a human must. Open it, comment on #347, and stop builder work that depends on it until it lands.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-1 | 1 | two targets, Linux-empty Metal module, C4 parts | Package.swift, Sources/CoreRender/CoreRender.swift, Sources/CoreRenderMetal/MetalBackend.swift, Tests/CoreRenderTests/TargetsTests.swift, Tests/CoreRenderMetalTests/TargetsTests.swift, docs/c4/parts/creative-core/corerender/* | TargetsTests | none | – | blocked: protected path, needs human merge |
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
