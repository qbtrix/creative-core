# motion-tracks lead record

Issue: #313 · Packet: docs/blueprints/core/features/motion-tracks.md
Run: act-1a149b544ea-emiq (line lead: render-backend, motion-tracks) · Started: 2026-10-17 (prior runs act-1a1463a91ae-nkkr, act-1a142b4b27e-bv69)
Stage: 4 Anatomy (all waves merged; MT-5 #363 feature-done)
Base: 3be8939 (origin/dev)
Next: round 2 fixer PR merges; round 3 on dev (loop stops at 2 clean rounds or 4 total); contact sheet on #313 once a dev CI run holding 9b72477 is green (39031409068 was red on macOS only, MetalPipelinesTests from #362, dev-red #365; Linux green); then stop.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| MT-1 | a | Timeline.onionFrames | Onion.swift, OnionTests | OnionTests | FlareOnion.json | #317 | merged |
| MT-2 | a | Lottie opacity and rotation tracks | LottieExporter.swift, LottieTracksTests | LottieTracksTests | FlareLottieTracks.json | #315 | merged |
| MT-3 | b | Lottie scale tracks, maxBakedKeys | LottieExporter.swift, LottieScaleTrackTests | LottieScaleTrackTests | FlareLottieScale.json | #328 | merged |
| MT-4 | c | Lottie gradient stop alpha | LottieExporter.swift, LottieGradientAlphaTests | LottieGradientAlphaTests | FlareLottieGradientAlpha.json | #346 (merged 6967968) | merged |
| MT-5 | d | FlareBudgetTests reference scene; feature-done | FlareBudgetTests.swift | FlareBudgetTests | - | #363 (9b72477) | merged |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 3be8939 | 962/964; 2 known wall-clock flakes under load (StageBudget hit 11.1 ms, EngineStress 10.2 s) | FlareOnion 5/5, FlareLottieTracks 2/2, FlareLottieScale 3/3, FlareLottieGradientAlpha 2/2 | 39031409068 (Linux green, macOS red from #362) | correctness, rules fit, first-use clarity | 4 minor: scale x100 overflows past finite check (a), onion range unbounded for huge durationFrames (b), 3 invariants without mutation entries (c), exporter header says static only (d) | #370 (23af67b) | no |
| 2 | 23af67b | (gate with fixer PR) | (with fixer PR) | – | round 1 fixes, whole feature, first-use clarity | 3 minor: add-saturation mutant removed in #370 is not equivalent (durationFrames Int.max reachable), group transform scale checks finite before x100 (LottieExporter:401), contract slice omits maxOnionSkins | #372 (merged as e2d3b95) | no |
| 3 | e2d3b95 | 967/967, CI: PASS | FlareOnion 5/5, FlareLottieTracks 2/2, FlareLottieScale 6/6, FlareLottieGradientAlpha 3/3 | – | round 2 fixes, whole feature, first-use clarity | 1 minor: scale bake computes hi = durationFrames - 1 before its durationFrames > 0 guard (LottieExporter:301), traps on in-memory Int.min; #372 fixes verified | #375 (merged as 3fcc64e) | no |
| 4 | 4682eee | (running) | (running) | – | round 3 fix, whole feature, first-use clarity (final round) | 2 minor: Onion.swift:26 duration guard and LottieExporter:285 layer scale finite-after-x100 have no mutation entry; #375 verified (guard order, fallback, mutation real) | fixer building (mutation entries only) | no; loop ends (4 rounds) |

## Decisions
- Packet base was f05665f; dev is at cae920b. MT-1, MT-2, MT-3 were already merged before this lead started, so the lead starts at wave c.
- Designated branch is pushed WIP (dfb6aa7); its only remote history beyond dev was the merged MT-4 commit, replaced with force-with-lease per CLAUDE.md.
- Status branch lead/motion-tracks is the one the playbook names. Builder PRs use the designated branch claude/motion-tracks-lead-qyywzp, restarted from origin/dev after each merge, per the session's branch rule.
- Swift 6.3.3 installed via scripts/cloud-setup.sh (the pinned toolchain).

- QB-L5 ruling (supervisor, #313 06:06Z): keep the 10 ms budget and the reference scene; disable hitWithinBudget on reference with the reason naming gap #360 (filed, p3); QB-L6..QB-L8 stay asserted. MT-5 carries feature-done and Refs #228 (does not close it).

## Open
- Dev CI 39031409068 (9b72477, triggered by feature-done): Linux, Mutation, anchors green; macOS red in MetalPipelinesTests (metal-backend #362, not this feature). Waiting for the next green dev run.
- QB-L5 hit median measured 10.4-11 ms on the Linux sandbox vs 17 ms on reference; noted for gap #360.
- Packet says the lead's critic panel is run after the build waves; not yet run.
- Issue #313 shows state reopened; no contact sheet yet.
