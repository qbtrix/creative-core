# layer-style-engine lead record

Issue: #779 · Packet: docs/blueprints/core/features/layer-style-engine.md
Run: act-1a15b62a149-srko · Session: see Belt · Started: 2026-10-20T22:05Z
Stage: 3 wave 2 (LE-a2, LE-3, LE-6 in parallel)
Base: 3ded188e8702de287fcc38dee63e1889220788b3
Next: builders on LE-a2 (les/le-a2), LE-3 (les/le-3) and LE-6 (les/le-6) from dev 6e8f82c report PRs; then LE-4 on LE-3, LE-7 on LE-6

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
- Base gate on 3ded188 (2026-10-20T22:25Z): CI: FAIL only on wall-clock `ThumbnailStoreRecoveryTests.fuzzedIndexThrowsOrRecovers` (1.5-2.0 s vs 1 s) while a builder compiled (load 10.8 on 4 cores). No open dev-red. Treated as contention: builders gate under `flock /tmp/les-gate.lock scripts/ci`; recheck on a quiet machine before calling dev red.
- PR #780 (LE-a1) opened 22:32Z, lane-merged 22:33Z as 6e8f82c. Lane merges within a minute, so slices branch from fresh dev rather than stacking whenever the lower PR is already in.
- LE-a1 builder ran `pkill -f scripts/ci` once (could hit other gates); builders told never to pkill -f.
- Wave-2 builders hit the session limit at about 22:55Z, and then the container restarted. All three had committed and gated locally (CI: PASS): les/le-a2 b46f382a (155 lines, 14 files), les/le-3 88efe69e (194 lines, 3 files), les/le-6 e9634deb (544 lines, 8 files). Dev moved to 7966e5a9 (#781-#784, unrelated), and all three rebase cleanly. The lead ships them: rebase, gate under flock, push, PR.
- LE-6 is over the 400-line cap, so it ships as two stacked PRs, both `Slice: LE-psd`. LE-6a is the descriptor reader (f3d1b322, 193 lines). LE-6b is the effects mapping plus PSDRead (351 lines) and opens after LE-6a merges. LE-7 then stacks on LE-6b.
- #785 (LE-a2) opened at 00:23Z. The PR server appended an attribution footer, so the lead removed it at 00:30Z. The builder contract now says to read the body back and strip the footer. The lane waits on `Metal (macOS)` because the PR touches MetalBackend+Warmup.
- LE-3's gate after rebase (c9c61caf) failed only on wall-clock `ThumbnailStoreRecoveryTests.fuzzedIndexThrowsOrRecovers` (1.29 s against 1 s, load 11 with the LE-4 and LE-7 builders compiling). That is the same contention as the base gate, so it gets one rerun under flock.
- LE-4 (les/le-4, on les/le-3) and LE-7 (les/le-7, on les/le-6) builders started at 00:08Z. They open their PRs only after the lower PR merges.
- #786 (LE-3, c9c61caf, `Mutate: 3/3 CoreRaster.Bevel`) opened at 00:40Z after the gate rerun passed. The footer was stripped. #785 is mergeable (`Metal (macOS)` is green).
- LE-7 is ready but unopened as les/le-7 3222eebc (gate passed, 2/2 caught). It left one gap: `PSDEffects.modes`, the blend mode inside each effect, doesn't map `lddg` or `lbrn` yet. Fold that into the next PSD-side change (under 50 lines), or into LE-10.

## 00:47Z stage: LE-a/LE-3/LE-6a merged
- #785 (LE-a), #786 (LE-3) and #788 (LE-6a) merged into dev; dev is d2021453.
- #788 footer stripped after merge.
- LE-6b rebased onto dev at 804bbc83 (328+/23-, 5 files); its gate and the CoreRaster.PSDEffects mutate run are going.
- Next: open LE-6b, then resume the LE-7 builder to rebase onto dev and open its PR. LE-4 is building on dev.
- Belt-Slice-Done LE-a waits for a dev ci.yml run that contains #785.

## 00:52Z stage: LE-4 merged, LE-5 started
- #789 (LE-4, `styled` and `reach`) merged. Mutate 3/3 CoreRaster.StyleComposite. Its builder stripped the footer.
- LE-5 builder started on dev as `les/le-5`. It is not stacked, so it opens at once when its gate passes.
- LE-6b: once its gate passes, rebase onto dev (which now has #789), regate, then open.
- LE-8 starts when LE-5 merges.

- 2026-10-21T01:12:13Z: #790 (LE-6b) merged at 24caf911. LE-7 rebased onto dev cleanly (d84b3849); builder resumed to gate, mutate and open PR (Slice LE-psd). LE-5 builder still running. No dev ci.yml run contains #785 yet (latest run #425 at 7966e5a9).
- 2026-10-21T01:21:41Z: #791 (LE-5, slice LE-cpu last PR) merged at bddb0961, 12 files +175/-40, mutate 3/3. LE-8 builder started (slice LE-metal). LE-7 told to rebase on bddb0961 before push.
- 2026-10-21T01:34:39Z: LE-8 opened as #792 (head 1bab51d9, 3 new files, +350), footer stripped, fast-lane; Metal (macOS) check queued; two MSL constructs flagged unverified in body. LE-9 builder started stacked on les/le-8 (opens after #792 merges).
- 2026-10-21T01:36:42Z: LE-9 split (lead decision). Builder estimate ~850 lines/16 files: parity samples are 9x7 so tolerance is effectively 2 levels everywhere, the stroke needs CoreRaster AA edge distances, and removing style from notOnMetalYet touches 6 Linux test files. LE-9a: Metal light-layer kernels, per-surface alpha-keyed cache with encode counter, MetalStyleTests cache check, MetalStyleLayerTests, package access on CoreRaster helpers and LE-8 helpers (access only). LE-9b: paint-order blend/clipped composite, styled in one buffer, warmup, ParityTolerance.style, notOnMetalYet loses style, MetalStyleParityTests, Linux expectation fixes. LE-11 to update the packet Tasks rows.
- 2026-10-21T01:38:53Z: LE-7 opened as #793 (head a8717989, 15 files, +176/-20), mutate 2/2 CoreRaster.BlendMode, footer stripped, fast-lane. Folded in PSDEffects.modes linearDodge/linearBurn (+20); the descriptor enum names are unverified against a published spec, so that goes to the critic round. Last PR of slice LE-psd.
- 2026-10-21T01:46:18Z: LE-9a over the cap (~550 with tests). Re-split into LE-9a (access, LE-8 helper refactor, cache, shadow/glow/overlay layers, ~330), LE-9a2 (stroke and bevel layers, ~250), then LE-9b. All three are Slice LE-metal. #792 Metal (macOS) check in progress since 01:42Z.
- 2026-10-21T02:01:53Z: #792 Metal (macOS) green. LE-9a ready (0ded51b9, 9 files +366/-29), waiting for #792 to merge. No mutation entry: the packet says "none: kernels" for LE-8 and LE-9, and Linux compiles the Metal code out, so the parity tests are the check (lead agrees).
- 2026-10-21T02:09:58Z: #792 (LE-8) merged at 2d242a0d. #793 (LE-7) Metal (macOS) still queued since 01:38Z (the mac runner is the bottleneck). LE-9a builder is opening its PR now. No dev ci.yml run past 425 yet.
- 2026-10-21T02:10:56Z: LE-9a opened as #794 (head 14b4871e, rebased on 2d242a0d, 9 files +366/-29). Footer stripped, fast-lane on. Metal (macOS) queued. LE-9a2 building, stacked on les/le-9.
- 2026-10-21T02:19:23Z LE-9a2 built and gated on les/le-9a2 (4fbe7b28, 5 files +249/-16: stroke + bevel kernels, MetalStrokeBevelTests). Opens after #794 merges.
- 2026-10-21T02:30:42Z Heartbeat: #793 and #794 Metal checks are still queued and nothing is running, so the mac runner looks offline. Noted on #779 (comment 6306525297). No dev CI run after 425, so no Belt-Slice-Done yet.
- 2026-10-21T02:34:51Z LE-9b built and gated on les/le-9b (ba469709, 15 files +223/-32). Decision: the style parity samples compare to the CPU at the LE-9a expectClose tolerance (2 levels; edge pixels within 8 on at most 0.5%), not to the goldens; CPUGoldenTests holds the CPU to the goldens exactly. LE-10 builder started (LE-11 folded in, feature-done) on les/le-10, stacked on les/le-9b; it opens once #793, #794, 9a2 and 9b have merged.
- 2026-10-21T02:51:56Z Heartbeat: the Mac runner is back. #794 Metal (macOS) went green at 02:43Z and #794 now waits on the lane. #793 Metal is still queued (since 01:38Z). No dev CI run after 425.
- 2026-10-21T02:57:22Z LE-10 built on les/le-10 (d24512fe, 6 files +380/-12, LE-11 folded in), not gated. Its walk PSD leg fails because of an LE-6 (#790) bug: `Mapper.add` reads `Clr ` before the switch, so the gradient overlay (GrFl) and bevel (ebbl) are dropped as unreadable. LE-psd fix round 1: its own PR from dev (les/le-6-fix) with a PSDEffectsTests case and a mutation entry. The CPU budget read 6537 ms against 250 on this 4-core Linux sandbox (EffectBudgetTests misses by the same order here); the Mac reading is the real one.
- 2026-10-21T03:06:10Z LE-psd fix round 1 open as #795 (f301b339, 3 files +33/-7, Mutate 4/4 CoreRaster.PSDEffects). Gradient overlay, bevel and gradient-paint strokes no longer need `Clr `.
- 2026-10-21T03:13:05Z #793 (LE-7), #794 (LE-9a) and #795 (LE-psd fix) merged at 03:06Z; dev is at 3ad633b5. LE-psd's last PR is now #795. Dev CI run 426 (https://github.com/qbtrix/creative-core/actions/runs/39536751190) is queued at 3ad633b5 and holds LE-a, LE-cpu and LE-psd: Belt-Slice-Done goes out once its Linux job is green. LE-9a2 is open as #796.
- 03:36Z: dev CI 426 (3ad633b5) Linux green. Posted Belt-Slice-Done for LE-a, LE-cpu and LE-psd on #779.
- 03:36Z: #796 (LE-9a2) Metal (macOS) red. strokeAndBevelLayersMatchTheCPU fails for the inside and center stroke positions; outside strokes and bevel pass. The error grows with width, which points at the interior distance. LE-metal fix round 1 went to the builder. LE-9b and LE-10 wait.
- Root cause of the LE-metal round 1 failure: the stroke took its nearest seed from the jump flood, while the CPU uses the exact separable EDT. In thin stems the jump flood can pick a seed on the far edge, which puts the distance off by up to 1 px. That only shows up on inside and center strokes.
- The fix adds an exact int64 `style_edt_pass` kernel, a port of `envelopePass` that breaks ties the same way as the CPU, and adds a size guard that throws `unsupported(.style)`. The tolerance is unchanged. It is pushed as #796 head 29576313; Metal (macOS) is queued.
- 04:03Z: #796 Metal (macOS) passed at 29576313, so LE-metal fix round 1 fixed it with no contact sheet needed. The PR is mergeable and clean, and the fast lane should merge it on its next sweep (it sweeps every 5 min).
- 04:34Z: #796 stayed open 40 min after Metal (macOS) passed. The lane last ran on it at 03:46Z while Metal was still running, and the 5-min schedule has not fired since 02:04Z. Edited the PR body (wording only, same Head) to fire the lane's `edited` trigger. Belt nudge named lead/core-layer-style-engine; that branch does not exist, the record lives on lead/layer-style-engine.
- 04:35Z: #796 (LE-9a2) merged as 0407c94f. Resumed a83f4fc for LE-9b: rebase onto dev, check edt_pass in the warmup and the 18-mode blend switch, gate, open the PR (Slice LE-metal).
- 04:42Z: LE-9b open as #797 (head 7facfdb4, 15 files +223/-32). It was rebased past 9a2 with the edt fix kept in all three conflicted files; the blend switch covers 18 modes; the gate passed; the footer is stripped; fast-lane was added last. Metal (macOS) is queued. If the lane does not merge it within about 10 min of Metal going green, re-fire it with a body edit, as for #796.
- 04:55Z: #797 Metal (macOS) failed (job 119042317141). (1) MetalSurfaceTests `landed` lacks .style. (2) `samplesMatchTheCPU` style/stroke-center: worst 204 levels, 63 px past 2, while strokeAndBevelLayersMatchTheCPU and stacksMatchTheCPU pass. Fix round 2 of 2 sent to a83f4fc. If it is still red after this round, the slice gets a contact sheet.
- 05:05Z: #797 fix round 2 (subnormal alpha seed) pushed at 2797e556; 16 files tripped the lane cap. Decision: drop the C4 part sentence from #797, fold it into LE-10. LE-10 rebases onto dev past the final le-9b head.
