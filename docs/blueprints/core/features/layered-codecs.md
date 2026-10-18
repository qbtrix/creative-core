# Feature packet: layered-codecs

**Feature:** the suite's layered-file codecs in one CoreRaster component,
`codecs`: a neutral `LayeredImage` (pixel layers with position, opacity,
blend mode, visibility, clipping, a mask, and nested groups) that any app
maps its own layers to; a PSD reader (8-bit RGB and grayscale, and 16-bit
with the embedded profile once `color-profiles` landed; raw and RLE channels, layer masks, blend modes, groups, the merged image) and then a PSD
writer; and OpenRaster, moved in from Photo: the stored-entry zip container,
`stack.xml` written and now also read, so `.ora` files from other apps open.
PNG pixels inside ORA go through an injected `PixelCodec` (apps plug their
ImageIO codec; Linux tests use a raw fake), so the module stays
Foundation-only.
**Line:** `line:core` · **Wave:** 5 (`waves.md`) · **Lead branch:** `lead/layered-codecs`
**Status:** built. Merged PRs: #446, #472, #474, #475, #489, #492, #493,
#497, #499, #513, #514, #518, #520, #526, #545, #555, and this packet's
closing `feature-done` PR. `color-profiles` (#458, #476, #515, #519, #523,
#529, #538, #547, #552) extended the same files with 16-bit channels, the
embedded profile and profile conversion. LC-z's budgets are proved on the
Mac separately (see Done check). Where this packet and the code differ, the
code and its doc comments win.

**Covers:** beta-80 plan row E10 ("PSD codec: read layers, masks, blend,
groups; then write"; "ORA moves in"); Photo map row 15 / 10 ("PSD open, then
save"; "the `.ora` reader and writer is the model"); Photo blueprint 9.1
(the container could live in creative-core for other apps to share).

**Depends on:** nothing open. It adds its own part and folder and touches
no file `engine-contracts` owns, so it runs in wave 5. Base: `origin/dev`
4f91e04.

**C4:** container `coreraster`, ✚ new component `codecs`
(`docs/c4/parts/creative-core/coreraster/codecs.json`, `paths:
["Sources/CoreRaster/Codecs/"]`, `order` 40), added in LC-1, the task that
adds its first code. ⚠ ORA moves in: Photo's `PhotoZip.swift` and
`PhotoStackXML.swift` (creative-apps, this suite's own code) are moved, not
copied; Photo deletes them in its W3 adoption.

**Clean-room.** PSD from the publicly published PSD file format
specification and OpenRaster from its published spec; the zip container
from the public .ZIP File Format Specification (PKWARE APPNOTE), as Photo's
was. No binary of any app is inspected, and no other product's code is read
(CLAUDE.md, reverse engineering: a published spec needs no sign-off).

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| LC-a | `LayeredImage`, `PixelCodec`, `CodecError` and the PSD and ORA entry points exist as documented stubs in the new `codecs` component, with a raw `PixelCodec` fake, fixtures and every later check written and disabled. | LC-1, LC-2 | `CodecShapeTests` | nothing |
| LC-psd | A PSD opens into a `LayeredImage` with every pixel layer at its place, opacity, blend mode, visibility, clipping and mask, groups nested, names in Unicode, raw and RLE channels decoded, and damaged or unsupported files throw a named `CodecError`. | LC-3, LC-4 | `PSDReadTests`, `PSDFuzzTests` | LC-a |
| LC-ora | The zip container and `stack.xml` moved from Photo write the same bytes Photo writes today, and `.ora` files from other apps (stored entries) open with their layers, offsets, opacity, visibility and composite ops. | LC-5, LC-6 | `ORAContainerTests`, `ORAReadTests`, `ORAFuzzTests` | LC-a |
| LC-write | A `LayeredImage` saves as a PSD (RLE, groups, masks, merged image) that this reader reopens equal, and as an ORA through the `PixelCodec`. | LC-7, LC-8 | `PSDWriteTests`, `CodecRoundTripTests` | LC-psd, LC-ora |
| LC-z | A walk opens fixture PSDs and a third-party-style ORA, edits nothing, saves each as PSD and ORA and reopens them `==` wherever the format holds the image (what ORA cannot hold throws a named error or, for a group's open state, reopens open), the budgets hold, and the feature is built. | LC-9, LC-10 | `CodecWalkTests`, `CodecBudgetTests` | LC-write |

`ui_slice: none`: engine only. Its screens: Photo's Open and Save (PSD
open, then save; ORA documents), and the large-image gate G1's deep-layer
PSD fixtures.

## Journey steps

Engine only. KJ-LC (`CodecWalkTests.walk`, LC-9). Every "equal" is exact
`==`: the raw test `PixelCodec` keeps every Float, which is tighter than
1/255.

1. `layers.psd` (built by LC-2's writer-independent byte builder: 1200 × 800,
   five nodes: a group of two layers, one with a mask, one at Multiply 60%,
   one hidden, one clipped, a Unicode name) opens with every attribute.
   Saved as PSD and reopened, it is `==`. ORA can hold neither a mask nor
   clipping, so its ORA save throws
   `unsupported("a mask or clipping on \"Clipped\"")` instead of losing them.
2. `gray.psd` holds only what both formats keep, and reopens `==` from both.
3. `nested.psd` has a closed group. Its PSD save reopens `==`. ORA keeps no
   open or closed state, so its ORA save reopens `==` to the same tree with
   every group open.
4. A third-party-style `.ora` (stored entries) opens with its offsets (its
   last layer at x 12, y −3), and its ORA save reopens `==`.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/Codecs/LayeredImage.swift (LC-1)
public struct LayeredImage: Equatable, Sendable { public var width: Int, height: Int; public var nodes: [LayerNode]
    public var composite: PixelBuffer?; public var bitsPerChannel: Int                    // 8 or 16; a writer refuses any other
    public var profile: ColorProfile? }                                                   // color-profiles; nil when absent or refused
public enum LayerNode: Equatable, Sendable { case pixels(PixelLayer), group(LayerGroup)
    public static func == (lhs: LayerNode, rhs: LayerNode) -> Bool }                      // walks deep trees with a stack, no recursion
public struct PixelLayer: Equatable, Sendable { public var name: String; public var pixels: PixelBuffer; public var x: Int, y: Int
    public var opacity: Float; public var blendMode: BlendMode; public var isHidden: Bool; public var clipsToBelow: Bool
    public var mask: PlacedMask? }
public struct PlacedMask: Equatable, Sendable { public var mask: Mask; public var x: Int, y: Int; public var defaultCoverage: Float; public var isDisabled: Bool }
public struct LayerGroup: Equatable, Sendable { public var name: String; public var children: [LayerNode]; public var opacity: Float
    public var blendMode: BlendMode?; public var isHidden: Bool; public var isOpen: Bool }            // nil blend = pass through
public enum CodecError: Error, Equatable, Sendable {
    case notThisFormat, damaged(String), unsupported(String), tooLarge(String), compressedEntry(String), pixelCodec(String) }
// Sources/CoreRaster/Codecs/PixelCodec.swift (LC-1)
public protocol PixelCodec: Sendable {                                           // apps plug ImageIO; tests use RawPixelCodec
    func decodePNG(_ data: Data) throws -> PixelBuffer
    func encodePNG(_ buffer: PixelBuffer, bitsPerChannel: Int) throws -> Data }
public struct RawPixelCodec: PixelCodec { public init() }                        // PNG signature + IHDR, then Float32 bits; tests only
// Sources/CoreRaster/Codecs/PSD.swift (LC-1 stubs, LC-4 read, LC-7 write)
public enum PSD { public static let maxSide = 30_000; public static let maxLayers = 8_000
    public static let maxTotalPixels = PixelBuffer.maxPixels                     // summed area of every layer, mask and composite
    public static let maxDepth = OpenRaster.maxDepth                             // nested groups, 256
    public static func read(_ data: Data) throws -> LayeredImage
    public static func write(_ image: LayeredImage) throws -> Data }
// Sources/CoreRaster/Codecs/OpenRaster.swift (LC-1 stubs, LC-6 read, LC-8 write)
public enum OpenRaster { public static let maxSide = PSD.maxSide; public static let maxLayers = PSD.maxLayers
    public static let maxDepth = 256                                             // nested <stack> levels, the root the first
    public static let maxTotalPixels = PSD.maxTotalPixels                        // summed IHDR area of every layer and the merged image
    public static func read(_ data: Data, pixels: any PixelCodec) throws -> LayeredImage
    public static func write(_ image: LayeredImage, pixels: any PixelCodec, extra: [String: Data] = [:]) throws -> Data   // extra: app entries, e.g. photo/document.json
    public static let profilePath = "profile.icc"                                 // OpenRasterDeep.swift (color-profiles)
    public static let maxProfileBytes = StackXML.maxBytes }                       // 16 MiB
// Sources/CoreRaster/Codecs/ZipStore.swift (LC-5, moved from PhotoZip)
public enum ZipStore { public static func archive(_ files: [String: Data], first: String?) throws -> Data
    public static func entries(_ data: Data) throws -> [String: Data] }                       // stored only; else compressedEntry
```

## Pseudocode

- **PSD read.** Big-endian reader over `Data` with a bounds check on every
  read (no unchecked index, no Int overflow: lengths are checked against the
  remaining bytes first). Header: signature `8BPS`, version 1 (2 → 
  `unsupported("large document format")`), channels 1...56, height and
  width 1...`maxSide` (0 → `damaged`, over → `tooLarge`), depth 8 or 16
  (16-bit since `color-profiles`; any other → `unsupported("N-bit
  channels")`), colour mode RGB or Grayscale (others → `unsupported`).
  Colour-mode data is skipped by length; of the image resources, the ICC
  profile (resource 1039) fills `profile`, and one `ColorProfile(iccData:)`
  refuses is dropped (`PSDDeep.swift`). Layer and mask section: layer count (negative means the
  first alpha channel is the merged transparency; more than `maxLayers` →
  `tooLarge`), each record's bounds,
  channel ids and lengths, blend key (`norm`, `mul `, `scrn`, `over`,
  `dark`, `lite`, `diff`, `hue `, `sat `, `colr`, `lum `, … 16 keys mapped to
  `BlendMode`; an unknown key reads as `.normal`, which `PSD.read`'s doc
  comment says, and `PSDReadTests` has a case for it), opacity, clipping,
  flags (hidden bit), mask
  record (bounds, default colour byte → `defaultCoverage` byte / 255, so
  the spec's 0 or 255 reads 0 or 1, disabled flag → `isDisabled`), Pascal
  name, then tagged
  blocks: `luni` (Unicode name), `lsct` (section divider: open folder,
  closed folder, bounding divider) for groups. Channel data per channel:
  compression 0 raw, 1 RLE (PackBits rows with per-row byte counts),
  2 and 3 (zip) → `unsupported("zip-compressed channel")` (no inflate in
  the module; see Not in this packet). A channel id that repeats in one
  record → `damaged`; groups nested deeper than `maxDepth` → `tooLarge`.
- **PSD limits.** Every record's bounds (layer and mask) are four Int32
  values; width and height are computed in Int (`right − left`,
  `bottom − top`, so no Int32 overflow), a negative one → `damaged`, one
  over `maxSide` → `tooLarge`. A canvas within `maxSide` whose
  width × height is over `PixelBuffer.maxPixels` → `CodecError.tooLarge`.
  The summed area of every layer, every mask and the composite is checked
  against `maxTotalPixels` from the record bounds, before any channel is
  decoded (→ `tooLarge`). Every channel length is checked against the bytes
  left before it is read.
- **PSD pixels.** Pixels become premultiplied linear
  Float32 through CoreColor's sRGB tables. The merged image section fills
  `composite`: only its colour channels and, with a negative layer count,
  the first alpha are decoded, so the canvas counts once in
  `maxTotalPixels`; every other channel (up to 56) is skipped by its RLE
  row lengths, or its plane size when raw, without allocating.
- **Groups.** Records are bottom to top; a bounding divider opens a group
  and the matching folder record closes it, carrying its name, opacity,
  blend (`pass` → nil) and hidden flag. Unbalanced dividers → `damaged`.
- **ORA read.** `ZipStore.entries`, which keeps a running total of entry
  sizes and throws `damaged` once it passes the archive's byte count
  (entries that overlap cannot multiply the bytes); `mimetype` must be
  exactly `image/openraster`, and a missing or different one throws
  `notThisFormat`; `stack.xml` read by a small attribute scanner for
  `<image>` (`w`, `h`: the canvas, 1...`maxSide` and at most
  `PixelBuffer.maxPixels` in area, else `tooLarge`), `<stack>` and
  `<layer>` (src, x, y, opacity, visibility, name, composite-op `svg:*`
  mapped to `BlendMode`), nested stacks as groups. More than `maxLayers`
  `<layer>` and nested `<stack>` elements (the root stack not counted), or
  stacks nested more than `maxDepth` levels (the root stack the first) →
  `tooLarge`; a `src` that two layers name → `damaged`. Before anything
  goes through `pixels.decodePNG`, every `src` and `mergedimage.png` is
  sized from its IHDR (width and height at bytes 16 to 23, after the
  signature): each within `maxSide` and `PixelBuffer.maxPixels`, and their
  areas summed with checked math within `OpenRaster.maxTotalPixels`
  (= `PSD.maxTotalPixels`), else `tooLarge`, so many small entries cannot
  decode to more than one buffer's worth. An entry without a PNG signature
  and IHDR cannot be sized and throws `damaged` (the raw test fake writes
  both). Each entry is decoded once. Unknown elements are skipped.
  `mergedimage.png`, when present, fills `composite` (a size other than
  the canvas → `damaged`); a file without it reads `composite` nil. So an ORA
  this codec wrote reopens with the composite it saved, which LC-9's walk
  needs for "attributes equal". `Thumbnails/` is not read. A missing
  `stack.xml` → `damaged`; `stack.xml` over 16 MiB → `tooLarge`; x and y
  that are not integers within ±2^30 → `damaged`; opacity is clamped to 0...1, and a non-finite
  one → `damaged`; an unknown `composite-op` reads as `.normal`. Since
  `color-profiles`, `bitsPerChannel` is 16 when any IHDR says 16, and
  `profile.icc` (at most `maxProfileBytes`, else `tooLarge`) fills
  `profile`, dropped when `ColorProfile(iccData:)` refuses it.
- **Write.** PSD: 8 or 16 bits, RGB, or grayscale when `profile` is gray
  (a non-grey pixel then → `unsupported`), `profile` as resource 1039, RLE
  every channel, a negative layer count (the merged alpha), one record per
  pixel layer plus two records per group (a bounding divider below its
  children, a folder record above them carrying its name, opacity, blend or
  `pass`, and open or closed state), `luni` names with a Pascal ASCII name
  (`?` for other characters), the merged image from `composite`, or, when
  it is nil, a preview flattened from the visible layers (opacity and blend
  only: no masks, clipping or group blending). Before any byte is written,
  `PSD.write` validates the image and throws a `CodecError` instead of
  trapping. `unsupported` (naming the value) for: a layer, group or mask
  default value that is not finite in 0...1; `bitsPerChannel` other than 8
  or 16; a profile the ICC writer refuses; a canvas side under 1; a
  composite other than the canvas size. `tooLarge` for: a canvas, layer or
  mask side over `maxSide`; a layer or mask's bounds (`x`, `y`,
  `x + width`, `y + height`) outside Int32; more than `maxLayers` records
  (dividers and folders counted); canvas, layer and mask areas summing over
  `maxTotalPixels`. The writer walks the tree without recursion and has no
  nesting cap: groups nested deeper than `maxDepth` write, and `PSD.read`
  refuses that file with `tooLarge`. ORA: Photo's container rules (stored
  entries, `mimetype` first at offset 30, the other paths sorted, the fixed
  DOS date), `stack.xml` listing children top first, one PNG per layer
  (`data/<n>.png`), `mergedimage.png`, `Thumbnails/thumbnail.png` (longest
  side 256, never scaled up), `profile.icc` when there is a profile, then
  the `extra` entries. Before anything is encoded, `OpenRaster.write`
  throws `unsupported` for: a depth other than 8 or 16; a profile it cannot
  write; a missing composite or one other than the canvas size; a mask or
  a clipped layer (ORA holds neither); opacity outside 0...1; a NUL in a
  name; an `extra` entry on a standard path, a layer path or `profile.icc`.
  The canvas and every layer must pass the reader's size checks, offsets
  must be within ±2^30, layers plus groups within `maxLayers`, and nesting
  stops where the reader does. A group's `isOpen` is not kept; it reopens
  open.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| LC-1 | feature issue | The values, `CodecError`, `PixelCodec` and `RawPixelCodec`, the PSD and ORA stubs; the new `codecs` part; `CodecShapeTests` | `Sources/CoreRaster/Codecs/LayeredImage.swift`, `Sources/CoreRaster/Codecs/PixelCodec.swift`, `Sources/CoreRaster/Codecs/PSD.swift`, `Sources/CoreRaster/Codecs/OpenRaster.swift`, `Tests/CoreRasterTests/CodecShapeTests.swift`, `docs/c4/parts/creative-core/coreraster/codecs.json` | – | ~260, 6 |
| LC-2 | – | Fixtures: a byte builder that writes PSD records field by field from the spec (independent of LC-7's writer), the fixture files it makes, two third-party-style `.ora` files; the read, write, ORA and fuzz suites disabled | `Tests/CoreRasterTests/PSDBytes.swift`, `Tests/CoreRasterTests/Fixtures/codecs/`, `Tests/CoreRasterTests/PSDReadTests.swift`, `Tests/CoreRasterTests/PSDFuzzTests.swift`, `Tests/CoreRasterTests/ORAReadTests.swift`, `Tests/CoreRasterTests/ORAFuzzTests.swift`, `Tests/CoreRasterTests/PSDWriteTests.swift`, `Tests/CoreRasterTests/CodecRoundTripTests.swift` | LC-1 | ~380, 8 + fixtures |
| LC-3 | – | The bounds-checked big-endian reader and PackBits decode and encode | `Sources/CoreRaster/Codecs/ByteReader.swift`, `Sources/CoreRaster/Codecs/PackBits.swift`, `Tests/CoreRasterTests/PackBitsTests.swift`, `Tests/mutations/CoreRaster.PackBits.json` | LC-1 | ~220, 4 |
| LC-4 | – | PSD read: header, layer records, masks, tagged blocks, groups, channels, merged image; turns on `PSDReadTests`, `PSDFuzzTests` | `Sources/CoreRaster/Codecs/PSD.swift`, `Sources/CoreRaster/Codecs/PSDRead.swift`, `Tests/CoreRasterTests/PSDReadTests.swift`, `Tests/CoreRasterTests/PSDFuzzTests.swift`, `Tests/mutations/CoreRaster.PSDRead.json` | LC-2, LC-3 | ~390, 5 |
| LC-5 | – | `ZipStore` moved from Photo's `PhotoZip` (same bytes; CRC-32 slicing-by-8); `ORAContainerTests` from Photo's container tests | `Sources/CoreRaster/Codecs/ZipStore.swift`, `Tests/CoreRasterTests/ORAContainerTests.swift`, `Tests/mutations/CoreRaster.ZipStore.json` | LC-1 | ~300, 3 |
| LC-6 | – | ORA read (`stack.xml` scanner, nested stacks, composite ops, `mergedimage.png`, the limits); `ZipStore.entries`' running size total; turns on `ORAReadTests`, `ORAFuzzTests` | `Sources/CoreRaster/Codecs/OpenRaster.swift`, `Sources/CoreRaster/Codecs/StackXML.swift`, `Sources/CoreRaster/Codecs/ZipStore.swift`, `Tests/CoreRasterTests/ORAReadTests.swift`, `Tests/CoreRasterTests/ORAFuzzTests.swift`, `Tests/mutations/CoreRaster.StackXML.json` | LC-2, LC-5 | ~370, 6 |
| LC-7 | – | PSD write; turns on `PSDWriteTests` | `Sources/CoreRaster/Codecs/PSDWrite.swift`, `Tests/CoreRasterTests/PSDWriteTests.swift`, `Tests/mutations/CoreRaster.PSDWrite.json` | LC-4 | ~340, 3 |
| LC-8 | – | ORA write (moved `stack.xml` writer, thumbnail, merged image); turns on `CodecRoundTripTests` | `Sources/CoreRaster/Codecs/OpenRasterWrite.swift`, `Tests/CoreRasterTests/CodecRoundTripTests.swift`, `Tests/mutations/CoreRaster.ORAWrite.json` | LC-6, LC-7 | ~280, 3 |
| LC-9 | – | KJ-LC walk; `CodecBudgetTests` (release, `.serialized`) | `Tests/CoreRasterTests/CodecWalkTests.swift`, `Tests/CoreRasterTests/CodecBudgetTests.swift` | LC-8 | ~180, 2 |
| LC-10 | – | `codecs` part description final; the packet's status line; `feature-done` | `docs/c4/parts/creative-core/coreraster/codecs.json`, `docs/blueprints/core/features/layered-codecs.md` | LC-9 | ~30, 2 |

LC-4 and LC-6 fill the stub files LC-1 made (`PSD.swift`, `OpenRaster.swift`);
the write halves go in new files so read and write never share one.
LC-8 waits on LC-7 only for `CodecRoundTripTests`, which saves both formats.

## Build waves

- Wave 1: LC-1. Independent in this wave: LC-1 alone.
- Wave 2: LC-2, LC-3, LC-5. Independent in this wave: all three.
- Wave 3: LC-4, LC-6. Independent in this wave: both.
- Wave 4: LC-7. Independent in this wave: LC-7 alone.
- Wave 5: LC-8. Independent in this wave: LC-8 alone.
- Wave 6: LC-9. Independent in this wave: LC-9 alone.
- Wave 7: LC-10 (`feature-done`, final). Independent in this wave: LC-10 alone.

Longest chain: LC-1 → LC-2 → LC-4 → LC-7 → LC-8 → LC-9 → LC-10 (7). Chain
of 7: the reader needs the fixtures, the writer is proven by the reader, the
round-trip suite saves both formats, the walk and budgets time them, LC-10
is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| LC-1 | `CodecShapeTests`: `.valuesKeepEveryAttribute`, `.defaultsAreNormalVisibleAndPassThrough`, `.codecErrorCasesAreDistinct`, `.rawPixelCodecRoundTrips`, `.rawPixelCodecRefusesBadBytes`, and, now the writers are built, `.writersRefuseAMismatchedComposite` (LC-1's stubs that threw `unsupported("not built")` are gone) | a signature is missing | none: declarations |
| LC-2 | the byte builder's fixture opens nowhere yet (suites disabled) | – | – |
| LC-3 | `PackBitsTests`: the published example row decodes exactly; encode then decode is identity for 1,000 seeded rows; a run past the row's end throws; the reader throws at every truncation point of a 64-byte sample | a run overflows the row | `CoreRaster.PackBits`: repeat packet writes `n` copies for `1 − n` → `PackBitsTests.publishedExample`; row bound `<` for `<=` → `.runPastEndThrows`; byte reader reads one past the end → `.everyTruncationThrows`; encoder caps a run at 129 bytes → `.seededRowsRoundTrip`. Also in `PackBitsTests`: `.noOpHeaderIsSkipped`, `.byteReaderReadsBothOrdersAndThrowsAtEveryTruncation`, `.lengthArithmeticThrowsOnOverflow` |
| LC-4 | `PSDReadTests`: `layers.psd` gives 5 nodes with exact bounds, opacity 0.6 Multiply, hidden, clipped, the mask at its offset with default 0, the group's two children, the Unicode name (`.layersOpenInPlace`, `.groupsNest`, `.maskAtOffset`, `.hiddenFlag`, `.negativeCountHasAlpha`); grayscale opens as grey RGB (`.grayscaleOpensAsGrey`); the merged image matches; `.unsupportedFilesThrowNamedErrors`: a wrong signature throws `notThisFormat`, version 2, CMYK, Lab, 32-bit and zip channels each throw their named error (16-bit opens since `color-profiles`); an unknown blend key reads as `.normal` (`.unknownBlendKeyIsNormal`); unbalanced dividers throw `damaged` (`.unbalancedDividersThrow`); a mask with default colour 255 and the disabled flag reads `defaultCoverage` 1 and `isDisabled` (`.maskDefaultAndDisabled`); `.refusesHuge`: record bounds over `maxSide`, a canvas within `maxSide` but over `PixelBuffer.maxPixels`, summed areas over `maxTotalPixels` (a mask alone, or layers each under it) and more than `maxLayers` records each throw `tooLarge` before any channel is decoded; a layer side of exactly `maxSide` reads and `maxSide + 1` throws (`.layerSideBoundary`); `maxDepth` nested groups read and one more throws `tooLarge` (`.groupDepthLimit`); a repeated channel id throws `damaged` (`.repeatedChannelIdThrows`); a merged image with 52 extra channels decodes colour and alpha only (`.mergedImageSkipsExtraChannels`); `PSDFuzzTests`: 1,000 seeded mutations of three fixtures throw or open, never crash, each under 1 s | a layer is misplaced or a damaged file crashes | `CoreRaster.PSDRead`: a positive count taken as merged alpha → `PSDReadTests.negativeCountHasAlpha`; group order inverted → `.groupsNest`; mask offset ignored → `.maskAtOffset`; hidden bit 2 for bit 1 → `.hiddenFlag`; opacity / 256 and RLE row counts read as 32-bit → `.layersOpenInPlace`; side bound `<` for `<=`, `maxLayers + 1` let through, budget skipped for layer and mask bounds, mask area left out → `.refusesHuge`; unbalanced guard dropped → `.unbalancedDividersThrow`; disabled flag from bit 0, default read as 0 or 1 → `.maskDefaultAndDisabled`; every merged channel decoded, raw extra planes not skipped → `.mergedImageSkipsExtraChannels`; `maxDepth + 1` groups let through → `.groupDepthLimit`; repeated channel id accepted → `.repeatedChannelIdThrows`; 16-bit samples low byte first → `PSDDecodeTests.layerSamplesDecodeExactly` (`color-profiles`) |
| LC-5 | `ORAContainerTests`: `.pinnedGoldenBytes`, an archive laid out field by field from the PKWARE APPNOTE, is equal (Photo's adoption of `ZipStore` checks its own output against this pinned golden); `.mimetypeAtOffset30`; `.roundTrips`; `.refusesMissingFirstAndEmptyName`; a compressed entry throws `compressedEntry` naming it (`.compressedEntryThrows`); a bad CRC throws `damaged` (`.badCRCThrows`); every truncation throws (`.everyTruncationThrows`); `.seededDamageNeverCrashes`; `.crcMatches` | a byte moves from Photo's output | `CoreRaster.ZipStore`: unreflected CRC polynomial, slicing tables advanced by the wrong table → `ORAContainerTests.crcMatches`; paths sorted backwards → `.pinnedGoldenBytes`; compressed entry read as stored → `.compressedEntryThrows` |
| LC-6 | `ORAReadTests`: both third-party files open with offsets, opacity, hidden layers and `svg:multiply` as `.multiply`; a nested stack is a group; a missing `src` throws `damaged` naming it; a wrong or missing `mimetype` throws `notThisFormat`; `mergedimage.png` fills `composite`, and a file without it reads nil; `.refusesHuge`: a canvas or PNG IHDR over `maxSide` or `PixelBuffer.maxPixels`, more than `maxLayers` layers and nested stacks, stacks deeper than `maxDepth` and an entry without a PNG IHDR (`damaged`) each throw before any decode, while `maxLayers` layers, a `maxSide` canvas and `maxDepth` stacks read; `.totalPixelsBounded`: IHDRs summing past `maxTotalPixels` throw `tooLarge` before any decode, and exactly at it read; `.repeatedSourceThrows`: two layers naming one `src` throw `damaged`; `.overlappingEntriesThrow`: a zip whose entry sizes sum past its byte count throws `damaged`; `ORAFuzzTests`: 1,000 seeded mutations of `stack.xml` throw or open | an offset or op is lost | `CoreRaster.StackXML`: `x` read from `y`, stack order left top first → `ORAReadTests.offsetsKept`; visibility default hidden → `.visibleByDefault`; opacity ignored → `.offsetsKept` and `.attributesBounded`; depth cap removed, `maxDepth + 1` let through → `.namesDecodeEntitiesAndDepthIsCapped`; IHDR size check skipped → `.refusesHuge`; repeated source accepted → `.repeatedSourceThrows`; entry sizes past the archive → `.overlappingEntriesThrow`; merged image of another size kept → `.compositeMatchesTheCanvas`; offset lower bound dropped → `.attributesBounded`; summed IHDR budget dropped → `.totalPixelsBounded`; groups with different child counts equal → `LayerNodeEqualityTests.comparesFieldsChildrenAndDepth`. Also `ORAReadTests.missingSourceIsDamagedNamingIt` |
| LC-7 | `PSDWriteTests`: `PSD.read(PSD.write(img)) == img` for the fixture and 50 seeded stacks (`.fixtureAndSeededStacksRoundTrip`); `.everyChannelIsRLE`; `.headerMatchesTheSpecLayout`; `.groupsRoundTrip`; `.opacityRoundTrips`; `.invalidValuesThrow`: NaN, −0.1 and 1.5 opacity, a NaN group opacity, an offset, right edge or mask offset past Int32, `x` `Int.max`, 12 and 32 bits, a 0 or over-`maxSide` canvas and a colour layer under a gray profile each throw a `CodecError`, never trap | a written attribute reads back different | `CoreRaster.PSDWrite`: divider and folder records swapped, colour not unpremultiplied → `PSDWriteTests.groupsRoundTrip`; opacity rounded down → `.opacityRoundTrips`; opacity guard dropped, Int32 edges truncated, other depths written as 8 → `.invalidValuesThrow`; merged alpha not flagged → `.fixtureAndSeededStacksRoundTrip`; bucketed sRGB encoder stops at its bucket → `PSDColorBytesTests.encoderMatchesTheTableScan` (`color-profiles`) |
| LC-8 | `CodecRoundTripTests`: `.oraRoundTripsWithinOneStep` and `.seededStacksRoundTripExactly`: ORA write then read is `==` with the raw codec (opacity also within 1/255); `extra` entries survive (`.extraEntriesKept`) and one on a standard or layer path throws (`.extraKeyCollisionsThrow`); a 300 × 1000 canvas's thumbnail is 77 × 256 (`.thumbnailLongestSide`); masks, clipping, bad opacity and other limits throw (`.refusesWhatOraCannotHold`); `.nestingStopsWhereTheReaderDoes` | an entry is lost | `CoreRaster.ORAWrite`: thumbnail longest side uses width only → `CodecRoundTripTests.thumbnailLongestSide`; `extra` dropped → `.extraEntriesKept`; `extra` overwrites a layer source → `.extraKeyCollisionsThrow`; children bottom first → `.oraRoundTripsWithinOneStep`; opacity guard dropped → `.refusesWhatOraCannotHold`; one group more than the reader opens → `.nestingStopsWhereTheReaderDoes` |
| LC-9 | `CodecWalkTests.walk` (KJ-LC, as in Journey steps); `CodecBudgetTests` (`.serialized`, optimized builds only, wall-clock medians): `.openDeep` opens the 100-layer 4,000 × 3,000 PSD ≤ 1.5 s and ≤ 1.3 GB peak; `.saveDeep` saves it ≤ 2 s | the walk's equalities fail | none |
| LC-10 | the part names PSD, ORA and `PixelCodec`; status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Open a deep PSD | 100 seeded 8-bit layers of 400 × 300 tiling the 4,000 × 3,000 (12 MP) canvas in a 10 × 10 grid, plus the merged image: open ≤ 1.5 s, peak memory ≤ 1.3 GB; save ≤ 2 s. (100 full-canvas layers would decode to 19 GB of Float32 pixels, which no 1.3 GB budget holds.) Linux measured open about 394 ms after #555 and save about 1,353 ms | `CodecBudgetTests.openDeep`, `.saveDeep` (optimized builds, `.serialized`, medians; G1 reuses `deepPSD()`) |
| Never crashes | 1,000 PSD and 1,000 ORA fuzz cases throw or open, each under 1 s | `PSDFuzzTests.thousandMutationsThrowOrOpen`, `ORAFuzzTests.stackMutationsThrowOrOpen`, `ORAContainerTests.seededDamageNeverCrashes` |
| Bounded | PSD: `maxSide` on every record's bounds (Int from Int32), a canvas over `PixelBuffer.maxPixels`, `maxLayers`, `maxDepth`, `maxTotalPixels` from the record bounds before any channel is decoded, the merged image decoding only colour and one alpha, and every length checked before allocation. ORA: `OpenRaster.maxSide` on the canvas and each PNG's IHDR before decode, `maxTotalPixels` summed from every layer's and the merged image's IHDR before any decode, `maxLayers`, `maxDepth`, x and y within ±2^30, a repeated `src` refused, and `ZipStore`'s entry sizes summing to at most the archive size | `PSDReadTests.refusesHuge`, `.groupDepthLimit`, `.mergedImageSkipsExtraChannels`, `ORAReadTests.refusesHuge`, `.totalPixelsBounded`, `.attributesBounded`, `.repeatedSourceThrows`, `.overlappingEntriesThrow` |
| Same bytes as Photo | the moved container writes the pinned golden, built field by field from the PKWARE APPNOTE; Photo's adoption checks its own output against this pinned golden | `ORAContainerTests.pinnedGoldenBytes` |
| Linux-safe | Foundation only; PNG through `PixelCodec` | `scripts/ci` |

## Done check

Per slice as usual; LC-z's budgets on the Mac (`Mac-Finish-Wanted: LC-z`).
Then the contact sheet with the walk and the deep-PSD numbers, and the
supervisor bumps creative-core in creative-apps.

## Adopted later

- **W3:** Photo opens PSD and saves it (P+1.5), and moves its ORA archive
  onto `OpenRaster` and `ZipStore` (its `PhotoImageCodec` conforms to
  `PixelCodec`), deleting `PhotoZip.swift` and `PhotoStackXML.swift`; Design
  and Library import PSD as flattened art and thumbnails (maps' "also" rows).
- **W5:** G1's deep-layer PSD fixture.
- `color-profiles` (wave 6) added 16-bit channels and the embedded profile
  to both codecs (`PSDDeep.swift`, `OpenRasterDeep.swift`) and profile
  conversion (`ProfileConvert.swift`, `ProfileConvertCurves.swift`); it has
  landed.

## Not in this packet

Zip-compressed PSD channels and compressed ORA entries: both need inflate,
which no module has and Foundation on Linux doesn't give; a pure-Swift
inflate is its own approved issue if the beta's PSDs need it (most 8-bit
files use RLE). The large document format (PSB), CMYK, Lab, adjustment and
smart-object layers, text layers as text (they open as their pixels), layer
effects as effects (they open flattened in the merged image only).
