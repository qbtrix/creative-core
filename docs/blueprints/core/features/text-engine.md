# Feature packet: text-engine

**Feature:** the platform-free half of the suite's text: styled runs inside
one text shape (font, size, weight, italic, fill, tracking, baseline shift),
paragraph style (alignment including justified, line height, tracking,
paragraph spacing, an optional box width that wraps), and type on a path
(start offset, flip), as commands with exact undo; a layout that turns the
text plus measured glyph advances into lines, baselines and per-grapheme
positions, and onto a path; and SVG export of all of it. Glyph measuring and
drawing are the platform's: the app measures through the suite's
`TextMeasuring` (creative-apps `shell-text`, CoreText) and hands the
advances in, so FlareCore stays Linux-safe and imports nothing.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/text-engine`
**Status:** built. Merged PRs: #567 (TE-1), #614 (TE-2), #615 (TE-3),
#619 (TE-4), #618 (TE-5), #761 (TE-6), #679 (TE-7), #763 (TE-8), the
review fixes #646, #656, #682, #686, #694, #697, #701, and this packet's
closing `feature-done` PR (TE-9, TE-10). Deviations from the text below:
`SVGExporter.export` takes a `measure` closure (default
`FixedAdvances.measure`), so exported lines follow the app's advances
(#701); justified `x` lists hold one value per Unicode scalar, as SVG
counts characters, and each `<text>` is one output line, since a newline
between line spans draws as a space under `xml:space="preserve"` (#763);
`onPath` ignores alignment and lines and measures a multi-contour path end
to end; KJ-TE's "200-unit circle" is a circle of diameter 200 as 32 cubic
arcs from its right point, clockwise (the four-arc ellipse's normals are off
by 1.3e-3), and its first glyph's pen point, not its centre, is the bottom.
`TextBudgetTests` records a release miss as a known issue instead of
failing; on Linux release they ran at 2.0 ms and 0.06 ms. Where this
packet and the code differ, the code and its doc comments win.

**Covers:** beta-80 plan row E8, core half ("styles, line height, tracking,
paragraphs, type on a path"; C4 home flarecore/document-commands
`TextShape`); Halo's text-layer rows, Design's text rows (mixed styles,
text on a path), Photo's and Flare's text rows.

**Depends on:** `engine-contracts` (EC-f: `TextRun`, `ParagraphStyle`,
`TextOnPath` on `TextShape`, `TextStyleCommands.swift`, the
`SVGExporter+Text.swift` seam); `path-geometry` (PG-measure:
`sample(atLength:)` for type on a path, TE-6 only).

**C4:** container `flarecore`, components `document-commands`
(`TextStyleCommands.swift`, `TextLayout*.swift`, named in the part by EC-6)
and `export` (`SVGExporter+Text.swift`). No new component in core. The
measuring and drawing half is creative-apps `suite-shell` ✚`shell-text`
with its contract in `suite-model` (that repo's `shell-text` packet).

**Clean-room.** Line breaking at break opportunities, alignment and
justification are described from public typography and the SVG text and
`textPath` specs (W3C); no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| TE-a | `ResolvedRun`, `GlyphRunMetrics`, `TextLayout`, `PlacedGlyph` and the style commands exist as documented stubs, a fixed-advance metrics fake stands in for the platform, and every later check is written and disabled. | TE-1, TE-2 | `TextShapeTests` | engine-contracts:EC-f |
| TE-cmd | Applying a style to a range splits and merges runs so they never overlap and always cover what they style, editing the string keeps runs on their graphemes, and paragraph and path settings change with exact undo, refused on a locked layer or a bad range. | TE-3, TE-4 | `TextStyleCommandsTests` | TE-a |
| TE-lay | With measured advances, text lays out into lines that wrap at the box width at break opportunities (a long word breaks by grapheme), aligned or justified, with line height, tracking and paragraph spacing, and places each grapheme along a path from the start offset, hiding those past the end. | TE-5, TE-6 | `TextLayoutTests`, `TextOnPathTests` | TE-a; path-geometry:PG-measure (TE-6) |
| TE-svg | SVG writes styled runs as `tspan`s with their font properties, the alignment as `text-anchor` (justified lines as explicit positions), wrapped lines at their baselines, and type on a path as `textPath`, byte-stable. | TE-7, TE-8 | `SVGTextExportTests` | TE-cmd, TE-lay |
| TE-z | A walk styles, wraps, justifies and puts text on a circle through commands and the layout, exports it, undoes to the start, and the feature is built. | TE-9, TE-10 | `TextWalkTests`, `TextBudgetTests` | TE-svg |

`ui_slice: none`: engine only. Its screens are the apps' text tools and
inspectors on SuiteUI's font picker (creative-apps `shell-text` ST-u) and
S21's text animators.

## Journey steps

Engine only. KJ-TE (`TextWalkTests.walk`, TE-9): a text shape "Bring the
light home" at 24 pt; bold applied to "light" (three runs); box width 120
(two lines under `FixedAdvances`); justified (the first line's last
grapheme ends at x 120); line height 1.5 (baseline gap 1.5 × 24); the string
edited to "Bring the warm light home" (bold still on "light"); type on a
200-unit circle at offset 0.25 (first glyph at the circle's bottom, tangent
horizontal); SVG written; undo every step back to the plain shape.

## Screens and states

None.

## Contract slice

The model fields are `engine-contracts`'. This feature adds:

```swift
// Sources/FlareCore/TextLayout.swift (TE-1 stubs, TE-5 body)
public struct ResolvedRun: Sendable, Hashable { public var start: Int, length: Int; public var fontFamily: String; public var fontSize: Double
    public var weight: Int; public var italic: Bool; public var fill: Fill; public var tracking: Double; public var baselineShift: Double }
extension TextShape { public var resolvedRuns: [ResolvedRun] { get } }        // covers the whole string; gaps take the shape's own style
public struct GlyphRunMetrics: Sendable, Hashable { public var advances: [Double]; public var ascent: Double; public var descent: Double
    public init(advances: [Double], ascent: Double, descent: Double) throws }  // finite, ≥ 0
public struct LaidLine: Sendable, Hashable { public var graphemes: Range<Int>; public var baseline: Double; public var x: [Double]; public var width: Double }
public struct TextLayout: Sendable, Hashable { public var lines: [LaidLine]; public var bounds: Rect
    public static let maxGraphemes = 100_000
    public static func lay(_ text: TextShape, measured: [GlyphRunMetrics]) throws -> TextLayout }   // one metrics per resolved run
public enum FixedAdvances { public static func measure(_ text: TextShape) -> [GlyphRunMetrics] }      // 0.5 em per grapheme, ascent 0.8 em, descent 0.2 em
// Sources/FlareCore/TextLayout+Path.swift (TE-1 stub, TE-6 body)
public struct PlacedGlyph: Sendable, Hashable { public var index: Int; public var position: Point; public var degrees: Double }
extension TextLayout { public static func onPath(_ text: TextShape, measured: [GlyphRunMetrics], tolerance: Double) throws -> [PlacedGlyph] }
// Sources/FlareCore/TextStyleCommands.swift (TE-1 stubs, TE-3 bodies)
public struct ApplyTextStyle: LayerCommand { owner, layerID, textIndex, range: Range<Int>, style: TextRunStyle }   // TextRunStyle: the optional fields of TextRun
public struct ClearTextStyle: LayerCommand { owner, layerID, textIndex, range: Range<Int> }
public struct SetParagraphStyle: LayerCommand { owner, layerID, textIndex, paragraph: ParagraphStyle? }    // merges a drag of one field
public struct SetTextOnPath: LayerCommand { owner, layerID, textIndex, onPath: TextOnPath? }
public struct EditTextString: LayerCommand { owner, layerID, textIndex, replacing: Range<Int>, replacement: String /* init label with: */ }   // keeps runs on their graphemes
```

## Pseudocode

- **Graphemes.** Every offset counts `Character`s (extended grapheme
  clusters), never UTF-16 units or bytes, so emoji and combining marks are
  one step.
- **ApplyTextStyle.** Split the runs at `range` bounds; set the given fields
  on the runs inside; merge neighbours whose fields are now equal; drop runs
  that equal the shape's own style. Undo restores the old run list.
- **EditTextString.** Runs before the edit stay; runs after shift by the
  length change; a run cut by the edit shrinks; inserted text takes the
  style of the grapheme before it (the run it extends).
- **lay.** Break opportunities: after whitespace, after a hyphen, and at a
  newline (a hard break that also adds `paragraphSpacing`). Greedy: add the
  next word's advances (plus tracking per grapheme, the run's and the
  paragraph's) while the line fits `boxWidth`; a word alone wider than the
  box breaks by grapheme; trailing spaces don't count toward the width.
  Line height: the gap to a line is `lineHeight × (max ascent + max
  descent)`, each max taken separately over that line's runs; the first
  baseline at the first line's max ascent. Alignment: leading,
  centre and trailing shift `x`; justified spreads the extra width over the
  line's spaces (every line but a paragraph's last). No box: one line per
  paragraph.
- **onPath.** Path length L; start `s = startOffset × L` (flip reverses the
  path); each grapheme's centre at `s + x + advance / 2`; `sample(atLength:)`
  gives the point and the tangent; the glyph's baseline point is the centre
  minus `advance / 2` along the tangent; `degrees` from the tangent; a centre
  past L is not placed (closed paths wrap).
- **SVG.** One `<text>` per shape; runs as `<tspan>` with `font-family`,
  `font-size`, `font-weight`, `font-style`, `fill`, `letter-spacing`,
  `baseline-shift`; lines as `<tspan x y>`; centre and trailing as
  `text-anchor` middle and end; justified lines with explicit per-grapheme
  `x` lists (from the layout); type on a path as `<textPath href
  startOffset>` with the path in `<defs>`. Output byte-stable; non-finite
  values throw.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| TE-1 | feature issue | The layout and command stubs, `ResolvedRun`, `resolvedRuns` (real: it is a contract value), `FixedAdvances`; `TextShapeTests` | `Sources/FlareCore/TextLayout.swift`, `Sources/FlareCore/TextLayout+Path.swift`, `Sources/FlareCore/TextStyleCommands.swift`, `Tests/FlareCoreTests/TextShapeTests.swift`, `Tests/mutations/FlareResolvedRuns.json` | engine-contracts:EC-f | ~300, 5 |
| TE-2 | – | Checks first: `TextStyleCommandsTests` (and its `undoSteps`, `expectedIDs`), `TextLayoutTests`, `TextOnPathTests`, `SVGTextExportTests`, disabled by name; text fixtures (Latin, emoji, combining marks, a 10,000-grapheme paragraph) | `Tests/FlareCoreTests/TextStyleCommandsTests.swift`, `Tests/FlareCoreTests/TextLayoutTests.swift`, `Tests/FlareCoreTests/TextOnPathTests.swift`, `Tests/FlareCoreTests/SVGTextExportTests.swift`, `Tests/FlareCoreTests/TextFixtures.swift` | TE-1 | ~380, 5 |
| TE-3 | – | `ApplyTextStyle`, `ClearTextStyle`, `EditTextString`; turns on their cases | `Sources/FlareCore/TextStyleCommands.swift`, `Tests/FlareCoreTests/TextStyleCommandsTests.swift`, `Tests/mutations/FlareTextStyleCommands.json` | TE-2 | ~340, 3 |
| TE-4 | – | `SetParagraphStyle`, `SetTextOnPath` in a second file, with the drag merge | `Sources/FlareCore/TextStyleCommands+Paragraph.swift`, `Tests/FlareCoreTests/TextParagraphCommandsTests.swift`, `Tests/mutations/FlareTextParagraphCommands.json` | TE-2 | ~220, 3 |
| TE-5 | – | `TextLayout.lay`; turns on `TextLayoutTests` | `Sources/FlareCore/TextLayout.swift`, `Tests/FlareCoreTests/TextLayoutTests.swift`, `Tests/mutations/FlareTextLayout.json` | TE-2 | ~360, 3 |
| TE-6 | – | `onPath`; turns on `TextOnPathTests` | `Sources/FlareCore/TextLayout+Path.swift`, `Tests/FlareCoreTests/TextOnPathTests.swift`, `Tests/mutations/FlareTextOnPath.json` | TE-2, path-geometry:PG-measure | ~200, 3 |
| TE-7 | – | SVG text writer for runs, lines and alignment; turns on those cases | `Sources/FlareCore/Export/SVGExporter+Text.swift`, `Tests/FlareCoreTests/SVGTextExportTests.swift`, `Tests/mutations/FlareSVGText.json` | TE-3, TE-5 | ~300, 3 |
| TE-8 | – | SVG `textPath` in a second file; its cases in a second suite | `Sources/FlareCore/Export/SVGExporter+TextPath.swift`, `Tests/FlareCoreTests/SVGTextPathExportTests.swift` | TE-6, TE-7 | ~160, 2 |
| TE-9 | – | KJ-TE walk; `TextBudgetTests` (release, `.serialized`) | `Tests/FlareCoreTests/TextWalkTests.swift`, `Tests/FlareCoreTests/TextBudgetTests.swift` | TE-4, TE-8 | ~180, 2 |
| TE-10 | – | The packet's status line; `feature-done` | `docs/blueprints/core/features/text-engine.md` | TE-9 | ~5, 1 |

`SVGExporter+TextPath.swift` is a new file (in `Export/*.swift`, already
covered by the `export` part). TE-4's commands go in their own file so TE-3
and TE-4 share none; both register through the one
`TextStyleCommands.all` list TE-1 declares with every id, so neither edits
the registry.

## Build waves

- Wave 1: TE-1. Independent in this wave: TE-1 alone.
- Wave 2: TE-2. Independent in this wave: TE-2 alone.
- Wave 3: TE-3, TE-4, TE-5, TE-6. Independent in this wave: all four (TE-6 once path-geometry's PG-measure has merged).
- Wave 4: TE-7. Independent in this wave: TE-7 alone.
- Wave 5: TE-8. Independent in this wave: TE-8 alone.
- Wave 6: TE-9. Independent in this wave: TE-9 alone.
- Wave 7: TE-10 (`feature-done`, final). Independent in this wave: TE-10 alone.

Longest chain: TE-1 → TE-2 → TE-5 → TE-7 → TE-8 → TE-9 → TE-10 (7).
Chain of 7: the checks need the stubs, the writer reads the layout, the
path writer extends the text writer's element, the walk exports both,
TE-10 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| TE-1 | `TextShapeTests`: `resolvedRuns` of a plain shape is one run over the string; with a bold run in the middle, three runs that tile the string; emoji count as one grapheme; stubs throw | runs leave a gap or count UTF-16 units | `FlareResolvedRuns`: gap filler skipped at the end → `TextShapeTests.runsTileTheString`; `utf16.count` for `count` → `.emojiIsOneGrapheme` |
| TE-2 | suites compile, disabled | – | – |
| TE-3 | `TextStyleCommandsTests`: bold on 6..<11 of "Bring the light" gives three runs; bold again on 6..<8 changes nothing; bold on 0..<15 then clear gives no runs; editing before a run shifts it, inside it grows it, across it shrinks it; inserted text takes the style before it; a range past the end or on a locked layer is refused unchanged; exact undo in `UndoPropertyTests` | runs overlap or drift off their graphemes | `FlareTextStyleCommands`: merge skipped (equal neighbours stay split) → `TextStyleCommandsTests.equalNeighboursMerge`; shift uses `>=` for `>` at the edit point → `.runAtEditPointGrows`; range check `<=` for `<` → `.rangePastEndRefused` |
| TE-4 | `TextParagraphCommandsTests`: set, change and clear paragraph and path settings with exact undo; a drag of `lineHeight` merges into one step; `lineHeight` 5 refused | a drag leaves many steps | `FlareTextParagraphCommands`: merge on a different field → `TextParagraphCommandsTests.mergeOnlySameField`; validation skipped → `.lineHeightFiveRefused` |
| TE-5 | `TextLayoutTests` on `FixedAdvances`: 10 graphemes of 12 pt at box 30 wrap into 2 lines at the space; a 20-grapheme word breaks by grapheme; trailing space not counted; centre shifts by half the slack; justified first line ends at the box edge and the last line doesn't; line gap = 1.5 × 24; a newline adds paragraph spacing; tracking adds per grapheme; 10,000 graphemes lay out; more than `maxGraphemes` throws | a line overflows or a gap is wrong | `FlareTextLayout`: trailing whitespace counted → `TextLayoutTests.trailingSpaceDoesNotWrap`; justify the last line → `.lastLineNotJustified`; line height from the first run only → `.mixedSizesUseTallest`; tracking added once per line → `.trackingPerGrapheme` |
| TE-6 | `TextOnPathTests`: on a 100-unit straight line, offset 0.25, glyphs start at x 25 at 0°; on a circle the tangent is perpendicular to the radius within 1e-6; flip runs the other way; glyphs past the end of an open path are not placed; a closed path wraps | a glyph is placed off the path | `FlareTextOnPath`: centre at `s + x` without `advance / 2` → `TextOnPathTests.glyphCentredOnPath`; flip ignored → `.flipReverses` |
| TE-7 | `SVGTextExportTests`: the fixture writes one `text` with three `tspan`s and their attributes, two line `tspan`s at their baselines, `text-anchor` middle for centre, explicit `x` lists on a justified line; byte-stable over two runs | an attribute or a baseline is wrong | `FlareSVGText`: `font-weight` from the shape, not the run → `SVGTextExportTests.runWeightWritten`; baseline from line index × size → `.baselinesFromLayout` |
| TE-8 | `SVGTextPathExportTests`: `textPath` with `startOffset` as a percentage and the path in `defs`; flip reverses the path data | the path or offset is wrong | none beyond TE-7's plan (one formatting path) |
| TE-9 | `TextWalkTests.walk` (KJ-TE); `TextBudgetTests`: lay out 10,000 graphemes ≤ 4 ms; 500 glyphs on a path ≤ 2 ms (release, reported) | the walk's checks fail | none |
| TE-10 | status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Typing in a long paragraph | layout of 10,000 graphemes ≤ 4 ms (per keystroke) | `TextBudgetTests.layParagraph` (release, reported) |
| Exact undo | every text command in the cross-family property | `UndoPropertyTests` |
| Graphemes, not units | emoji and combining marks count as one everywhere | `TextShapeTests`, `TextStyleCommandsTests` |
| Linux-safe | no CoreText or platform import; metrics come in as values | `scripts/ci` |
| Never crashes | NaN advances, negative sizes and ranges past the end throw | `TextLayoutTests.fuzz`, `TextStyleCommandsTests.fuzz` |

## Done check

Per slice as usual. No Mac finisher here: the CoreText half is
`shell-text`'s, verified there. Then the contact sheet with the walk's SVG.

## Adopted later

- creative-apps `shell-text` (wave 5 of the suite line, beside this one):
  measures with CoreText into `GlyphRunMetrics`-shaped values and draws
  placed glyphs; its font picker.
- **W2:** S21 text animators (type-on, per-character fade and offset) on
  `LaidLine.x` and `PlacedGlyph`.
- **W3:** Halo's text layers (H+1.7), Design (D+1.3), Photo (P+1.5) and
  Flare (F+1.3) text tools move onto these runs and this layout; Halo's
  `HaloTextRasterizer` goes to `shell-text`.

## Not in this packet

Bidirectional and vertical text, OpenType feature toggles, hyphenation
dictionaries, text in Lottie export (Lottie's text layer needs embedded
glyphs; the beta exports text as outlines where the app asks), outlines of
glyphs (the platform's, through `shell-text`).
