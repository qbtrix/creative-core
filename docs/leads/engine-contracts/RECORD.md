# engine-contracts lead record

Issue: #429 · Packet: docs/blueprints/core/features/engine-contracts.md
Run: act-1a14ddaebc8-nwqn · Session: line lead (engine-contracts, animate-properties, color-profiles) · Started: 2026-10-18T07:15Z
Stage: 3 wave 2
Base: 9d01972365f04da4fe6074e9bdd56ceab5b616a8
Next: wave 2 (EC-2, EC-7, EC-8) building on dev e1d381f; then wave 3 (EC-3, EC-4, EC-5, AP-1)

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| EC-a | EC-1, EC-2, EC-3 | nothing | open | | wanted (everyFamilyIsOn, Warmup switch) |
| EC-b | EC-4, EC-5 | EC-a (EC-2) | open | | |
| EC-f | EC-6, EC-7, EC-8 | nothing | open | | |
| EC-z | EC-9, EC-10 | EC-a, EC-b, EC-f | open | | |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| EC-1 | 1 | CoreRaster W1 value types | Sources/CoreRaster/W1/W1Values.swift, image-ops + compositing parts | W1ValuesTests | CoreRaster.W1Values (2) | #443 | merged 5300d41 |
| EC-6 | 1 | W1 FlareCore model fields + validate | Document.swift, W1Model.swift, FlareFormat.swift | W1ModelTests | FlareW1Model (3) | #444 | merged e1d381f |
| EC-2 | 2 | RenderOp families, tone cases, backend defaults | RenderOp, ToneAdjustment, RenderBackend(+NotOnThisBackend) | W1ContractTests | CoreRender.W1Contract (2) | | building |
| EC-7 | 2 | registry and undo seams | CommandRegistry, Mask/TextStyle/TrackCommands | CommandRegistryTests | none (seam) | | building |
| EC-8 | 2 | exporter seam files, byte for byte | SVGExporter+*, LottieExporter+* | existing exporter tests | none (move) | | building |
| EC-3 | 3 | FakeBackend + Metal holdout | FakeBackend, AdjustTable, MetalCapabilities, Warmup | RenderBackendFakeTests, AdjustTableTests | CoreRenderFake (2) | | waits EC-2 |
| EC-4 | 3 | dispatcher forwarders + CPU stubs | RenderDispatcher, CPUBackend+* | RenderDispatcherW1Tests | CoreRenderDispatcherW1 (2) | | waits EC-2 |
| EC-5 | 3 | parity seams | Parity/* | ParityHarnessTests | none (seam) | | waits EC-2 |
| EC-9 | 4 | KJ-EC walk | W1ContractWalkTests, W1FileWalkTests | walk | none | | waits EC-3,4,5,7,8 |
| EC-10 | 5 | status line, engineering.md, feature-done | packet, docs/engineering.md | prose | none | | waits EC-9 |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Line lead over #429, #442, #441 (rule 19); one wave plan across them, files disjoint per wave.
- Builder branches are named lead/<feature>-<task> (a ref lead/<feature>/<task> can't coexist with lead/<feature>).
- PR bodies carry Slice: and Mutate: lines (v3 rules 4 and 14); build-wave.js adapted in the session scratchpad to say so.

- Wave-1 PR bodies carried a trailing --- after Head: (a server-appended footer, since stripped); builders now PATCH the body so it ends at Head:.

## Open
- none
