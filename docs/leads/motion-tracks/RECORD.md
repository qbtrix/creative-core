# motion-tracks lead record

Issue: #313 · Packet: docs/blueprints/core/features/motion-tracks.md
Run: act-1a149b544ea-emiq (line lead: render-backend, motion-tracks) · Started: 2026-10-17 (prior runs act-1a1463a91ae-nkkr, act-1a142b4b27e-bv69)
Stage: 3 wave d (MT-5 building per the supervisor's QB-L5 ruling on #313, 06:06Z)
Base: 24fd483 (origin/dev)
Next: MT-5 PR (feature-done, Refs #228) merges; dev CI green; one Anatomy round; contact sheet on #313; then stop (feature is out of the beta cut).

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| MT-1 | a | Timeline.onionFrames | Onion.swift, OnionTests | OnionTests | FlareOnion.json | #317 | merged |
| MT-2 | a | Lottie opacity and rotation tracks | LottieExporter.swift, LottieTracksTests | LottieTracksTests | FlareLottieTracks.json | #315 | merged |
| MT-3 | b | Lottie scale tracks, maxBakedKeys | LottieExporter.swift, LottieScaleTrackTests | LottieScaleTrackTests | FlareLottieScale.json | #328 | merged |
| MT-4 | c | Lottie gradient stop alpha | LottieExporter.swift, LottieGradientAlphaTests | LottieGradientAlphaTests | FlareLottieGradientAlpha.json | #346 (merged 6967968) | merged |
| MT-5 | d | FlareBudgetTests reference scene; feature-done | FlareBudgetTests.swift | FlareBudgetTests | - | branch motion-tracks/mt-5 | building |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| – | – | – | – | – | – | – | – | – |

## Decisions
- Packet base was f05665f; dev is at cae920b. MT-1, MT-2, MT-3 were already merged before this lead started, so the lead starts at wave c.
- Designated branch is pushed WIP (dfb6aa7); its only remote history beyond dev was the merged MT-4 commit, replaced with force-with-lease per CLAUDE.md.
- Status branch lead/motion-tracks is the one the playbook names. Builder PRs use the designated branch claude/motion-tracks-lead-qyywzp, restarted from origin/dev after each merge, per the session's branch rule.
- Swift 6.3.3 installed via scripts/cloud-setup.sh (the pinned toolchain).

- QB-L5 ruling (supervisor, #313 06:06Z): keep the 10 ms budget and the reference scene; disable hitWithinBudget on reference with the reason naming gap #360 (filed, p3); QB-L6..QB-L8 stay asserted. MT-5 carries feature-done and Refs #228 (does not close it).

## Open
- Packet says the lead's critic panel is run after the build waves; not yet run.
- Issue #313 shows state reopened; no contact sheet yet.
