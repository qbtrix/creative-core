# Feature packet: raster-throughput

**Feature:** whole-image raster work at display speed. 8-bit display bytes
encoded and decoded through tables instead of a `pow` and a `try` per
component, an encode of one region, and a composite that writes into the
backdrop in place, so Photo's Copy, Paste, Merge Down and Flatten of a
12 MP layer, and every brush tile Photo shows, stop paying a per-pixel
conversion and a whole-buffer copy. Also the clone dab budget that fails
`scripts/ci` under a parallel test load.
**Line:** `line:core` · **Wave:** 2 (`waves.md`) · **Lead branch:** `lead/raster-throughput`

**Covers:** #309 (needs-core from Photo, PB-15 and PB-16), #300 (gap, the
`smallDabOn12MegapixelsIsFast` budget). #309 closes with RT-5, #300 with
RT-4.

**Unblocks:** creative-apps `photo-edit` (PV-2, #1075): its PB-15 and PB-16
release gates in `MT/PhotoEditBudgetTests.swift`. Also the brush tile path
(PB-1): `renderedTiles` in Photo's `Sources/PhotoModel/PhotoRender.swift`
calls `rgba8()` on every damaged tile, each in its own child task, so the
per-pixel `pow` the brush profile showed on worker threads goes with RT-2.
creative-apps adopts it in one PR (see "App adoption" below).

**Depends on:** nothing open. Base: `origin/dev` f05665f.

**Source:** #309 (its numbers, API and acceptance), #300, and creative-apps
`docs/blueprints/photo.md` section 7.1 (rows PB-15 and PB-16). Where an issue
body and this packet differ, this packet wins.

**Existing work:** no open PR or branch covers these issues (checked against
`origin/dev` f05665f on 2026-10-16; the only open PR is #307, docs). Photo
already works around the cost on its side: `Sources/PhotoModel/TiledPixelsBytes.swift`
builds its own sRGB tables from CoreRaster calls (`SRGBBytes.linear`,
`least`, `start`) and runs them per tile across the cores, and
`Sources/PhotoModel/PhotoLayerComposite.swift` composites one 256 px tile at
a time so each copy is a tile, not the picture. RT-1 moves the table idea
into the engine, where it can also cover Display P3, so the app deletes its
copy.

## Where the time goes on `dev`

Checked against the code on f05665f:

- `rgba8(colorSpace:)` (`DisplayBytes.swift`) calls `Color3.converted` per
  pixel. That validates the input, runs `TransferCurve.encode` (one `pow` per
  channel, `ColorSpace.swift:111`) and validates the result, all behind a
  `try`. `init(rgba8:)` does the same with `decode` (`ColorSpace.swift:105`).
  The decode input is only ever 256 values per channel.
- `composite(_:onto:x:y:mode:opacity:)` (`Composite.swift`) starts with
  `var result = backdrop` (a full copy on the first write), then reads and
  writes each pixel through `pixel(x:y:)` and `setPixel(x:y:_:)`, each a
  bounds check and a `try`.
- `cloned(offset:through:)` (`Retouch.swift`) scans the whole 12 MP mask for
  its covered rect and copies the whole buffer before it writes the dab. In
  debug that takes 0.59 s alone; with the other 750 tests running on 4
  cores the wall clock reached 1.6 to 3.0 s against the 1.5 s budget (#300,
  and the #269 run). The extra time is the parallel load, not the dab.
- Precedent for tables already in CoreRaster: `Adjustments.swift`'s sRGB tone
  mapping tabulates encode, map, decode once per call (`toneTableSteps`), and
  `mappingPixels` is the non-throwing one-pass loop over storage (#248).

`Histogram.swift` also encodes per pixel for its sRGB axis. It is not on the
brush, copy or merge path (Curves no longer recounts per pointer sample), so
it is not in this packet; it can adopt `DisplayTransfer` later.

## Journey steps

Proven on 4000 x 3000 buffers in `Tests/CoreRasterTests/`, against a frozen
copy of today's per-pixel code kept in the test file (the `fullPassClone`
pattern in `RetouchBoundsTests.swift`):

1. Copy: a 12 MP layer's `rgba8()` gives exactly today's bytes, in sRGB and
   in Display P3, within 30 ms on one core in release.
2. Paste: those bytes through `init(rgba8:)` give exactly today's
   components, within 30 ms on one core.
3. A region: `rgba8(x:y:width:height:)` of a 256 px tile equals
   `cropped(...)` then `rgba8()`, with no crop copy.
4. Merge Down: an upper 12 MP layer composited in place onto the lower one
   equals today's `composite(_:onto:x:y:mode:opacity:)`, within 60 ms on one
   core. Flatten (two composites over three layers) equals today's result.
5. Four cores: four 4000 x 750 bands run at once take at most 10 ms to
   encode, 10 ms to decode and 20 ms to composite.
6. A 64 x 64 clone dab on 12 MP stays within 1.5 s of its own thread's CPU
   time while the full test suite runs.

## Screens and states

The "screens" are the public calls. Each one must answer every state without
crashing, and give the same result as today's code.

| Call | Empty | Error | Loading |
|---|---|---|---|
| `DisplayTransfer(_:)` | – | a space other than `.sRGB` or `.displayP3` throws `ColorError.invalid` | the tables build once, on first use, from `TransferCurve` (thread-safe `static let`) |
| `DisplayTransfer.encode(_:)` | – | never throws: a component past 0...1 clamps; NaN gives byte 0 (callers never pass one; it must not trap) | – |
| `rgba8(colorSpace:)` | – | a space outside `displayColorSpaces` throws `RasterError.invalid`, as today; a fully transparent pixel encodes 0, 0, 0, 0; a tiny alpha whose unpremultiply overflows Float clamps to the largest finite value, as today | – |
| `rgba8(x:y:width:height:colorSpace:)` | – | a width or height under 1, or a rect not wholly inside the buffer, throws `RasterError.invalid` with `cropped`'s wording | – |
| `init(rgba8:width:height:colorSpace:)` | – | a bad size, byte count or space throws `RasterError.invalid`, as today | – |
| `composite(_:x:y:mode:opacity:)` (in place) | a source with no overlap leaves the buffer unchanged | an opacity outside 0...1 or not finite throws before any change; a result that overflows to infinity throws with `setPixel`'s message for the first such pixel in row order (see "Approved deviation") | – |

## Contract slice

New public API. Names are binding for the lead and builders; doc comments
may add, not rename.

```swift
// CoreColor/DisplayTransfer.swift (RT-1)
/// 8-bit display encoding of linear sRGB in sRGB or Display P3, by table.
/// Bit for bit the same as `Color3.converted` followed by DisplayBytes'
/// clamp and round, without a `pow` or a `throw` per value.
public struct DisplayTransfer: Sendable, Hashable {
    public let space: ColorSpace                 // .sRGB or .displayP3
    public init(_ space: ColorSpace) throws      // ColorError.invalid for any other space
    /// == try Color3(Double(r) / 255, Double(g) / 255, Double(b) / 255)
    ///        .converted(from: space, to: .linearSRGB)
    public func decode(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Color3
    /// For a finite color: each component of
    /// (try linear.converted(from: .linearSRGB, to: space)).clampedToUnit(),
    /// times 255, rounded to nearest. NaN gives 0.
    public func encode(_ linear: Color3) -> (UInt8, UInt8, UInt8)
    /// A value clamped to 0...1, times 255, rounded to nearest: the alpha rule.
    public static func byte(_ value: Double) -> UInt8
}

// CoreRaster/DisplayBytes.swift (RT-2): same signatures, same results, faster
extension PixelBuffer {
    public func rgba8(colorSpace: ColorSpace = .sRGB) throws -> [UInt8]          // = the whole-buffer region
    public func rgba8(x: Int, y: Int, width: Int, height: Int,
                      colorSpace: ColorSpace = .sRGB) throws -> [UInt8]         // new
    public init(rgba8 bytes: [UInt8], width: Int, height: Int,
                colorSpace: ColorSpace = .sRGB) throws
}

// CoreRaster/Composite.swift (RT-3)
extension PixelBuffer {
    /// Composites `source` over this buffer with source pixel (sx, sy) on
    /// pixel (x + sx, y + sy), in place. Same pixels and same throws as
    /// `composite(_:onto:x:y:mode:opacity:)`.
    public mutating func composite(_ source: PixelBuffer, x: Int, y: Int,
                                   mode: BlendMode, opacity: Float) throws
}
// Both free `composite` functions stay, unchanged in signature: each copies
// the backdrop and calls the method, so there is one loop, not two.
// PixelBuffer.swift (RT-3): one internal writer,
//   mutating func writeRow(_ values: ArraySlice<Float>, x: Int, y: Int)
// with `copyRows`' contract (the caller checked the span and that every
// value is finite); the file header lists it among the writers.
```

**Approved deviation (RT-3).** CoreRaster's mutating calls so far leave the
buffer unchanged when they throw. The in-place composite does that for a bad
opacity, but not for a result that overflows to infinity: rows above the
failing row already hold the composite, the rest are untouched, and every
stored component stays finite. Keeping the old pixels would need a full copy
of the overlap or a second pass, which is the cost this method exists to
remove. Only extreme inputs reach it (a straight value past Float's range
after unpremultiplying a tiny alpha). A caller that needs the old pixels
after a throw uses the free function, which composites a copy.

**App adoption (creative-apps, one PR, after `main` holds RT-5).**

| Photo file | today | after |
|---|---|---|
| `Sources/PhotoModel/TiledPixelsBytes.swift` | `SRGBBytes.tile` decodes through its own `linear` table and `setPixel`; `SRGBBytes.bytes` encodes through `least` / `start` | gather a tile's rows (256 KB) and call `PixelBuffer(rgba8:width:height:)`; call `tile.rgba8()`. `SRGBBytes`' tables are deleted; `thumbnail` reads `DisplayTransfer(.sRGB).decode` |
| `Sources/PhotoModel/PhotoLayerComposite.swift` | `piece = try CoreRaster.composite(tiled.tiles[hit.tile], onto: piece, x:, y:, mode:, opacity:)` | `try piece.composite(tiled.tiles[hit.tile], x:, y:, mode:, opacity:)` |
| `Sources/PhotoModel/PhotoRender.swift` | `rgba8()` per damaged tile in `renderedTiles` | unchanged call, now table-based |

## Pseudocode

```
RT-1 DisplayTransfer
  decodeTable[b] = TransferCurve.decode(Double(b) / 255)   for b in 0...255   # same Double op as converted
  decode(r, g, b): c = Color3(decodeTable[r], decodeTable[g], decodeTable[b])
                   space == .displayP3 ? Matrix3.linearSRGBFromP3 * c : c      # the same internal matrix and order
  step(v) = byte(clamp(TransferCurve.encode(v), 0, 1))     # today's rule; monotonic in v
  least[k] for k in 1...255 = the smallest Double v in 0...1 with step(v) >= k, by bisection on the
          bit patterns of non-negative Doubles (their order is their values' order)
  encodeComponent(v): count of least[k] <= v   (branchless 8-step search; NaN compares false -> 0)
  encode(c): p = space == .displayP3 ? Matrix3.p3FromLinearSRGB * c : c
             (encodeComponent(p.c0), encodeComponent(p.c1), encodeComponent(p.c2))

RT-2 rgba8(x, y, w, h, space)
  check space; check rect as `cropped` does; t = DisplayTransfer(space)
  for row in y..<y+h: for each pixel of the row span in `components`:
    s = RGBA(...).unpremultiplied()                               # same Float division as today
    (r, g, b) = t.encode(Color3(finite(s.r), finite(s.g), finite(s.b)))
    a = DisplayTransfer.byte(Double(s.a))
  rgba8(space) = rgba8(0, 0, width, height, space)
  init(rgba8:): per pixel c = t.decode(r, g, b); RGBA(Float(c.c0), ..., a: Float(bytes[i + 3]) / 255).premultiplied()
    storage built in one pass; init(checkedWidth:height:storage:)   # no setPixel, no try per pixel

RT-3 composite in place (self is the backdrop)
  guard (0...1).contains(opacity) else throw                       # before any change
  clip the overlap rows and columns once (the same guards as today)
  for each overlap row:
    if mode == .normal, opacity == 1, every source alpha in the row span == 1:
      writeRow(source row span)                                    # equals the general formula by ==
    else:
      scratch[i] = sourceOver(source px, self px, mode, opacity)  # today's private per-pixel function
      if any scratch component is not finite: throw setPixel's message for the first one
      writeRow(scratch)
  free composite(source, onto: b, x, y, mode, opacity): var r = b; try r.composite(source, x, y, mode, opacity); return r

RT-4 smallDab budget: measure the test thread's CPU time (clock_gettime CLOCK_THREAD_CPUTIME_ID,
  from Glibc or Darwin, in a Support.swift helper) instead of the wall clock; the budget stays 1.5 s
```

## Tasks

Every task is one PR to `dev`: at most 400 changed lines and 15 files, label
`fast-lane`, body lines `Belt-Lead:`, `Feature: raster-throughput`,
`Fast-Check: pass`, `Head:`. RT-5 also carries `feature-done`.

**Mutation plans.** RT-2 owns `Tests/mutations/CoreRaster.json` in this
wave: its three `DisplayBytes.swift` entries move with the code (the
truncate-instead-of-round entry follows the byte rule to
`DisplayTransfer.swift` and keeps its `DisplayBytesTests` filter; the
premultiply and color-space entries get new anchors that still plant those
bugs). RT-3 keeps `sourceOver` and the opacity guard text unchanged, so the
three `Composite.swift` entries stay valid and RT-3 does not edit that file.
`CoreColor.json` anchors the `pow` lines in `ColorSpace.swift`, which RT-1
leaves alone (the tables derive from them). Every new entry goes in the
task's own plan file.

**C4.** No new CoreRaster file. `DisplayTransfer.swift` is owned by the
`color-spaces` component through its `Sources/CoreColor/` folder entry; RT-1
adds "8-bit display tables" to its description. RT-2 and RT-3 add the region
encode and the in-place composite to the `pixel-buffer` and `compositing`
descriptions.

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| RT-1 | #309 (part) | `DisplayTransfer`: decode table, encode thresholds, the byte rule; an exhaustive release-only check of the sRGB encode | `Sources/CoreColor/DisplayTransfer.swift`, `Tests/CoreColorTests/DisplayTransferTests.swift`, `Tests/mutations/CoreColorDisplayTransfer.json`, `docs/c4/parts/creative-core/corecolor/color-spaces.json` | – | ~300 |
| RT-2 | #309 (part) | `rgba8` and `init(rgba8:)` over `DisplayTransfer`, one pass, no `try` per pixel; `rgba8(x:y:width:height:colorSpace:)` | `Sources/CoreRaster/DisplayBytes.swift`, `Tests/CoreRasterTests/DisplayBytesFastPathTests.swift`, `Tests/mutations/CoreRaster.json`, `Tests/mutations/CoreRasterDisplayBytes.json`, `docs/c4/parts/creative-core/coreraster/pixel-buffer.json` | RT-1 | ~300 |
| RT-3 | #309 (part) | In-place `composite(_:x:y:mode:opacity:)`; the free functions call it; the opaque `.normal` row copy; `writeRow` | `Sources/CoreRaster/Composite.swift`, `Sources/CoreRaster/PixelBuffer.swift`, `Tests/CoreRasterTests/CompositeInPlaceTests.swift`, `Tests/mutations/CoreRasterCompositeInPlace.json`, `docs/c4/parts/creative-core/coreraster/compositing.json` | – | ~300 |
| RT-4 | #300 (closes) | `smallDabOn12MegapixelsIsFast` times its own thread's CPU time; the helper in `Support.swift` | `Tests/CoreRasterTests/RetouchBoundsTests.swift`, `Tests/CoreRasterTests/Support.swift` | – | ~60 |
| RT-5 | #309 (closes) | The release budgets on one core and on four; `feature-done` | `Tests/CoreRasterTests/RasterThroughputBudgetTests.swift` | RT-2, RT-3 | ~180 |

Build waves inside the feature: **a** RT-1, RT-3, RT-4 (disjoint files);
**b** RT-2; **c** RT-5. After **a**, #300 is closed; after **c**, #309.

## Acceptance test per task

| id | test | fails when |
|---|---|---|
| RT-1 | `DisplayTransferTests`: `decode` equals `Color3.converted` with `==` on every byte for sRGB (the channels are independent), and for Display P3 on every gray, every one-channel ramp with the other two at 0, 128 and 255, and 100,000 seeded triples; `encode` equals the reference (converted, `clampedToUnit`, times 255, rounded) on 1,000,000 seeded Doubles in -0.5...1.5 and on both sides of every threshold (`least[k]` gives k, its next-lower Double gives k - 1) for both spaces; NaN gives 0 and ±infinity clamps; `DisplayTransfer(.oklab)` throws. Release only (`.serialized`, `.enabled(if: optimized)`): every Float in 0...1 encodes in sRGB to the reference byte | a table entry is off by one, the P3 matrix is skipped or applied in the wrong order, a threshold sits one value off, or a NaN traps |
| RT-2 | `DisplayBytesFastPathTests`, against a private copy of today's two loops: for sRGB and Display P3, a buffer of every byte value per channel (gray and one-channel ramps) at alpha 0, 1, 128 and 255 decodes to equal components and encodes back to equal bytes; 50 seeded `randomPixel` buffers and pixels with alpha 1e-38 or 1e-45 (the overflow clamp) encode equally; `rgba8(x:y:width:height:)` equals `cropped` then `rgba8` for each tile of a 600 x 300 buffer and for 1 x 1 corners; a rect hanging off any edge, a zero size and a bad space throw; every existing `DisplayBytesTests` passes unchanged | one byte differs, the region reads the wrong rows, or a bad rect is accepted |
| RT-3 | `CompositeInPlaceTests`, against a private copy of today's per-pixel loop: every `BlendMode` at opacities 0, 0.37 and 1, with sources hanging off each edge and corner and a source wholly outside, equals the reference with `==`; the free functions give the same; an opacity of NaN, -0.1 or 1.1 throws and changes nothing; a source pixel with alpha 1e-45 and a color of 1e30 throws in both, with the same message, and leaves every component of the in-place buffer finite; an opaque `.normal` source at opacity 1 equals the reference, and so does one whose row holds a single pixel of alpha 0.999; every existing `CompositeTests`, `CompositeOffsetTests` and `CompositeOffsetAdversarialTests` passes unchanged | a pixel differs, a throw case differs, a non-finite value is stored, or the row copy takes a row that is not opaque |
| RT-4 | `smallDabOn12MegapixelsIsFast` asserts the thread CPU time of the `cloned` call is under 1.5 s and keeps its four pixel checks; `scripts/ci` prints `CI: PASS` three runs in a row on a 4-core Linux box with nothing else running; the helper is checked once against a busy loop (its CPU time grows with work and is under the wall clock) | the budget is widened, or the test still fails because the thread waited for a core |
| RT-5 | `RasterThroughputBudgetTests` (below) | a median exceeds its budget |

## Quality tests

CI runs `scripts/ci` in debug, where CoreRaster's loops are about 20 times
slower, so the timing rows below are release gates that the lead runs and
records: `swift test -c release -Xswiftc -enable-testing --filter
RasterThroughputBudgetTests` (FlareCoreTests' `@testable` imports need
`-enable-testing` in release). The suite is `.serialized` and
`.enabled(if: optimized)`, like `ContrastHighlightsTargetTests`; in debug it
is skipped and the equivalence tests above carry the gate.

| quality row | budget (release, best of 3) | test |
|---|---|---|
| PB-15, core part: Copy and Paste of 12 MP | one core: `rgba8()` ≤ 30 ms and `init(rgba8:)` ≤ 30 ms. Four cores (four 4000 x 750 bands through `DispatchQueue.concurrentPerform`): each ≤ 10 ms. That leaves Photo at least 60 ms of its 120 ms | `RasterThroughputBudgetTests.copyAndPasteWithinBudget` |
| PB-16, core part: Merge Down and Flatten of 12 MP | one core: one in-place composite ≤ 60 ms, so Merge Down ≤ 60 ms and Flatten of three layers (two composites) ≤ 120 ms. Four cores (bands as above): ≤ 20 ms per composite. Both far inside 400 ms | `RasterThroughputBudgetTests.mergeAndFlattenWithinBudget` |
| Region encode costs its pixels | one 256 px tile of a 12 MP buffer ≤ 0.5 ms | `RasterThroughputBudgetTests.tileEncodeWithinBudget` |
| Same bytes, same pixels | every equivalence test above, in debug, on every `scripts/ci` run | RT-1 to RT-3 tests |
| The dab budget holds under load | CPU time ≤ 1.5 s in debug, three full runs on 4 cores | `RetouchBoundsTests.smallDabOn12MegapixelsIsFast` |
| Mutation | every entry in the feature's plan files, and the repointed `CoreRaster.json` entries, are caught | `scripts/mutate --run --changed-since <first base>`, run by the lead |

## Done check

- **Journeys green:** `scripts/ci` prints `CI: PASS` on the `dev` SHA that
  holds every merged task, and the CI run on `dev` the `feature-done` PR
  (RT-5) triggers is green (Linux, macOS on Swift 6.1, Mutation).
- **Budgets recorded:** the release run of `RasterThroughputBudgetTests` on a
  4-core Linux box, its medians in the contact sheet, every row within budget.
- **Audit zero new:** no new no-crash lint hit, the jscpd threshold not
  raised (one composite loop, not two), `scripts/mutate --validate` clean,
  no escaped mutant.
- **Contact sheet:** `Belt-Contact-Sheet: <run link>` on the feature issue,
  one line per acceptance test above, the budget medians, and the test and
  mutation counts. Then the lead comments on #309 with the API names from
  "App adoption" so creative-apps can file its one PR.
