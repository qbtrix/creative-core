# motion-tracks lead record

Issue: #313 · Packet: docs/blueprints/core/features/motion-tracks.md
Run: act-1a1463a91ae-nkkr · Session: claude/motion-tracks-lead-qyywzp (session_011q6y88xiPg7Pn4N3NTipgF) · Started: 2026-10-16T19:40Z (prior run act-1a142b4b27e-bv69 resumed)
Stage: 3 wave d (MT-5 blocked; #313 labelled needs-human after the third stall)
Base: 9ba4c2b (origin/dev after #346 merged)
Next: wait for the supervisor's choice on the QB-L5 hit budget (raise with amendment, optimize hit path in a separate PR, or shrink the reference scene). Then finish MT-5 and open its PR. Idle rerun: hit median 17.2 ms over 10 ms budget (not load).

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| MT-1 | a | Timeline.onionFrames | Onion.swift, OnionTests | OnionTests | FlareOnion.json | #317 | merged |
| MT-2 | a | Lottie opacity and rotation tracks | LottieExporter.swift, LottieTracksTests | LottieTracksTests | FlareLottieTracks.json | #315 | merged |
| MT-3 | b | Lottie scale tracks, maxBakedKeys | LottieExporter.swift, LottieScaleTrackTests | LottieScaleTrackTests | FlareLottieScale.json | #328 | merged |
| MT-4 | c | Lottie gradient stop alpha | LottieExporter.swift, LottieGradientAlphaTests | LottieGradientAlphaTests | FlareLottieGradientAlpha.json | #346 (merged 6967968) | merged |
| MT-5 | d | FlareBudgetTests reference scene; feature-done | FlareBudgetTests.swift | FlareBudgetTests | - | WIP dfb6aa7 on claude/motion-tracks-lead-qyywzp, no PR | blocked: QB-L5 hit budget decision |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| – | – | – | – | – | – | – | – | – |

## Decisions
- Packet base was f05665f; dev is at cae920b. MT-1, MT-2, MT-3 were already merged before this lead started, so the lead starts at wave c.
- Designated branch is pushed WIP (dfb6aa7); its only remote history beyond dev was the merged MT-4 commit, replaced with force-with-lease per CLAUDE.md.
- Status branch lead/motion-tracks is the one the playbook names. Builder PRs use the designated branch claude/motion-tracks-lead-qyywzp, restarted from origin/dev after each merge, per the session's branch rule.
- Swift 6.3.3 installed via scripts/cloud-setup.sh (the pinned toolchain).

## Open
- Packet says the lead's critic panel is run after the build waves; not yet run.
- Issue #313 shows state reopened; no contact sheet yet.
