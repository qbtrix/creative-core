# Feature packet: color-profiles

**Feature:** colour management and deep layers for the layered codecs.
CoreColor gets ICC profiles: read matrix-and-curve profiles (RGB and gray,
v2 and v4), write sRGB, Display P3 and a profile from any primaries and
curve (for embedding on export), and a profile-to-profile transform through
XYZ with chromatic adaptation. CoreRaster's codecs get 16-bit channels in
PSD (read and write) and ORA (through the `PixelCodec`), a profile on every
`LayeredImage` read from and written to the file, and assign (reinterpret
the numbers) and convert (change them) on a buffer.
**Line:** `line:core` · **Wave:** 6 (`waves.md`) · **Lead branch:** `lead/color-profiles`
**Status:** planned

**Covers:** beta-80 plan row E13 ("colour profiles (assign, convert, embed)
and 16-bit layers"); Photo map row 12 ("Float32 inside, CoreColor display
transfer; 16-bit `.ora` and ICC are new"); Photo blueprint 9.3 (16-bit was
tier 3).

**Depends on:** `layered-codecs` (the `codecs` component, `LayeredImage`,
`PSD`, `OpenRaster`, `PixelCodec`; its LC-write slice for CP-7 and CP-8).
No `engine-contracts` slice.

**C4:** container `corecolor`, ✚ new component `icc-profiles`
(`docs/c4/parts/creative-core/corecolor/icc-profiles.json`, `paths:
["Sources/CoreColor/ICC/"]`, `order` 20), added by CP-1; container
`coreraster`, component `codecs` (new files in `Sources/CoreRaster/Codecs/`,
already owned by that part; CP-10 updates its words after
`layered-codecs`' LC-10).

**Clean-room.** The ICC profile format from the International Color
Consortium's published specification (ICC.1), chromatic adaptation by the
published linear Bradford transform, 16-bit PSD channels from the public
PSD file format specification. No task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| CP-a | `ColorProfile`, `ProfileTransform` and the 16-bit and profile fields exist as documented stubs in the new `icc-profiles` component, with ICC fixtures built field by field from the spec and every check written and disabled. | CP-1, CP-2 | `ICCShapeTests` | layered-codecs:LC-a |
| CP-icc | Matrix-and-curve profiles (gamma, table and parametric curves; RGB and gray; v2 and v4) read into primaries and curves, LUT-based and CMYK profiles throw a named error, and sRGB, Display P3 and any primaries-and-curve profile write bytes that read back equal. | CP-3, CP-4 | `ICCReadTests`, `ICCWriteTests`, `ICCFuzzTests` | CP-a |
| CP-convert | A transform between two profiles maps colours through XYZ with Bradford adaptation (sRGB to itself is identity, sRGB to Display P3 matches CoreColor's own conversion), and a buffer can be assigned a profile or converted to one. | CP-5, CP-6 | `ProfileTransformTests`, `ProfileConvertTests` | CP-icc |
| CP-deep | PSD reads and writes 16-bit RGB and gray with its embedded profile, and ORA reads and writes 16-bit layers and a profile entry through the `PixelCodec`, each round-tripping exactly at 16 bits. | CP-7, CP-8 | `PSDDeepTests`, `ORADeepTests` | CP-icc; layered-codecs:LC-write |
| CP-z | A walk opens a 16-bit Adobe-RGB-style PSD, converts to the working space, saves 16-bit ORA with the profile and 8-bit PSD in sRGB, reopens all, the budgets hold, and the feature is built. | CP-9, CP-10 | `ProfileWalkTests`, `ProfileBudgetTests` | CP-convert, CP-deep |

`ui_slice: none`: engine only. Its screens: Photo's Image > Assign Profile
and Convert to Profile, the export sheet's "embed profile" row, and 16-bit
documents (W3).

## Journey steps

Engine only. KJ-CP (`ProfileWalkTests.walk`, CP-9): a 16-bit PSD fixture
with a wide-gamut matrix profile (primaries chosen for the test, not any
vendor's) opens with its profile; converted into the working space (linear
sRGB primaries), a pure green outside sRGB stays finite and unclipped in
Float32; saved as 16-bit ORA with the profile and reopened `==` at 16 bits;
saved as 8-bit PSD converted to sRGB with sRGB embedded and reopened within
1/255.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreColor/ICC/ColorProfile.swift (CP-1 stubs, CP-3 read, CP-4 write)
public enum ProfileCurve: Hashable, Sendable { case gamma(Double), table([Double]), parametric(type: Int, params: [Double]) }
public struct ColorProfile: Hashable, Sendable {
    public var name: String; public var isGray: Bool
    public var toXYZD50: [Double]                                   // 3 × 3, row-major; gray: the white point column
    public var curves: [ProfileCurve]                               // 3 (RGB) or 1 (gray)
    public static let sRGB: ColorProfile; public static let displayP3: ColorProfile; public static let linearSRGB: ColorProfile
    public init(iccData: Data) throws(ColorError)                  // matrix and curve only; LUT-based, CMYK, Lab throw .invalid("…")
    public func iccData() throws(ColorError) -> Data               // v4, mluc description, chad tag
}
// Sources/CoreColor/ICC/ProfileTransform.swift (CP-1 stub, CP-5 body)
public struct ProfileTransform: Sendable { public init(from: ColorProfile, to: ColorProfile) throws(ColorError)
    public func apply(_ rgb: Color3) -> Color3                      // encoded in, encoded out; no clamp
    public func applyLinear(_ rgb: Color3) -> Color3 }              // linear in and out (the matrix part only)
// Sources/CoreRaster/Codecs/ProfileConvert.swift (CP-6)
extension PixelBuffer { public func converted(from: ColorProfile, to: ColorProfile) throws -> PixelBuffer }   // premultiplied linear light as the codecs decode it (sRGB TransferCurve); other curves get a curve pass
// LayeredImage gains `profile: ColorProfile?` (CP-1, in the codecs' file); `bitsPerChannel` takes 8 or 16
```

## Pseudocode

- **Read.** Header (size, class `mntr`/`scnr`, colour space `RGB ` or
  `GRAY`, PCS `XYZ `, version), tag table with every offset and length
  checked against the data; `rXYZ`/`gXYZ`/`bXYZ` (s15Fixed16), `wtpt`,
  `chad`; `rTRC`/`gTRC`/`bTRC` or `kTRC` as `curv` (count 0 identity, 1
  gamma u8Fixed8, n table) or `para` (types 0 to 4); `desc` (v2) or `mluc`
  (v4, the first record) for the name. Any `A2B0`/`B2A0` without the
  matrix tags, a non-XYZ PCS, CMYK or Lab throws `.invalid` naming it.
- **Write.** v4 header, `desc` as `mluc`, `wtpt` D50, `chad` (Bradford from
  D65), the three colourants and curves (`para` type 3 for sRGB-style
  curves, `curv` gamma otherwise), padded to 4 bytes; the profile ID left 0.
- **Transform.** Decode by the source curves, multiply by `toXYZD50`, by the
  inverse of the target's matrix (both in D50, so the `chad`-adapted
  colourants need no second adaptation), encode by the target's inverse
  curves (tables inverted by monotone interpolation). sRGB to linear sRGB
  is the curve only.
- **Buffer convert.** Unpremultiply, `applyLinear` when both sides are the
  working space's linear form, else decode with `from`'s curves after
  CoreColor's encode; premultiply. No clamp: Float32 keeps out-of-gamut
  values.
- **16-bit.** PSD: depth 16 channels big-endian, RLE rows over 2-byte
  samples' bytes, values / 65535; the ICC image resource (id 1039) read
  into `profile` and written from it. ORA: `PixelCodec.encodePNG(…,
  bitsPerChannel: 16)` and a `profile.icc` entry plus the app's document
  JSON naming it (OpenRaster has no profile field; other readers ignore it).

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| CP-1 | feature issue | The values and stubs, the `profile` field on `LayeredImage`, the new `icc-profiles` part; `ICCShapeTests` | `Sources/CoreColor/ICC/ColorProfile.swift`, `Sources/CoreColor/ICC/ProfileTransform.swift`, `Sources/CoreRaster/Codecs/LayeredImage.swift`, `Tests/CoreColorTests/ICCShapeTests.swift`, `docs/c4/parts/creative-core/corecolor/icc-profiles.json` | layered-codecs:LC-a | ~220, 5 |
| CP-2 | – | An ICC byte builder from the spec's fields and the fixtures it makes (v2 gamma, v4 parametric, table, gray, LUT-based, CMYK, damaged); every suite disabled | `Tests/CoreColorTests/ICCBytes.swift`, `Tests/CoreColorTests/Fixtures/icc/`, `Tests/CoreColorTests/ICCReadTests.swift`, `Tests/CoreColorTests/ICCWriteTests.swift`, `Tests/CoreColorTests/ICCFuzzTests.swift`, `Tests/CoreColorTests/ProfileTransformTests.swift` | CP-1 | ~380, 6 + fixtures |
| CP-3 | – | ICC read; turns on `ICCReadTests`, `ICCFuzzTests` | `Sources/CoreColor/ICC/ICCRead.swift`, `Tests/CoreColorTests/ICCReadTests.swift`, `Tests/CoreColorTests/ICCFuzzTests.swift`, `Tests/mutations/CoreColor.ICCRead.json` | CP-2 | ~340, 4 |
| CP-4 | – | ICC write and the three built-in profiles; turns on `ICCWriteTests` | `Sources/CoreColor/ICC/ICCWrite.swift`, `Tests/CoreColorTests/ICCWriteTests.swift`, `Tests/mutations/CoreColor.ICCWrite.json` | CP-3 | ~260, 3 |
| CP-5 | – | `ProfileTransform` with Bradford-adapted colourants and curve inversion; turns on `ProfileTransformTests` | `Sources/CoreColor/ICC/ProfileTransform.swift`, `Tests/CoreColorTests/ProfileTransformTests.swift`, `Tests/mutations/CoreColor.ProfileTransform.json` | CP-3 | ~240, 3 |
| CP-6 | – | `PixelBuffer.converted(from:to:)` with its checks | `Sources/CoreRaster/Codecs/ProfileConvert.swift`, `Tests/CoreRasterTests/ProfileConvertTests.swift`, `Tests/mutations/CoreRaster.ProfileConvert.json` | CP-5 | ~160, 3 |
| CP-7 | – | PSD 16-bit read and write and the ICC resource, in their own files | `Sources/CoreRaster/Codecs/PSDDeep.swift`, `Sources/CoreRaster/Codecs/PSDRead.swift`, `Sources/CoreRaster/Codecs/PSDWrite.swift`, `Tests/CoreRasterTests/PSDDeepTests.swift`, `Tests/mutations/CoreRaster.PSDDeep.json` | CP-4, layered-codecs:LC-write | ~320, 3 |
| CP-8 | – | ORA 16-bit and the profile entry, in its own file | `Sources/CoreRaster/Codecs/OpenRasterDeep.swift`, `Sources/CoreRaster/Codecs/OpenRaster.swift`, `Sources/CoreRaster/Codecs/OpenRasterWrite.swift`, `Tests/CoreRasterTests/ORADeepTests.swift`, `Tests/mutations/CoreRaster.ORADeep.json` | CP-4, layered-codecs:LC-write | ~200, 3 |
| CP-9 | – | KJ-CP walk; `ProfileBudgetTests` (release, `.serialized`) | `Tests/CoreRasterTests/ProfileWalkTests.swift`, `Tests/CoreRasterTests/ProfileBudgetTests.swift` | CP-6, CP-7, CP-8 | ~180, 2 |
| CP-10 | – | `icc-profiles` part's final words; the `codecs` part names 16-bit and profiles; the packet's status line; `feature-done` | `docs/c4/parts/creative-core/corecolor/icc-profiles.json`, `docs/c4/parts/creative-core/coreraster/codecs.json`, `docs/blueprints/core/features/color-profiles.md` | CP-9, layered-codecs | ~30, 3 |

CP-7 and CP-8 hook into the readers and writers through the `bitsPerChannel`
switch `layered-codecs` leaves in `PSDRead`, `PSDWrite` and
`OpenRasterWrite` (an `unsupported` throw today): each replaces that one
throw with a call into its own new file. Those one-line edits are the only
`layered-codecs` files they touch, after LC-write has merged.

## Build waves

- Wave 1: CP-1. Independent in this wave: CP-1 alone.
- Wave 2: CP-2. Independent in this wave: CP-2 alone.
- Wave 3: CP-3. Independent in this wave: CP-3 alone.
- Wave 4: CP-4, CP-5. Independent in this wave: both.
- Wave 5: CP-6, CP-7, CP-8. Independent in this wave: all three.
- Wave 6: CP-9. Independent in this wave: CP-9 alone.
- Wave 7: CP-10 (`feature-done`, final). Independent in this wave: CP-10 alone.

Longest chain: CP-1 → CP-2 → CP-3 → CP-4 → CP-7 → CP-9 → CP-10 (7).
Chain of 7: the reader needs the fixtures, the writer is proven by the
reader, the deep PSD embeds what the writer writes, the walk saves it,
CP-10 is the prose task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| CP-1 | `ICCShapeTests`: stubs throw; `LayeredImage` decodes with `profile` nil | a signature is missing | none |
| CP-2 | suites compile, disabled | – | – |
| CP-3 | `ICCReadTests`: each fixture reads its primaries within 1e-6 and its curve kind and values; gray reads one curve; LUT-based, CMYK and Lab throw naming themselves; `ICCFuzzTests`: 1,000 seeded mutations throw or read, never crash | a colourant or curve reads wrong | `CoreColor.ICCRead`: s15Fixed16 divided by 65535 → `ICCReadTests.colourantsExact`; `curv` count 1 read as a table → `.gammaCurve`; tag bounds `<=` for `<` → `ICCFuzzTests.tagPastEndThrows` |
| CP-4 | `ICCWriteTests`: `ColorProfile(iccData: p.iccData()) == p` for the three built-ins and 50 seeded primaries-and-gamma profiles; the size is a multiple of 4; the header's size field equals the byte count | a written profile reads back different | `CoreColor.ICCWrite`: padding skipped → `ICCWriteTests.sizeMultipleOfFour`; `chad` omitted → `.roundTripsAdapted` |
| CP-5 | `ProfileTransformTests`: sRGB → sRGB is identity within 1e-9; sRGB → Display P3 equals `Color3.converted(from: .sRGB, to: .displayP3)` within 3/65536 linear (the matrix part) and 13 × 3/65536 encoded, not 1e-6: the built-ins sit on the ICC s15Fixed16 grid (#509) so CP-4's built-in round trip is exact, which moves them up to 2^-16 off CoreColor's unrounded matrices; a table curve inverts within 1e-5; gray → sRGB gives r == g == b | the adaptation or a curve is wrong | `CoreColor.ProfileTransform`: target matrix not inverted → `ProfileTransformTests.sRGBToP3MatchesCoreColor`; curve inversion clamps → `.tableInverts` |
| CP-6 | `ProfileConvertTests`: converting there and back is identity within 1e-5; alpha unchanged; transparent pixels unchanged; out-of-gamut values stay finite | colour clips or alpha moves | `CoreRaster.ProfileConvert`: premultiplied values converted → `ProfileConvertTests.unpremultipliesFirst`; clamp to 0…1 → `.keepsOutOfGamut` |
| CP-7 | `PSDDeepTests`: 16-bit RGB and gray round-trip `==` at 16 bits; the ICC resource reads back the profile; an 8-bit file still reads as before | a 16-bit sample loses bits | `CoreRaster.PSDDeep`: little-endian samples → `PSDDeepTests.bigEndianSamples`; resource 1039 skipped → `.profileRoundTrips` |
| CP-8 | `ORADeepTests`: 16-bit layers round-trip through the raw `PixelCodec` at 16 bits; `profile.icc` read back | the depth or profile is lost | `CoreRaster.ORADeep`: depth passed as 8 → `ORADeepTests.sixteenBitsKept`; profile entry dropped → `.profileEntry` |
| CP-9 | `ProfileWalkTests.walk`; `ProfileBudgetTests`: converting 24 MP ≤ 150 ms; opening a 12 MP 16-bit PSD ≤ 1.3 × the 8-bit time (release, reported) | the walk's checks fail | none |
| CP-10 | parts' words; status line says built | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Convert a photo | 24 MP ≤ 150 ms | `ProfileBudgetTests.convert24MP` (release, reported) |
| 16-bit costs little | a 16-bit open ≤ 1.3 × the 8-bit one | `ProfileBudgetTests.deepOpen` |
| Exact at 16 bits | 16-bit round trips are `==` | `PSDDeepTests`, `ORADeepTests` |
| Never crashes | 1,000 ICC fuzz cases | `ICCFuzzTests` |
| Linux-safe | Foundation only | `scripts/ci` |

## Done check

Per slice as usual; CP-z's budgets on the Mac (`Mac-Finish-Wanted: CP-z`).

## Adopted later

**W3:** Photo's Assign Profile, Convert to Profile and 16-bit documents
(P+2.1), the export sheet's embed-profile row through S11; Library, Halo,
Design and Flare later read embedded profiles at one adopt slice each.

## Not in this packet

LUT-based and CMYK profiles, soft proofing, rendering intents beyond
relative colorimetric, 32-bit float documents, HDR and EDR display.
