# layer-style-engine lead record

Issue: #779 · Packet: docs/blueprints/core/features/layer-style-engine.md
Run: act-1a15b62a149-srko · Session: see Belt · Started: 2026-10-20T22:05Z
Stage: 3 wave 1 (LE-a)
Base: 3ded188e8702de287fcc38dee63e1889220788b3
Next: LE-a1 builder (les/le-a1) opens its PR; then LE-a2, LE-3 and LE-6 stack on les/le-a1

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| LE-a | LE-1, LE-2 | – | open | | |
| LE-cpu | LE-3, LE-4, LE-5 | LE-a | open | | |
| LE-psd | LE-6, LE-7 | LE-a; LE-cpu | open | | |
| LE-metal | LE-8, LE-9 | LE-cpu | open | | wanted |
| LE-z | LE-10, LE-11 | LE-psd, LE-metal | open | | wanted (budgets) |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| LE-1 | 1 | style types, `styled` stub, StrokePosition Codable, RenderOp.style seam (dispatcher, fake, CPU, parity, Metal warmup) | packet LE-1 | RenderDispatcherTests.everyFamilyIsOn; StrokePosition JSON | – (seam) | | open |
| LE-2 | 1 | five suites disabled, style fixtures, PixelLayer.style + LayeredImage.notes | packet LE-2 | suites compile; PSD/ORA unchanged | – | | open |
| LE-3 | 2 | `beveled` | Effects/Bevel.swift | BevelTests | CoreRaster.Bevel (3) | | open |
| LE-4 | 3 | `styled`, reach, paint order | Effects/StyleComposite.swift | StyleCompositeTests | CoreRaster.StyleComposite (3) | | open |
| LE-5 | 4 | CPU backend styled + goldens | CPUBackend+Style.swift | CPUStyleTests, CPUGoldenTests | CoreRenderCPUStyle (2) | | open |
| LE-6 | 4 | lfx2 descriptor reader + mapping | PSDDescriptor/PSDEffects | PSDEffectsTests | CoreRaster.PSDEffects (3) | | open |
| LE-7 | 5 | linearDodge/linearBurn | BlendMode, PSDRead, StackXML, Metal blend | BlendModeTests, MetalBlendTests | CoreRaster.BlendMode (2) | | open |
| LE-8 | 5 | Metal JFA distance + box blur | MetalBackend+Distance | MetalDistanceTests | parity | | open |
| LE-9 | 6 | Metal style kernels | MetalBackend+Style | MetalStyleTests, parity | parity | | open |
| LE-10 | 7 | KJ-LE walk + budgets | StyleWalkTests, StyleBudgetTests | walk | – | | open |
| LE-11 | 8 | C4 descriptions, status, feature-done | docs | c4-assemble --check | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Rule 20: one PR per slice. LE-a = LE-1 + LE-2 in one PR (tests-first commit, then seam).
- Slice PRs stack: the next slice starts on a branch stacked on the open one; never wait on CI.
- Builders are worktree subagents, one per slice (lead.md stage 3 fallback), so a builder can be messaged back on a lane ejection. Branches `les/<slice>`: `lead/layer-style-engine/<task>` collides with the lead ref.
- Size cap beats rule 20's one-PR-per-slice: a slice over 400 lines ships as stacked PRs with the same `Slice:` line. LE-a: 1 PR. LE-cpu: LE-3, LE-4, LE-5 (3 PRs). LE-psd: LE-6, LE-7. LE-metal: LE-8, LE-9. LE-z: LE-10 + LE-11 folded (LE-11 < 50 lines), labelled feature-done.
- Rule 18 parallelism: once LE-a's PR is open, two chains stack on it: CPU (LE-3 -> LE-4 -> LE-5 -> LE-8 -> LE-9) and PSD (LE-6 -> LE-7). LE-6 maps lfx2 onto the contract's types only, so it doesn't need LE-4's bodies (packet lists LE-4 as a dependency for the op shapes, which LE-a fixes). LE-6 and LE-7 both own PSDRead.swift, so they're stacked, not parallel.
- LE-a split (builder report, 2026-10-20T22:20Z): ~21 files with pinned family-count tests, C4 cpu-backend entry and the parity switch, so over the 15-file cap. LE-a1 = CoreRaster contract types, stubs, StrokePosition Codable, PixelLayer.style, LayeredImage.notes, disabled suites (8 files). LE-a2 = CoreRender seam (RenderOp.style, defaults, dispatcher, fake, CPU stub throwing unsupported(.style), parity/Metal arms, contract-test counts), stacked on LE-a1. Both `Slice: LE-a`.
- Stacked PRs open only after the lower PR merged and the branch is rebased onto dev, since the lane counts the lower PR's lines otherwise. Builders build on the stack at once and report "ready, unopened" if the lower is still open.
- LE-3 and LE-6 need only CoreRaster, so they stack on LE-a1 in parallel with LE-a2.

## Open
- Container had no Swift toolchain; ran scripts/cloud-setup.sh at start.
