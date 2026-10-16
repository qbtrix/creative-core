# motion-tracks lead record

Issue: #313 · Packet: docs/blueprints/core/features/motion-tracks.md (on branch docs/core-packets-wave2, PR #310, until it merges)
Run: act-1a142b4b27e-bv69 · Session: claude/motion-tracks-lead-pifwao · Started: 2026-10-16T03:16Z
Stage: 3 wave b
Base: f27f1042e2944c2c750dda91f2e3f24cdfdde08f
Next: wait for MT-3's PR to merge via the lane, then wave c (MT-4) on the new origin/dev

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| MT-1 | a | `Timeline.onionFrames(at:before:after:durationFrames:)` (closes #218) | Sources/FlareCore/Onion.swift, Tests/FlareCoreTests/OnionTests.swift, Tests/mutations/FlareOnion.json, docs/c4/parts/creative-core/flarecore/timeline.json | OnionTests | FlareOnion.json (clamp, playhead excluded, saturating) | #317 (c7f1c76) | merged |
| MT-2 | a | Lottie animated opacity and rotation tracks (#227 part) | Sources/FlareCore/Export/LottieExporter.swift, Tests/FlareCoreTests/LottieTracksTests.swift, Tests/mutations/FlareLottieTracks.json | LottieTracksTests | FlareLottieTracks.json (opacity clamp, hold) | #315 (7feb023) | merged |
| MT-3 | b | Lottie animated scale: one-track, shared keys, per-frame bake; `maxBakedKeys` (#227 part) | LottieExporter.swift, Tests/FlareCoreTests/LottieScaleTrackTests.swift, Tests/mutations/FlareLottieScale.json | LottieScaleTrackTests | FlareLottieScale.json (bake cap, range clamp) | – | building |
| MT-4 | c | Gradient stop alpha; export C4 description (closes #227) | LottieExporter.swift, Tests/FlareCoreTests/LottieGradientAlphaTests.swift, Tests/mutations/FlareLottieGradientAlpha.json, docs/c4/parts/creative-core/flarecore/export.json | LottieGradientAlphaTests | FlareLottieGradientAlpha.json (alpha < 1 guard) | – | planned |
| MT-5 | d | FlareBudgetTests on `reference`: QB-L5..QB-L8; `feature-done` (closes #228) | Tests/FlareCoreTests/FlareBudgetTests.swift | FlareBudgetTests | – | – | planned |

Acceptance tests and quality bars: the packet's "Acceptance test per task" and "Quality tests" tables (copied by reference; the packet wins).
- MT-1 OnionTests: 10/2/2/48 → [8,9,11,12]; 1 → [0,2,3]; 47 → [45,46]; 0,0 → []; -3 counts 0; 1-frame scene → []; Int.max counts / Int.min frames don't trap.
- MT-2 LottieTracksTests: golden `ks.o` (100→0, ease tangents); `ks.r` with `h` 1 on hold; opacity clamp; existing goldens byte-identical.
- MT-3 LottieScaleTrackTests: one-track keys; shared keys golden [100,100]→[200,200]; bake one linear key per frame == sample×100; > maxBakedKeys throws unsupported("scale track"); keys past end / 0 frames → static; static goldens unchanged.
- MT-4 LottieGradientAlphaTests: linear+radial alpha 0.25 → color stops then alpha stops, `p` = stop count, golden; opaque bytes unchanged; NaN alpha throws nonFiniteValue.
- MT-5 FlareBudgetTests: QB-L5 hit ≤10 ms, QB-L6 render list ≤20 ms, QB-L7 drag ≤10 ms, QB-L8 SVG frame <1 s, Lottie 300 frames <10 s; scene shape asserted.

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- Packet read from branch docs/core-packets-wave2 (PR #310 not merged yet); the issue says so.
- Builder branches are `lead/motion-tracks-<id>`: `lead/motion-tracks/<id>` would collide with the `lead/motion-tracks` ref.
- `gh` has no valid token in this session; agents open PRs and set labels with the GitHub MCP tools.

- Waves follow the packet: a = MT-1 + MT-2 (disjoint files), b = MT-3, c = MT-4 (LottieExporter.swift chain), d = MT-5 (feature-done).
- Builders run from an adapted copy of build-wave.js (branch names, MCP PR opening); the template itself is unchanged.

- The container restarted at ~05:00Z; the 15-minute heartbeat loop died with it, so Belt saw a stall. Restarted the heartbeat.
- The GitHub MCP server appends an attribution footer to PR bodies; builders must strip it with update_pull_request after opening.
- Baseline scripts/ci on f05665f failed two timing budgets (RetouchBoundsTests, EngineStressTests) under load 18 on 4 cores; contention, not code.

## Open
- none yet
