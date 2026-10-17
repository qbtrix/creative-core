# Feature packet: motion-tracks

**Feature:** what Flare needs to show and export motion over time. The onion
skin frames around the playhead; Lottie export of a layer's opacity,
rotation and scale tracks, and of gradient stop alpha; and the core budgets
for the stage and export on the blueprint's `reference` scene.
**Line:** `line:core` · **Wave:** 2 (`waves.md`) · **Lead branch:** `lead/motion-tracks`

**Covers:** #218 (LC-9, G46), #227 (LC-13, G52), #228 (LC-14). #218 closes
with MT-1, #227 with MT-4, #228 with MT-5.

**Unblocks:** Flare (qbtrix/creative-apps `docs/blueprints/flare.md`
section 7.5): LM-8 `LiveOnion` (needs LC-9) and LM-13a `LiveExport` (needs
LC-13), which IN-3 and IN-7 make live; and the QB-L5 to QB-L8 model budgets
that IN-1 and IN-7 assert.

**Depends on:** nothing open. Base: `origin/dev` f05665f. #228's
`Depends on: #213, #214, #173, #219` are all closed (stage-geometry and
edit-commands).

**Source:** Flare blueprint section 7.4 (rows LC-9, LC-13, LC-14), its
fixture table (`reference`: 20 layers, 1,000 shapes, 300 frames, every
property keyed, 50 instances of a two-level nested symbol), creative-apps
`docs/review-rubric.md` section 6 (QB-L5 to QB-L8), `docs/design/suite.md`
rows G46 and G52, and the public Lottie format docs. Where an issue body and
this packet differ, this packet wins.

**Existing work:** no open PR or branch covers these issues (checked against
`origin/dev` f05665f on 2026-10-16). On `dev`: `LottieExporter` animates only
position (split `x` and `y`, #82) and samples scale, rotation and opacity at
frame 0; it writes gradient stops as offset and RGB and says so in its
header ("Gradient stop alpha is not written"). Three of LC-14's four budgets
already exist on seeded scenes: `StageBudgetTests` (QB-L5, QB-L6, SG-8) and
`DragStepBudgetTests` (QB-L7, EC-10). No export budget exists.

## Journey steps

Proven on FlareCore values in `Tests/FlareCoreTests/`:

1. Onion at frame 10 with 2 before and 2 after in a 48-frame scene gives
   [8, 9, 11, 12]; at frame 1 it gives [0, 2, 3]; at frame 47 it gives
   [45, 46].
2. A layer whose opacity goes 1 to 0 and rotation 0 to 90 over frames 0 to
   24 exports animated `ks.o` (100 to 0) and `ks.r` (0 to 90) keyframes with
   its easing, and the exported JSON equals the golden.
3. A layer scaled 1 to 2 on both axes with keys at the same frames exports
   one animated `ks.s`, [100, 100] to [200, 200]. Keys at different frames
   export one linear key per frame across their span, each equal to the
   sampled scale.
4. A linear gradient with a stop at alpha 0.25 exports its alpha stops after
   the color stops; an opaque gradient exports the same bytes as today.
5. On the `reference` scene, one render list, one hit and one drag step stay
   within QB-L5 to QB-L7, an SVG frame within 1 s and the 300-frame Lottie
   export within 10 s, in debug.

## Screens and states

| Query or output | Empty | Error | Loading |
|---|---|---|---|
| `Timeline.onionFrames` | `durationFrames` ≤ 0, or 0 before and 0 after: `[]` | never throws; negative counts count as 0 and counts above `maxOnionSkins` (1,000) as it; frames outside `0..<durationFrames` are dropped, not repeated; no count or frame overflows Int | – |
| Lottie `ks.o`, `ks.r` | a track with 0 or 1 keys: a static value sampled at frame 0, the same bytes as today | a non-finite value throws `nonFiniteValue`, as today | – |
| Lottie `ks.s` | both scale tracks with 0 or 1 keys: static, as today | a per-frame bake longer than `LottieExporter.maxBakedKeys` throws `unsupported("scale track")` rather than write a huge file or drop the motion | – |
| Gradient stops | every stop opaque: no alpha stops, today's bytes | a non-finite alpha throws `nonFiniteValue` | – |
| `FlareBudgetTests` | – | a median over its budget fails | – |

## Contract slice

New public API. Names are binding for the lead and builders.

```swift
// Onion.swift (MT-1), evaluation layer
extension Timeline {
    /// The frames an onion skin shows around `frame`: up to `before` frames
    /// before it and `after` after it, ascending, without `frame` itself,
    /// clamped to `0..<durationFrames` (frames past an edge are dropped).
    /// Negative counts count as 0.
    public static func onionFrames(at frame: Int, before: Int, after: Int, durationFrames: Int) -> [Int]
}
// LottieExporter.swift (MT-3): public static let maxBakedKeys = 10_000
// No other public API changes: MT-2 to MT-4 change what `export` writes.
```

**Approved deviation (MT-1).** The issue and G46 name
`Layer.onionFrames(at:before:after:)`, but that reads nothing from the layer
and a layer has no duration to clamp to, while G46 says "clamped to the
scene". So it is a `Timeline` function beside `playbackFrame`, taking the
owner's `durationFrames` (a scene's, or a symbol's when editing in place).
Flare's LM-8 calls this name.

**Lottie mapping** (public Lottie docs; `sortedKeys` output as today):

- Opacity: `ks.o`, the track value clamped to 0...1 times 100, as the static
  value is today. Rotation: `ks.r` in degrees, as today. Each animated as
  `LottieScalar` already does for position: `a` 1, one keyframe per track
  key with `t`, `s`, and `h` 1 for hold or `o`/`i` tangents.
- Scale: `ks.s` is one 2-D property (Lottie splits only position). When one
  scale track has keys and the other has 0 or 1, the keys come from the
  first and the other value is constant. When both have keys at the same
  frames with the same easing, they share keyframes `s: [x × 100, y × 100]`.
  Otherwise the exporter bakes one linear keyframe per integer frame from
  the first key to the last, clamped to `0..<durationFrames`, each from
  `layer.sample(at:)`, which is exact at every frame a player shows.
- Gradient alpha: `g.k` is the color stops `[offset, r, g, b]` for each stop,
  then, only when some stop alpha is under 1, `[offset, alpha]` for each
  stop. `g.p` stays the stop count.

Instance groups inside a layer keep their transforms sampled at the symbol
frame, as today; animated tracks inside symbols are not in this packet.

## Pseudocode

```
MT-1 onionFrames(frame, before, after, d):
  guard d > 0 else []
  lo = max(0, frame - clamp(before, 0, maxOnionSkins))   # saturating subtract and add, so Int.max
  hi = min(d - 1, frame + clamp(after, 0, maxOnionSkins)) # counts and Int.min frames never overflow
                                                          # the 1,000 cap bounds the result in long scenes
  [lo...hi] without frame, ascending; [] when lo > hi

MT-2 LottieLayer: o = LottieScalar(tracks["opacity"], at0:, map: { clamp(v, 0, 1) * 100 })
                  r = LottieScalar(tracks["rotation"], at0:, map: identity)
  # 0 or 1 key: .fixed(at0 mapped), the same JSON as today's LottieStatic

MT-3 scale: xs = tracks["scaleX"], ys = tracks["scaleY"]
  if xs.count <= 1 && ys.count <= 1: static [x0 * 100, y0 * 100]          # today
  else if one has <= 1 key: keys of the other; the constant one fills its slot
  else if frames and easings match: shared keys s = [x * 100, y * 100]
  else: lo = max(0, first key frame); hi = min(d - 1, last key frame)
        if lo > hi: static [x0 * 100, y0 * 100]          # every key past the end, or d == 0: nothing plays
        guard hi - lo + 1 <= maxBakedKeys else throw unsupported("scale track")
        one linear key per f in lo...hi with s = [sample(f).scaleX * 100, sample(f).scaleY * 100]

MT-4 gradient(stops): alphas = stops.map { try channel($0.color.a) }   # throws on NaN first, as each color does
  k = flat [offset, r, g, b]; if alphas.contains { $0 < 1 }: k += flat [offset, alpha]

MT-5 FlareBudgetTests.reference(): seeded SplitMix64; 20 layers x 50 shapes (StageBudgetTests.shape);
  every layer keys x, y, scaleX, scaleY, rotation, opacity at 0, 150, 299; scene 300 frames;
  symbol "inner" (2 layers x 5 shapes); symbol "outer" holds one instance of "inner";
  50 instances of "outer" spread over the 20 layers. Timings reuse StageBudgetTests.median.
```

## Tasks

Every task is one PR to `dev`: at most 400 changed lines and 15 files, label
`fast-lane`, body lines `Belt-Lead:`, `Feature: motion-tracks`,
`Fast-Check: pass`, `Head:`. MT-5 also carries `feature-done`.

**Shared file.** MT-2, MT-3 and MT-4 all edit
`Sources/FlareCore/Export/LottieExporter.swift`, so they form one chain,
MT-2 → MT-3 → MT-4, each rebased on the one before. Each keeps the file's
header true for its part. MT-1 runs beside the chain.

**Mutation plans.** Each task puts its entries in its own plan file. No
existing entry anchors `LottieExporter.swift`.

**C4 and docs.** MT-1 adds `Sources/FlareCore/Onion.swift` to the
`timeline` part's paths and "onion skin frames" to its description. MT-4
rewrites the `export` part's description to "animated position, scale,
rotation and opacity, and gradient stop alpha". `docs/engineering.md`'s
evaluation list gets `Onion.swift` from `state-machine` SM-1, which owns
that file in this wave.

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| MT-1 | #218 (closes) | `Timeline.onionFrames(at:before:after:durationFrames:)` | `Sources/FlareCore/Onion.swift`, `Tests/FlareCoreTests/OnionTests.swift`, `Tests/mutations/FlareOnion.json`, `docs/c4/parts/creative-core/flarecore/timeline.json` | – | ~120 |
| MT-2 | #227 (part) | Animated opacity and rotation tracks | `Sources/FlareCore/Export/LottieExporter.swift`, `Tests/FlareCoreTests/LottieTracksTests.swift`, `Tests/mutations/FlareLottieTracks.json` | – | ~220 |
| MT-3 | #227 (part) | Animated scale: one-track, shared keys and the per-frame bake; `maxBakedKeys` | `Sources/FlareCore/Export/LottieExporter.swift`, `Tests/FlareCoreTests/LottieScaleTrackTests.swift`, `Tests/mutations/FlareLottieScale.json` | MT-2 | ~240 |
| MT-4 | #227 (closes) | Gradient stop alpha; the `export` C4 description | `Sources/FlareCore/Export/LottieExporter.swift`, `Tests/FlareCoreTests/LottieGradientAlphaTests.swift`, `Tests/mutations/FlareLottieGradientAlpha.json`, `docs/c4/parts/creative-core/flarecore/export.json` | MT-3 | ~140 |
| MT-5 | #228 (closes) | `FlareBudgetTests` on the `reference` scene: QB-L5 to QB-L8; `feature-done` | `Tests/FlareCoreTests/FlareBudgetTests.swift` | MT-4 | ~220 |

Build waves inside the feature: **a** MT-1, MT-2; **b** MT-3; **c** MT-4;
**d** MT-5. After **a**, #218 is closed (LM-8 can start once `main` holds
MT-1); after **c**, #227 (LM-13a); after **d**, #228.

## Acceptance test per task

| id | test | fails when |
|---|---|---|
| MT-1 | `OnionTests`: frame 10 with 2 and 2 in 48 frames gives [8, 9, 11, 12]; frame 1 gives [0, 2, 3]; frame 47 gives [45, 46]; 0 and 0 gives []; -3 counts as 0; a 1-frame scene gives []; `Int.max` counts and `Int.min` frames return without trapping and inside the range | an edge frame repeats or leaks, the playhead frame is listed, or a large count traps |
| MT-2 | `LottieTracksTests`: a one-layer scene with opacity keys (0: 1, 24: 0, ease-in-out) exports `ks.o` equal to a golden JSON string, values 100 and 0, tangents from the easing; rotation keys (0: 0, 12: 45 hold, 24: 90) export `ks.r` with `h` 1 on the hold key; opacity keys outside 0...1 clamp; every existing `LottieExporterTests` golden is byte-identical | a track stays static, a hold is lost, a clamp is missed, or a static export changes |
| MT-3 | `LottieScaleTrackTests`: scaleX keys only gives keys with scaleY's constant in the second slot; both at the same frames and easing gives shared keys [100, 100] to [200, 200] equal to the golden; different frames give one linear key per frame from the first key to the last, each equal to `layer.sample(at:)` × 100; a bake over `maxBakedKeys` throws `unsupported("scale track")`; keys all past the scene end, or a scene of 0 frames, export the static frame-0 value without trapping; all scale-static goldens are unchanged | an axis is dropped, the bake skips a frame or leaves the scene range, or a huge bake is written |
| MT-4 | `LottieGradientAlphaTests`: a linear and a radial gradient with one stop at alpha 0.25 export `g.k` with the color stops then the alpha stops, `g.p` the stop count, equal to a golden; an opaque gradient's bytes equal today's; a NaN alpha throws `nonFiniteValue` | alpha is dropped, `p` counts alpha stops, or an opaque gradient's bytes change |
| MT-5 | `FlareBudgetTests` (below), on a `reference` scene the test checks has 20 layers, 1,000 shapes, 300 frames, all six tracks keyed on every layer, and 50 instances of `outer` | a median exceeds its budget, or the scene drifts from the blueprint's `reference` |

## Quality tests

| quality row | budget (CI gate, debug) | test |
|---|---|---|
| QB-L5 hit per pointer move | ≤ 10 ms median of 50 seeded points on `reference` | `FlareBudgetTests.hitWithinBudget` |
| QB-L6 draw list for one frame | ≤ 20 ms median of 20 frames on `reference` | `FlareBudgetTests.renderListWithinBudget` |
| QB-L7 one drag step (perform and validate) | ≤ 10 ms median of 100 `SetInstanceTransform` steps on `reference` | `FlareBudgetTests.dragStepWithinBudget` |
| QB-L8 export | SVG frame < 1 s; Lottie of the 300-frame scene < 10 s. The PNG half (48 frames at 1080p) is the app's rasterizer (LA-1), not core | `FlareBudgetTests.svgFrameWithinBudget`, `.lottieWithinBudget` |
| QB-L4 with ghosts | app-side (Flare's P4 with onion on); core only supplies the frames | – |
| Old exports keep their bytes | a scene without animated scale, rotation or opacity and without stop alpha exports the same bytes | `LottieExporterTests` (unchanged), `GoldenFileTests` |
| Mutation | every entry in the feature's plan files is caught | `scripts/mutate --run --changed-since <first base>`, run by the lead |

## Done check

- **Journeys green:** `scripts/ci` prints `CI: PASS` on the `dev` SHA that
  holds every merged task, and the CI run on `dev` the `feature-done` PR
  (MT-5) triggers is green (Linux, macOS on Swift 6.1, Mutation).
- **Audit zero new:** no new no-crash lint hit, the jscpd threshold not
  raised, `scripts/mutate --validate` clean, no escaped mutant.
- **Contact sheet:** `Belt-Contact-Sheet: <run link>` on the feature issue,
  one line per acceptance test above, the budget medians, and the test and
  mutation counts.
