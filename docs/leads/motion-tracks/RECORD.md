# motion-tracks lead record

Issue: #313 · Packet: docs/blueprints/core/features/motion-tracks.md
Run: act-1a1463a91ae-nkkr · Session: claude/motion-tracks-lead-qyywzp (session_011q6y88xiPg7Pn4N3NTipgF) · Started: 2026-10-16T19:40Z (prior run act-1a142b4b27e-bv69 resumed)
Stage: 3 wave c (MT-4 PR #346 open, waiting on the lane)
Base: cae920bb08f80e277a9e7fc9c88b0a298b55e8d0 (origin/dev at lead start)
Next: when #346 merges, start MT-5 (FlareBudgetTests, feature-done) on the new origin/dev SHA.

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| MT-1 | a | Timeline.onionFrames | Onion.swift, OnionTests | OnionTests | FlareOnion.json | #317 | merged |
| MT-2 | a | Lottie opacity and rotation tracks | LottieExporter.swift, LottieTracksTests | LottieTracksTests | FlareLottieTracks.json | #315 | merged |
| MT-3 | b | Lottie scale tracks, maxBakedKeys | LottieExporter.swift, LottieScaleTrackTests | LottieScaleTrackTests | FlareLottieScale.json | #328 | merged |
| MT-4 | c | Lottie gradient stop alpha | LottieExporter.swift, LottieGradientAlphaTests | LottieGradientAlphaTests | FlareLottieGradientAlpha.json | #346 (head 07f0bc6) | open, fast-lane |
| MT-5 | d | FlareBudgetTests reference scene; feature-done | FlareBudgetTests.swift | FlareBudgetTests | - | - | not started |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| – | – | – | – | – | – | – | – | – |

## Decisions
- Packet base was f05665f; dev is at cae920b. MT-1, MT-2, MT-3 were already merged before this lead started, so the lead starts at wave c.
- Status branch lead/motion-tracks is the one the playbook names. Builder PRs use the designated branch claude/motion-tracks-lead-qyywzp, restarted from origin/dev after each merge, per the session's branch rule.
- Swift 6.3.3 installed via scripts/cloud-setup.sh (the pinned toolchain).

## Open
- Packet says the lead's critic panel is run after the build waves; not yet run.
- Issue #313 shows state reopened; no contact sheet yet.
