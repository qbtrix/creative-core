# render-backend lead record

Issue: #347 · Packet: docs/blueprints/core/features/render-backend.md
Run: act-1a148000c96-2nvm · Session: this session · Started: 2026-10-17
Stage: 3 wave 2 (RB-2 done, RB-3 next)
Base: b447e68eba1f576b8bc3b3f124d150b7b8ad812b (origin/dev)
Next: RB-3, CPUBackend and CPUSurface, on a fresh branch from origin/dev
Branch note: the playbook names lead/render-backend; the session's git rules name
claude/render-backend-lead-m82rpo. Work and this record are on the designated
branch until the supervisor says otherwise. lead/render-backend does not exist on origin yet.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| RB-1 | 1 | targets, Metal scaffold, C4 parts | Package.swift and others | TargetsTests | none | landed with decision PR | done |
| RB-2 | 2 | contract types and FakeBackend | Sources/CoreRender/{RenderOp,RenderSurface,RenderBackend,ToneAdjustment,FakeBackend}.swift | RenderBackendFakeTests | CoreRenderContract.json (2) | not opened | gate PASS 918 tests, pushed 653c33b |
| RB-3 | 3 | CPUBackend, CPUSurface | Sources/CoreRender/CPU/* | CPUBackendTests | CoreRenderCPUBackend.json | – | open |
| RB-4 | 4 | CPU ops: transform, resample, blur, adjust, retouch | Sources/CoreRender/CPU/CPUBackend+Ops.swift | CPUBackendOpsTests | CoreRenderCPUBackendOps.json | – | open |
| RB-5 | 4 | RenderDispatcher | Sources/CoreRender/RenderDispatcher.swift | RenderDispatcherTests | CoreRenderDispatcher.json | – | open |
| RB-6 | 5 | ParityTolerance, ParityHarness | Sources/CoreRender/Parity/* | ParityHarnessTests | CoreRenderParity.json | – | open |
| RB-7 | 6 | CPU goldens, RenderBudgetTests, feature-done | Tests/CoreRenderTests/Golden/, waves.md | CPUGoldenTests, RenderBudgetTests | none | – | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| – | – | not run yet | – | – | – | – | – | – |

## Decisions
- RB-2: FakeCallLog is a final class with NSLock, because a value-type fake cannot record calls from non-mutating protocol methods. Test support only.
- RB-2: CPU and dispatcher test files hold one disabled placeholder each until RB-3 and RB-5.
- Work is on the designated branch, one commit per task, not one PR per task.
- No PRs opened: the session rules say not to without an explicit request.

## Open
- Supervisor: confirm the branch (lead/render-backend vs the designated branch) and whether to open PRs.
- Critic panel and Mac finisher not run.
