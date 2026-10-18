# Feature packet: image-codecs

**Feature:** Foundation-only PNG and JPEG codecs in CoreRaster's `codecs`
component, so the apps open and write real image files with no platform
image library: `PNG` (read every colour type, bit depth and interlace;
write 8- and 16-bit RGBA) over a pure-Swift zlib (`Inflate`, `Deflate`),
and `JPEG` (read baseline and progressive, write baseline). `PNGCodec`
conforms to the existing `PixelCodec`, so ORA layers and every app's
headless document use it on Linux. This is what makes the suite's
`afterglow` CLI, its MCP server and the real-jobs suites work on Linux CI
for Photo and Library (today the only `PixelCodec` besides the raw test
stand-in is Photo's ImageIO one, macOS-only, and `layered-codecs.md` notes
there is no inflate in core).
**Line:** `line:core` · **Wave:** 5 (`waves.md`; beta-80 **W0**, `p0`) ·
**Lead branch:** `lead/image-codecs`

**Covers:** the captain's AI-accessible-first call (the beta-80 plan's "W0:
command layer"): headless Linux I/O for Photo and Library; creative-apps
`adopt-command-catalog` AC-p2 and AC-l3 and the real-jobs suites' pixel
expectations. Later: Library thumbnails and Photo open on Linux tests
without the raw stand-in.

**Depends on:** nothing open. It adds files under `Sources/CoreRaster/
Codecs/` that no open packet owns (layered-codecs is built), plus its own
tests. Base: `origin/dev` ce06d88. The apps receive it through one
`scripts/bump-core` PR after IC-png (and again after IC-jpeg).

**C4:** container `coreraster`, component `codecs` (existing,
`docs/c4/parts/creative-core/coreraster/codecs.json`): its description
gains PNG, JPEG, Inflate and Deflate, edited by the task that adds each.
No new component: these are codecs, and the component's path already
covers the folder (one canonical home; a new `image-io` component would
split one concept in two).

**Clean-room.** From the published specifications only: RFC 1950 (zlib),
RFC 1951 (DEFLATE), the W3C PNG specification (third edition), and ITU-T
T.81 / ISO 10918-1 (JPEG) with its Annex K example tables, plus JFIF 1.02
and the EXIF orientation tag. No library's source is read. The CRC-32 is
`ZipStore`'s (`crc32`), moved to `ByteReader.swift` as a shared helper,
not copied.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| IC-a | `PNG`, `PNGCodec`, `JPEG`, `Inflate` and `Deflate` exist as documented stubs in `codecs`, with test fixtures built from the specs and every check written and disabled. | IC-1, IC-2 | `ImageCodecShapeTests` | nothing |
| IC-png | Any valid PNG (grey, grey-alpha, RGB, RGBA, palette with tRNS; depths 1 to 16; Adam7) decodes to the right premultiplied linear pixels, a `PixelBuffer` writes as an 8- or 16-bit RGBA PNG that this reader and the spec's rules both accept, damaged and oversized files throw a named error before allocating, and `PNGCodec` round trips through ORA. | IC-3, IC-4, IC-5 | `InflateTests`, `PNGReadTests`, `PNGWriteTests`, `PNGFuzzTests` | IC-a |
| IC-jpeg | Baseline and progressive JPEGs (grey and YCbCr, 4:4:4, 4:2:2, 4:2:0, restart markers) decode within a tolerance of their reference pixels with the EXIF orientation reported, and a `PixelBuffer` writes as a baseline JFIF at a 1 to 100 quality that this reader reopens within a tolerance. | IC-6, IC-7, IC-8 | `JPEGReadTests`, `JPEGWriteTests`, `JPEGFuzzTests` | IC-a |
| IC-z | A walk decodes and re-encodes a set of spec-built fixtures through both codecs and ORA, the budgets hold on Linux, and the feature is built. | IC-9, IC-10 | `ImageCodecWalkTests`, `ImageCodecBudgetTests` | IC-png, IC-jpeg |

`ui_slice: none`: engine only. Its screens: none directly; the apps'
headless documents and the CLI's real jobs use it (creative-apps).

## Journey steps

Engine only. KJ-IC (`ImageCodecWalkTests.walk`, IC-9): every PNG fixture
(15 colour-type and depth pairs, interlaced and not) decodes to its
reference pixels; each re-encodes as RGBA and reopens `==`; an ORA with
three layers written through `PNGCodec` reopens with the same layers; every
JPEG fixture decodes within a mean absolute error of 1/255 and a maximum of
4/255 of its reference; quality 90 re-encodes and reopens within 3/255 mean;
an EXIF-rotated fixture reports orientation 6.

## Screens and states

None (engine only).

## Contract slice

```swift
// Sources/CoreRaster/Codecs/Inflate.swift, Deflate.swift (IC-1 stubs; IC-3 bodies)
public enum Inflate {
    /// zlib-wrapped (RFC 1950) or raw (RFC 1951) data, inflated. Throws CodecError.damaged on a bad
    /// header, block, code or Adler-32, and tooLarge past `limit` output bytes (checked as it grows).
    public static func zlib(_ data: Data, limit: Int) throws -> Data
    public static func raw(_ data: Data, limit: Int) throws -> Data }
public enum Deflate {
    /// zlib-wrapped DEFLATE: fixed-Huffman blocks with LZ77 over a 32 KiB window (hash chains, lazy
    /// match off), or stored blocks at level 0. Deterministic: the same input gives the same bytes.
    public static func zlib(_ data: Data, level: Int = 6) -> Data }

// Sources/CoreRaster/Codecs/PNG.swift (IC-1 stub; IC-4 read, IC-5 write)
public struct PNGInfo: Hashable, Sendable { public var width, height, bitDepth: Int; public var colorType: Int; public var interlaced: Bool }
public enum PNG {
    public static let maxSide = 30_000                       // like PSD; and PixelBuffer.maxPixels
    public static func info(_ data: Data) throws -> PNGInfo  // IHDR only, no decode
    /// Premultiplied linear Float32 pixels (sRGB transfer undone through DisplayBytes'
    /// rules; gAMA, cHRM and iCCP are ignored and the image is taken as sRGB).
    public static func read(_ data: Data) throws -> PixelBuffer
    /// RGBA at 8 or 16 bits per channel, sRGB, one IDAT per 64 KiB, adaptive filters per row
    /// (the filter with the least sum of absolute values, as the spec's 12.8 suggests).
    public static func write(_ buffer: PixelBuffer, bitsPerChannel: Int = 8, level: Int = 6) throws -> Data }
public struct PNGCodec: PixelCodec { public init(level: Int = 6)
    public func decodePNG(_ data: Data) throws -> PixelBuffer; public func encodePNG(_ b: PixelBuffer, bitsPerChannel: Int) throws -> Data }

// Sources/CoreRaster/Codecs/JPEG.swift (IC-1 stub; IC-6 baseline read, IC-7 progressive read, IC-8 write)
public struct JPEGInfo: Hashable, Sendable { public var width, height, components: Int; public var progressive: Bool; public var orientation: Int }   // EXIF 1...8, 1 when absent
public enum JPEG {
    public static let maxSide = 30_000
    public static func info(_ data: Data) throws -> JPEGInfo
    public static func read(_ data: Data) throws -> PixelBuffer          // not rotated; callers apply `orientation`
    public static func write(_ buffer: PixelBuffer, quality: Int = 90) throws -> Data }   // baseline, 4:2:0, Annex K tables scaled
```

Errors are the component's `CodecError` (`notThisFormat`, `damaged`,
`unsupported` (arithmetic coding, lossless and hierarchical JPEG, 12-bit
samples, CMYK), `tooLarge`). Sizes are checked from IHDR or SOF before any
pixel buffer is made; inflate output is capped at the size the header
implies plus filter bytes.

## Pseudocode

```
PNG.read: signature; chunks with CRC (ByteReader); IHDR first, sizes within maxSide and maxPixels;
  PLTE for type 3; tRNS; IDATs concatenated; Inflate.zlib(limit: expectedFilteredBytes);
  per pass (Adam7 or one): unfilter rows (None, Sub, Up, Average, Paeth); unpack samples by depth;
  expand to RGBA (palette, grey, tRNS key colour → alpha 0); 16-bit kept as 16 → Float;
  sRGB → linear, premultiply.
PNG.write: unpremultiply, linear → sRGB, quantize to 8 or 16 bits; per row pick the filter with the
  least sum of |bytes| as signed; Deflate.zlib; IHDR, IDAT chunks, IEND, each CRC'd.
JPEG.read: markers SOI, APPn (JFIF, EXIF orientation), DQT, SOF0/1/2, DHT, SOS, DRI, EOI;
  Huffman decode with restart handling; progressive: DC first and refine, AC spectral selection and
  successive approximation, per Annex G; IDCT (separable, float); upsample chroma (box for 4:2:x);
  YCbCr → RGB (JFIF); sRGB → linear premultiplied, alpha 1.
JPEG.write: 4:2:0 with box downsample; Annex K luminance and chrominance tables scaled by quality
  (the common 50-centred formula); forward DCT; Annex K Huffman tables; baseline, one scan.
```

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| IC-1 | – | Stubs with doc comments: `Inflate`, `Deflate`, `PNG`, `PNGInfo`, `PNGCodec`, `JPEG`, `JPEGInfo`; `crc32` moved from `ZipStore` into `ByteReader.swift` (ZipStore calls it); the `codecs` part's description; shape checks | `Sources/CoreRaster/Codecs/Inflate.swift`, `Sources/CoreRaster/Codecs/Deflate.swift`, `Sources/CoreRaster/Codecs/PNG.swift`, `Sources/CoreRaster/Codecs/JPEG.swift`, `Sources/CoreRaster/Codecs/ByteReader.swift`, `Sources/CoreRaster/Codecs/ZipStore.swift`, `Tests/CoreRasterTests/ImageCodecShapeTests.swift`, `docs/c4/parts/creative-core/coreraster/codecs.json` | – | ~240, 8 |
| IC-2 | – | Checks first, all disabled: `InflateTests` (stored, fixed, dynamic blocks from RFC 1951's examples; Adler-32; limit), `PNGReadTests`, `PNGWriteTests`, `PNGFuzzTests`, `JPEGReadTests`, `JPEGWriteTests`, `JPEGFuzzTests`; fixtures built in test code from the specs (`Fixtures/PNGFixtures.swift`, `Fixtures/JPEGFixtures.swift`: PNGs written byte by byte with stored deflate; JPEGs from hand-assembled baseline and progressive streams of 8×8 and 16×16 blocks with known DCT coefficients) | `Tests/CoreRasterTests/InflateTests.swift`, `Tests/CoreRasterTests/PNGReadTests.swift`, `Tests/CoreRasterTests/PNGWriteTests.swift`, `Tests/CoreRasterTests/PNGFuzzTests.swift`, `Tests/CoreRasterTests/JPEGReadTests.swift`, `Tests/CoreRasterTests/JPEGWriteTests.swift`, `Tests/CoreRasterTests/JPEGFuzzTests.swift`, `Tests/CoreRasterTests/Fixtures/PNGFixtures.swift`, `Tests/CoreRasterTests/Fixtures/JPEGFixtures.swift` | IC-1 | ~400, 9 |
| IC-3 | – | `Inflate` and `Deflate` bodies and plans; turns on `InflateTests` | `Sources/CoreRaster/Codecs/Inflate.swift`, `Sources/CoreRaster/Codecs/Deflate.swift`, `Tests/mutations/CoreRaster.Inflate.json`, `Tests/CoreRasterTests/InflateTests.swift` | IC-2 | ~380, 4 |
| IC-4 | – | `PNG.info`, `PNG.read` and `PNGCodec.decodePNG`, the plan; turns on `PNGReadTests` and `PNGFuzzTests` | `Sources/CoreRaster/Codecs/PNG.swift`, `Tests/mutations/CoreRaster.PNG.json`, `Tests/CoreRasterTests/PNGReadTests.swift`, `Tests/CoreRasterTests/PNGFuzzTests.swift` | IC-3 | ~360, 4 |
| IC-5 | – | `PNG.write` and `PNGCodec.encodePNG` in their own file, the plan; turns on `PNGWriteTests` (incl. an ORA round trip through `PNGCodec`) | `Sources/CoreRaster/Codecs/PNGWrite.swift`, `Tests/mutations/CoreRaster.PNGWrite.json`, `Tests/CoreRasterTests/PNGWriteTests.swift` | IC-3 | ~240, 3 |
| IC-6 | – | `JPEG.info` and baseline `JPEG.read` (markers, Huffman, IDCT, upsampling, colour, EXIF orientation), the plan; turns on the baseline half of `JPEGReadTests` and `JPEGFuzzTests` | `Sources/CoreRaster/Codecs/JPEG.swift`, `Tests/mutations/CoreRaster.JPEG.json`, `Tests/CoreRasterTests/JPEGReadTests.swift`, `Tests/CoreRasterTests/JPEGFuzzTests.swift` | IC-2 | ~400, 4 |
| IC-7 | – | Progressive decode (Annex G scans and refinement) in its own file, the plan; turns on the progressive half of `JPEGReadTests` | `Sources/CoreRaster/Codecs/JPEGProgressive.swift`, `Tests/mutations/CoreRaster.JPEGProgressive.json`, `Tests/CoreRasterTests/JPEGReadTests.swift` | IC-6 | ~320, 3 |
| IC-8 | – | Baseline `JPEG.write` in its own file, the plan; turns on `JPEGWriteTests` | `Sources/CoreRaster/Codecs/JPEGWrite.swift`, `Tests/mutations/CoreRaster.JPEGWrite.json`, `Tests/CoreRasterTests/JPEGWriteTests.swift` | IC-6 | ~300, 3 |
| IC-9 | – | KJ-IC walk and the budgets (below), budgets reported | `Tests/CoreRasterTests/ImageCodecWalkTests.swift`, `Tests/CoreRasterTests/ImageCodecBudgetTests.swift` | IC-4, IC-5, IC-7, IC-8 | ~200, 2 |
| IC-10 | – | Shared prose: `waves.md` row status, the `codecs` part's final description; `feature-done` | `docs/blueprints/core/features/waves.md`, `docs/c4/parts/creative-core/coreraster/codecs.json` | IC-9 | ~40, 2; `feature-done` |

IC-4 and IC-5 split read and write into two files so they run together;
IC-7 and IC-8 do the same for JPEG. `ByteReader.swift` and `ZipStore.swift`
are edited only by IC-1 (the CRC move, behaviour unchanged, `ZipStore`'s
tests prove it).

## Build waves

- Wave 1: IC-1. Independent in this wave: IC-1 alone.
- Wave 2: IC-2. Independent in this wave: IC-2 alone.
- Wave 3: IC-3, IC-6. Independent in this wave: both.
- Wave 4: IC-4, IC-5, IC-7, IC-8. Independent in this wave: all four.
- Wave 5: IC-9. Independent in this wave: IC-9 alone.
- Wave 6: IC-10 (shared prose, `feature-done`, final). Independent in this wave: IC-10 alone.

Longest chain: IC-1 → IC-2 → IC-3 → IC-4 → IC-9 → IC-10 (6). Chain of 6:
IC-2's checks need IC-1's stubs, IC-3's inflate feeds IC-4's reader, IC-9
walks both codecs, IC-10 is the final prose task.

## Acceptance test per task

| id | test | fails when | mutations |
|---|---|---|---|
| IC-1 | `ImageCodecShapeTests`; `ZipStore` tests unchanged | a stub is missing, or the CRC move changes a zip byte | – (stubs, a move) |
| IC-2 | the seven test files exist, disabled by name | – | – (tests) |
| IC-3 | `InflateTests`: stored, fixed and dynamic blocks decode; a bad Adler-32, a distance past the window, an over-subscribed code each throw `damaged`; output past `limit` throws `tooLarge`; `Deflate` then `Inflate` is identity on 1,000 seeded buffers; the same input deflates to the same bytes | a valid stream fails or a bad one passes | length base table off by one at code 284 → `.dynamicBlocks`; Adler-32 not checked → `.adlerChecked`; limit checked after growth → `.limitBeforeGrowth` |
| IC-4 | `PNGReadTests`: each colour type and depth to its reference pixels; Adam7 equals the non-interlaced image; palette tRNS alpha; 16-bit precision kept; a bad CRC, a missing IHDR, a size over `maxSide` throw before decode. `PNGFuzzTests`: 1,000 seeded mutations throw or decode, never crash | wrong pixels, or allocation before the size check | Paeth predictor ties broken toward `b` → `.paethTies`; Adam7 pass 6 offsets swapped → `.adam7`; sRGB transfer skipped → `.linearPixels` |
| IC-5 | `PNGWriteTests`: 8 and 16 bit write and reread `==` (within one 16-bit step); IHDR depth recorded; chunk CRCs valid; `PNGCodec` ORA round trip equal | a written PNG fails to reread or loses precision | 16-bit written high byte last → `.bigEndian16`; filter choice always None → `.adaptiveFilterSmaller` |
| IC-6 | `JPEGReadTests` (baseline): grey and 4:4:4, 4:2:2, 4:2:0 within the tolerance; restart intervals; EXIF orientation read; arithmetic or 12-bit throws `unsupported`. `JPEGFuzzTests` | pixels off tolerance or a crash | zigzag table entry swapped → `.zigzag`; restart marker not resetting DC predictors → `.restartResetsDC` |
| IC-7 | `JPEGReadTests` (progressive): the same image coded progressive equals the baseline decode within 1/255 | progressive differs | successive approximation refine skipped → `.acRefinement` |
| IC-8 | `JPEGWriteTests`: quality 90 reopens within 3/255 mean; quality 1 and 100 accepted, 0 and 101 throw; output starts with SOI and JFIF | out of tolerance or an invalid stream | quality scale inverted → `.qualityScale`; chroma tables used for luma → `.lumaTables` |
| IC-9 | `ImageCodecWalkTests` (KJ-IC), `ImageCodecBudgetTests` (reported) | any step of the walk breaks | – (integration) |
| IC-10 | `scripts/c4-assemble --check` | the parts don't assemble | – (prose) |

## Quality tests

| quality row | budget | test |
|---|---|---|
| PNG decode | a 12 MP RGBA PNG (dynamic blocks) ≤ 1.5 s in a release build on Linux CI | `ImageCodecBudgetTests.pngDecode12MP` (reported) |
| PNG encode | 12 MP at level 6 ≤ 2.5 s release; output ≤ 1.3 × the size the fixture had | `ImageCodecBudgetTests.pngEncode12MP` (reported) |
| JPEG decode | a 24 MP baseline JPEG ≤ 2 s release | `ImageCodecBudgetTests.jpegDecode24MP` (reported) |
| bounded | sizes checked from IHDR/SOF before allocation; inflate capped; 30,000 per side; `PixelBuffer.maxPixels` | `PNGReadTests.refusesHuge`, `JPEGReadTests.refusesHuge`, `InflateTests.limitBeforeGrowth` |
| never crash | fuzzers on both formats and on inflate | `PNGFuzzTests`, `JPEGFuzzTests`, `InflateTests.fuzzed` |
| Foundation only | no import beyond Foundation (FoundationEssentials) | the CoreRaster import scan (existing) |

## Done check

Per slice: tasks merged and the newest dev CI run containing its last PR is
green (Linux, 3 minutes). Then one `scripts/bump-core` PR in creative-apps
after IC-png (Photo's and Library's headless documents and the CLI's pixel
expectations wait on it), and another after IC-jpeg.
