# Feature packet: animate-properties

**Feature:** more of a layer animates. Keyframed fill colour, stroke colour
and stroke width per shape, and shape morph (a path keyframed over time,
made compatible on insert so any two keys tween), as commands with exact
undo; sampling of those tracks at any frame with the existing easings; and
export: Lottie writes them as animated properties, SVG writes their values
at the exported frame. Transform and opacity tracks are unchanged.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/animate-properties`
**Status:** planned

**Covers:** beta-80 plan row E14 ("animate more properties: colour, fill,
stroke keys; shape morph"); Flare map row "key colour, fill, stroke and path
(shape morph)" ("only transform and opacity tracks; shape tween is G48 on
the Later list").

**Depends on:** `engine-contracts` (EC-f: `ColorKeyframe`, `PathKeyframe`,
`ShapeTrack`, `Layer.colorTracks` and `shapeTracks`, `TrackCommands.swift`,
`Sampling+Tracks*.swift` in the `timeline` part, the
`LottieExporter+Tracks.swift` and `SVGExporter+Style.swift` seams);
`path-geometry` (PG-edit's `contours` and `inserting`, for AP-4's
compatibility rule).

**C4:** container `flarecore`, components `document-commands`
(`TrackCommands*.swift`), `timeline` (`Sampling+Tracks*.swift`) and
`export` (the two seam files). No new component.

**Clean-room.** Keyframe interpolation and shape tweening by matching
anchors are public animation technique; Lottie's animated-property encoding
is the published spec. No task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| AP-a | The track commands and samplers exist as documented stubs and every check and a fixture scene (a shape whose fill, stroke and path animate) is written, the checks disabled. | AP-1, AP-2 | `TrackShapeTests` | engine-contracts:EC-f |
| AP-cmd | Setting, moving and removing colour, stroke-width and shape keys are commands with exact undo, a drag on one key merges into one step, and a shape key that doesn't match the track's anchors is made compatible without changing how it draws. | AP-3, AP-4 | `TrackCommandsTests`, `ShapeKeyCompatTests` | AP-a; path-geometry:PG-edit (AP-4) |
| AP-sample | Colour tracks sample between keys with each key's easing in encoded sRGB components, hold where they say, and shape tracks morph anchor by anchor so frame 0 and the last key draw exactly their keys. | AP-5, AP-6 | `ColorSamplingTests`, `MorphSamplingTests` | AP-a |
| AP-export | Lottie writes animated fill colour, stroke colour, stroke width and path keys with their easings, and SVG writes the sampled values at the exported frame, both byte-stable. | AP-7, AP-8 | `LottieTrackExportTests`, `SVGStyleAtFrameTests` | AP-sample |
| AP-z | A walk keys a colour pulse and a square-to-star morph through commands, samples them, exports both formats, undoes to the start, the budgets hold, and the feature is built. | AP-9, AP-10 | `TrackWalkTests`, `TrackBudgetTests` | AP-cmd, AP-export |

`ui_slice: none`: engine only. Its screens: S16 timeline pro (graph editor,
copy keys, motion path) and Flare's inspector keyframe diamonds on colour,
stroke and path rows (W3).

## Journey steps

Engine only. KJ-AP (`TrackWalkTests.walk`, AP-9): on the fixture, key the
fill red at frame 0 and blue at frame 24 with ease-in-out; key stroke width
2 → 8; key the path a square at 0 and a 5-point star at 24 (the square made
compatible: 10 anchors); sample frame 12 (colour the eased midpoint in
encoded sRGB; width 5; every anchor halfway); export Lottie (the `fl.c`,
`st.w` and `sh.ks` keyframes present with `i`/`o` from the easing) and SVG
at frame 12; undo everything back to the static shape.

## Screens and states

None.

## Contract slice

The model types are `engine-contracts`'. This feature adds:

```swift
// Sources/FlareCore/TrackCommands.swift (AP-1 stubs, AP-3 bodies)
public enum TrackTarget: Hashable, Codable, Sendable { case fill(shape: Int), stroke(shape: Int), text(index: Int)  // colour tracks only
    public var key: String { get } }                                         // "fill.<i>", "stroke.<i>", "text.<i>" in Layer.colorTracks
// colour commands: a missing fill/stroke shape throws shapeNotFound(i), a missing text invalidIndex(i)
public struct SetColorKeyframe: LayerCommand { owner, layerID, target: TrackTarget, frame: Int, value: Color, easing: Easing }   // steps on one key merge under one coalesceKey
public struct RemoveColorKeyframe: LayerCommand { owner, layerID, target: TrackTarget, frame: Int }
public struct MoveColorKeyframes: LayerCommand { owner, layerID, target: TrackTarget, frames: [Int], by: Int }                 // all or nothing
// stroke width keys use the existing Double tracks under "strokeWidth.<shape>" and the existing keyframe commands
// Sources/FlareCore/TrackCommands+Shape.swift (AP-1 stubs, AP-4 bodies)
public struct SetShapeKeyframe: LayerCommand { owner, layerID, shape: Int, frame: Int, path: Path, easing: Easing }           // made compatible
public struct RemoveShapeKeyframe: LayerCommand { owner, layerID, shape: Int, frame: Int }
// Sources/FlareCore/Sampling+Tracks.swift (AP-1 stubs, AP-5 colour, AP-6 morph)
extension Layer {
    public func sampledColor(_ target: TrackTarget, at frame: Double) -> Color?        // nil: the track is empty (use the static value)
    public func sampledPath(shape: Int, at frame: Double) -> Path? }
```

## Pseudocode

- **Colour sampling.** Find the segment by binary search (the existing
  `Timeline` lookup); `t` from the left key's easing (`Easing` as today,
  hold returns the left key); interpolate r, g, b, a component-wise in
  encoded sRGB (Lottie players interpolate the encoded components, so the
  stage and the exported file agree); before the first key and after the
  last, hold the end values.
- **Compatibility (AP-4).** A shape track's keys share one structure: the
  same contour count and the same anchor count per contour (through
  `path-geometry`'s `contours`). A new key with fewer anchors gets anchors
  inserted on its longest segments (`inserting`, shape unchanged) until the
  counts match; one with more makes every existing key gain anchors the
  same way, in the same command (so its undo restores them). Contours
  differ in count → the command refuses with a `ModelError` whose message
  says "Shapes with a different number of parts can't morph".
  Start points: rotate a closed contour's anchors to the alignment with the
  least summed squared distance to the previous key.
- **Morph sampling.** Same segment lookup; each anchor's point and handles
  lerp by the eased `t`; nil handles are treated as the anchor's point.
- **Lottie.** `fl.c` and `st.c` as animated `[r, g, b, a]` keyframes, `st.w`
  as an animated number, `sh.ks` as animated shape values (vertices, in and
  out tangents relative to vertices, closed); each key's `i`/`o` from its
  easing (hold: `h: 1`), the same writer `LottieExporter` uses for position.
- **SVG.** The exported frame's sampled fill, stroke colour, stroke width
  and path replace the static values, through `SVGExporter+Style.swift`.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| AP-1 | feature issue | The command and sampler stubs with their ids in `TrackCommands.all`; `TrackShapeTests` | `Sources/FlareCore/TrackCommands.swift`, `Sources/FlareCore/TrackCommands+Shape.swift`, `Sources/FlareCore/Sampling+Tracks.swift`, `Tests/FlareCoreTests/TrackShapeTests.swift` | engine-contracts:EC-f | ~200, 4 |
| AP-2 | – | Checks first: the six suites disabled by name (and `TrackCommandsTests`' `undoSteps` and `expectedIDs`); the fixture scene | `Tests/FlareCoreTests/TrackCommandsTests.swift`, `Tests/FlareCoreTests/ShapeKeyCompatTests.swift`, `Tests/FlareCoreTests/ColorSamplingTests.swift`, `Tests/FlareCoreTests/MorphSamplingTests.swift`, `Tests/FlareCoreTests/LottieTrackExportTests.swift`, `Tests/FlareCoreTests/SVGStyleAtFrameTests.swift`, `Tests/FlareCoreTests/Fixtures/tracks.flare` | AP-1 | ~380, 7 |
| AP-3 | – | Colour key commands; turns on `TrackCommandsTests` | `Sources/FlareCore/TrackCommands.swift`, `Tests/FlareCoreTests/TrackCommandsTests.swift`, `Tests/mutations/FlareTrackCommands.json` | AP-2 | ~300, 3 |
| AP-4 | – | Shape key commands with the compatibility rule; turns on `ShapeKeyCompatTests` | `Sources/FlareCore/TrackCommands+Shape.swift`, `Tests/FlareCoreTests/ShapeKeyCompatTests.swift`, `Tests/mutations/FlareShapeKeys.json` | AP-2, path-geometry:PG-edit | ~340, 3 |
| AP-5 | – | `sampledColor`; turns on `ColorSamplingTests` | `Sources/FlareCore/Sampling+Tracks.swift`, `Tests/FlareCoreTests/ColorSamplingTests.swift`, `Tests/mutations/FlareColorSampling.json` | AP-2 | ~160, 3 |
| AP-6 | – | `sampledPath` in a second file; turns on `MorphSamplingTests` | `Sources/FlareCore/Sampling+TracksMorph.swift`, `Tests/FlareCoreTests/MorphSamplingTests.swift`, `Tests/mutations/FlareMorphSampling.json` | AP-2 | ~160, 3 |
| AP-7 | – | Lottie animated colour, width and shape keys; turns on `LottieTrackExportTests` | `Sources/FlareCore/Export/LottieExporter+Tracks.swift`, `Tests/FlareCoreTests/LottieTrackExportTests.swift`, `Tests/mutations/FlareLottieTrackExport.json` | AP-5, AP-6 | ~300, 3 |
| AP-8 | – | SVG values at the frame; turns on `SVGStyleAtFrameTests` | `Sources/FlareCore/Export/SVGExporter+Style.swift`, `Tests/FlareCoreTests/SVGStyleAtFrameTests.swift`, `Tests/mutations/FlareSVGStyleAtFrame.json` | AP-5, AP-6 | ~160, 3 |
| AP-9 | – | KJ-AP walk; `TrackBudgetTests` (release, `.serialized`) | `Tests/FlareCoreTests/TrackWalkTests.swift`, `Tests/FlareCoreTests/TrackBudgetTests.swift` | AP-3, AP-4, AP-7, AP-8 | ~180, 2 |
| AP-10 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/animate-properties.md` | AP-9 | ~5, 1 |

`Sampling+TracksMorph.swift` matches EC-6's `Sampling+Tracks*.swift` glob,
so AP-5 and AP-6 share no file and need no part edit.

## Build waves

- Wave 1: AP-1. Independent in this wave: AP-1 alone.
- Wave 2: AP-2. Independent in this wave: AP-2 alone.
- Wave 3: AP-3, AP-4, AP-5, AP-6. Independent in this wave: all four (AP-4 once path-geometry's PG-edit has merged).
- Wave 4: AP-7, AP-8. Independent in this wave: both.
- Wave 5: AP-9. Independent in this wave: AP-9 alone.
- Wave 6: AP-10 (`feature-done`, final). Independent in this wave: AP-10 alone.

Longest chain: AP-1 → AP-2 → AP-5 → AP-7 → AP-9 → AP-10 (6). Chain of 6:
the checks need the stubs, the exporter writes what the sampler reads, the
walk exports, AP-10 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| AP-1 | `TrackShapeTests`: the ids are registered; `TrackTarget.key` strings | a signature is missing | none |
| AP-2 | suites compile, disabled; the fixture validates | – | – |
| AP-3 | `TrackCommandsTests`: set, move and remove with exact undo; a drag on one key merges; a move past the duration refuses all of it; a NaN colour refused; a locked layer refused; in `UndoPropertyTests` | undo leaves a trace or a move is partial | `FlareTrackCommands`: merge across frames → `TrackCommandsTests.mergeOnlySameKey`; move clamps per key → `.moveAllOrNothing`; keys left unsorted after a move → `.keysStaySorted` |
| AP-4 | `ShapeKeyCompatTests`: a square key on a star track gains anchors and still draws the square (flattened points within 1e-9); a star key on a square track gives every square key the same anchors and undo restores them; different contour counts refused with the sentence; start-point alignment picks the least-distance rotation | a morph target changes shape or undo misses a key | `FlareShapeKeys`: anchors inserted on the shortest segments → `ShapeKeyCompatTests.insertsOnLongestSegments`; existing keys not upgraded → `.existingKeysGainAnchors`; alignment uses rotation 0 always → `.alignsStartPoint` |
| AP-5 | `ColorSamplingTests`: midpoint of red to blue under linear easing is (0.5, 0, 0.5) in encoded sRGB; ease-in-out at 0.25 matches `Easing`'s value; hold returns the left key; before the first and after the last hold the ends; empty is nil | the colour space or easing is wrong | `FlareColorSampling`: interpolate in linear light → `ColorSamplingTests.encodedComponents`; easing ignored → `.easingApplies`; hold not honoured → `.holdKeepsLeft` |
| AP-6 | `MorphSamplingTests`: at each key's frame the path equals the key exactly; at the midpoint each anchor is halfway; nil handles lerp as points | a key frame draws a blend | `FlareMorphSampling`: segment lookup off by one at a key frame → `MorphSamplingTests.keyFrameIsExact`; handles not lerped → `.handlesLerp` |
| AP-7 | `LottieTrackExportTests`: `fl.c`, `st.c`, `st.w` and `sh.ks` keyframes with `t`, `s`, and `i`/`o` from each easing; hold as `h: 1`; tangents relative to vertices; byte-stable | a key or tangent is written wrong | `FlareLottieTrackExport`: tangents absolute → `LottieTrackExportTests.tangentsRelative`; colour written 0…255 → `.colourUnitRange` |
| AP-8 | `SVGStyleAtFrameTests`: the exported frame's sampled fill, stroke and path; frame 0 equals the static export when nothing is keyed | the frame's values aren't used | `FlareSVGStyleAtFrame`: static colour used → `SVGStyleAtFrameTests.usesSampledColour`; path not sampled → `.usesSampledPath` |
| AP-9 | `TrackWalkTests.walk` (KJ-AP); `TrackBudgetTests`: sampling 1,000 colour and 200 morph tracks for one frame ≤ 2 ms; Lottie export of the reference scene with them ≤ 1.2 × without (release, reported) | the walk's checks fail | none |
| AP-10 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Scrub a busy scene | 1,000 colour + 200 morph tracks sampled ≤ 2 ms per frame | `TrackBudgetTests.sampleFrame` (release, reported) |
| Exact undo | every track command in the cross-family property | `UndoPropertyTests` |
| Keys are exact | a key's frame samples to the key | `ColorSamplingTests`, `MorphSamplingTests` |
| Old files load | a file without tracks samples as static | `TrackShapeTests.staticWhenEmpty` |

## Done check

Per slice as usual. No Mac finisher. Then the contact sheet with the walk's
Lottie output size and the sampling budget.

## Adopted later

- **W2:** S16 timeline pro (graph editor, copy keys, zoom, motion path) for
  Flare and Halo shows these tracks.
- **W3:** Flare's inspector diamonds on fill, stroke and path rows (F+2.6);
  Halo's colour keys reuse `colorTracks` at one adopt slice.

## Not in this packet

Gradient stop animation, trim-path animation (S17's trim fields key through
the existing Double tracks once S17 adds them), expressions, per-character
text animation (S21).
