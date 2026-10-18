# Feature packet: engine-contracts

**Feature:** the one contract slice the beta-80 W1 engines build on, so
nine features can run side by side without sharing a file. It widens the
`RenderBackend` contract with four CPU-first op families (`maskedComposite`,
`affine`, `effect`, `color`) and the W1 tone cases, declares every new
CoreRaster value type, adds the FlareCore model fields W1 needs (layer masks
and track mattes, styled text, colour and path tracks) with format checks
and old-file loading, splits the command registry, undo steps and the two
exporters along W1's seams, and gives every shared C4 part the folders and
words the W1 features will fill. Every new signature is a documented stub:
it throws `RenderError.unsupported(op)` or `RasterError.invalid("not built:
…")`, so callers and tests compile today and each feature fills only its
own files.
**Line:** `line:core` · **Wave:** 5 (`waves.md`) · **Lead branch:** `lead/engine-contracts`
**Status:** planned

**Covers:** the beta-80 plan (`paw-workspace/docs/design/drafts/2026-10-18-beta-80-plan.md`)
section 8, "Contract and description updates"; rows E2, E3, E4, E5, E8, E14
(their shared-file halves). Not a plan row of its own: it is the
contract-first split (`docs/factory/lead.md` rules 12 and 18) that lets
those rows run in one wave.

**Depends on:** nothing open. Base: `origin/dev` 4f91e04 (2026-10-18).
**Unblocks:** wave 6 (`masks-mattes`, `tone-pack`, `effects-engine`,
`affine-composite`, `fill-tools`, `retouch-heal`, `text-engine`,
`animate-properties`; wave 6's `color-profiles` waits on `layered-codecs`
instead) and the slices of wave-5 features
that name `engine-contracts:<slice>`.

**C4:** no new component. Edits the parts `corerender/contract`,
`corerender/cpu-backend`, `corerender/dispatcher`, `corerender/parity`,
`corerender/metal-support`, `coreraster/image-ops`, `coreraster/compositing`,
`flarecore/document-commands`, `flarecore/timeline` and `flarecore/export`:
new folder paths (so W1 files need no further part edit) and one sentence
each naming what its W1 folder or seam file holds. W1 features never edit
these shared parts, so nine of them never chain through one JSON file; a
feature whose result differs from its sentence files a `gap` for EC's
owner to fix.
`flarecore/geometry` is `path-geometry`'s; `coreraster/codecs`,
`corecolor/icc-profiles`, `coreasset/thumbnail-store` and `flarecore/import`
are new parts their features add.

**Clean-room.** Signatures and rules come from this repo's code and the
plan; no task reads another product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| EC-a | CoreRaster declares the W1 value types and CoreRender's contract lists the four new families, the W1 tone cases, the new backend methods with "not on this backend" defaults, `RenderOp.notOnMetalYet`, and a `FakeBackend` that records the new calls, so every W1 caller compiles. | EC-1, EC-2, EC-3 | `W1ContractTests`, `RenderBackendFakeTests` | nothing |
| EC-b | `RenderDispatcher` forwards every new method by its family and routes each tone adjustment by `ToneAdjustment.family`, the CPU backend answers every new family with a per-family stub file, and the parity harness reads one sample file per family, all empty until their feature fills them. | EC-4, EC-5 | `RenderDispatcherW1Tests`, `ParityHarnessTests` | EC-a (EC-4, EC-5) |
| EC-f | FlareCore files carry layer masks, track mattes, text runs, paragraph and path-text styles, colour tracks and shape tracks, old files load unchanged, `FlareFormat.validate` refuses bad values, and the registry, undo steps and exporters have one file per W1 family. | EC-6, EC-7, EC-8 | `W1ModelTests`, `CommandRegistryTests`, `SVGExporterTests`, `LottieExporterTests` | nothing |
| EC-z | A walk over the fakes calls every W1 signature once and gets its stub answer, the shared parts say what W1 adds, and the feature is built. | EC-9, EC-10 | `W1ContractWalkTests` | EC-a, EC-b, EC-f |

`ui_slice: none`: an engine contract with no screen. Its screens are the
app features each W1 engine lists under "Adopted later".

## Journey steps

Engine only. KJ-EC: `W1ContractWalkTests.walk` (EC-9) builds a 64 × 64
buffer, sends one call per new method through a `RenderDispatcher` over a
`FakeBackend` that supports none of the new families, and checks that each
reached the CPU backend and threw `unsupported(<family>)`; then it decodes a
v1 `.flare` with no W1 fields and one with all of them, and validates both.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/W1/W1Values.swift (EC-1): values only, Linux-safe
public struct AffineMatrix: Hashable, Sendable { public var a, b, c, d, tx, ty: Double
    public static let identity: AffineMatrix; public var inverse: AffineMatrix? { get } }   // nil when singular
public enum FlipAxis: Hashable, Sendable { case horizontal, vertical }
public enum CanvasAnchor: Hashable, Sendable { case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight }
public enum MatteSource: Hashable, Sendable { case alpha, luminance }                       // Mask(from:_:)
public struct HSLShift: Hashable, Sendable { public var hue, saturation, lightness: Float }  // -100...100 each
public struct HSLAdjustment: Hashable, Sendable { public var reds, oranges, yellows, greens, aquas, blues, purples, magentas: HSLShift }
public struct GrayMix: Hashable, Sendable { public var reds, yellows, greens, cyans, blues, magentas: Float; public var tint: RGBA? }  // tint: straight sRGB-encoded, alpha = strength
public struct ChannelMatrix: Hashable, Sendable { public var red, green, blue: SIMD4<Float>; public var monochrome: Bool }  // rgb weights + constant
public struct ToneBalance: Hashable, Sendable { public var shadows, midtones, highlights: SIMD3<Float>; public var preserveLuminosity: Bool }
public struct GradientMapStop: Hashable, Sendable { public var offset: Float; public var color: RGBA }  // color: straight sRGB-encoded, alpha ignored
public struct ColorLUT: Hashable, Sendable { public let size: Int; public let table: [SIMD3<Float>]   // size³ entries, r fastest, sRGB-encoded 0...1
    public init(size: Int, table: [SIMD3<Float>]) throws }                                           // 2...65, count checked
public enum LayerEffect: Hashable, Sendable {
    case boxBlur(radius: Double), motionBlur(degrees: Double, distance: Double), denoise(strength: Double, detail: Double)
    case clarity(amount: Double, radius: Double), glow(color: RGBA, radius: Double, intensity: Double, inner: Bool)
    case shadow(color: RGBA, dx: Double, dy: Double, blur: Double, inner: Bool), stroke(color: RGBA, width: Double, position: StrokePosition)
}
public enum StrokePosition: Hashable, Sendable { case outside, inside, center }
public enum FillTolerance: Hashable, Sendable { case exact; case within(Float) }          // 0...1 in OKLab distance
public enum RasterGradientShape: Hashable, Sendable { case linear, radial, angle, reflected, diamond }

// Sources/CoreRender/RenderOp.swift (EC-2): four families, CPU-first
case maskedComposite, affine, effect, color
public static let notOnMetalYet: Set<RenderOp> = [.maskedComposite, .affine, .effect, .color]   // R2 ports them

// Sources/CoreRender/ToneAdjustment.swift (EC-2): the color family
case vibrance(Float), hueSaturation(hue: Float, saturation: Float, lightness: Float), hsl(HSLAdjustment)
case blackAndWhite(GrayMix), channelMixer(ChannelMatrix), colorBalance(ToneBalance)
case gradientMap([GradientMapStop]), lut(ColorLUT), posterize(levels: Int), threshold(Float), invert
public var family: RenderOp { get }   // the six existing cases → .adjust, the rest → .color

// Sources/CoreRender/RenderBackend.swift (EC-2): new requirements
func composite(_ s: RenderSurface, onto b: inout RenderSurface, x: Int, y: Int, mode: BlendMode, opacity: Float,
               mask: Mask, maskX: Int, maskY: Int) throws                                       // .maskedComposite
func transformed(_ s: RenderSurface, _ m: AffineMatrix, width: Int, height: Int, filter: ResampleFilter) throws -> RenderSurface  // .affine
func flipped(_ s: RenderSurface, _ axis: FlipAxis) throws -> RenderSurface                       // .affine
func composite(_ s: RenderSurface, onto b: inout RenderSurface, through m: AffineMatrix, mode: BlendMode,
               opacity: Float, filter: ResampleFilter) throws                                    // .affine
func applying(_ s: RenderSurface, _ effect: LayerEffect) throws -> RenderSurface                 // .effect
// Sources/CoreRender/RenderBackend+NotOnThisBackend.swift (EC-2): a default per new method that throws
// RenderError.unsupported(<its family>), so MetalBackend compiles unchanged; CPUBackend and FakeBackend implement them.
```

CoreRaster stubs the features fill (each in the feature's own file, named
in its packet): `Mask.feathered(radius:)`, `Mask.contours(level:)`,
`Mask.coveredBounds`, `Mask(from:_:)`, `composite(…, mask:maskX:maskY:)`
(`masks-mattes`); the colour ops and `ToneAuto.suggest` (`tone-pack`);
`PixelBuffer.applying(_:)` (`effects-engine`); `transformed`, `flipped`,
`padded(width:height:anchor:)`, `composite(…, through:)` (`affine-composite`).
EC-1 declares none of them: a feature adds its own functions in its own
files, so EC-1 owns only values.

FlareCore model (EC-6, `Sources/FlareCore/Document.swift` and the new
`Sources/FlareCore/W1Model.swift`), every field optional or defaulted and
decoded with `decodeIfPresent`:

```swift
public struct LayerMask: Codable, Sendable, Hashable { public var path: Path; public var mode: MaskMode
    public var feather: Double; public var opacity: Double; public var inverted: Bool }
public enum MaskMode: String, Codable, Sendable, Hashable { case add, subtract, intersect, difference }
public struct TrackMatte: Codable, Sendable, Hashable { public var sourceLayerID: String; public var kind: MatteKind }
public enum MatteKind: String, Codable, Sendable, Hashable { case alpha, alphaInverted, luma, lumaInverted }
public struct TextRun: Codable, Sendable, Hashable { public var start: Int; public var length: Int   // grapheme offsets
    public var fontFamily: String?; public var fontSize: Double?; public var weight: Int?; public var italic: Bool?
    public var fill: Fill?; public var tracking: Double?; public var baselineShift: Double? }
public struct ParagraphStyle: Codable, Sendable, Hashable { public var alignment: TextAlignment
    public var lineHeight: Double; public var tracking: Double; public var paragraphSpacing: Double; public var boxWidth: Double? }
public enum TextAlignment: String, Codable, Sendable, Hashable { case leading, center, trailing, justified }
public struct TextOnPath: Codable, Sendable, Hashable { public var path: Path; public var startOffset: Double; public var flipped: Bool }
public struct ColorKeyframe: Codable, Sendable, Hashable { public var frame: Int; public var value: Color; public var easing: Easing }
public struct PathKeyframe: Codable, Sendable, Hashable { public var frame: Int; public var path: Path; public var easing: Easing }
public struct ShapeTrack: Codable, Sendable, Hashable { public var shapeIndex: Int; public var keys: [PathKeyframe] }
// Layer gains: masks: [LayerMask] = [], matte: TrackMatte? = nil,
//   colorTracks: [String: [ColorKeyframe]] = [:]   // keys "fill.<shape>", "stroke.<shape>", "text.<index>"
//   shapeTracks: [ShapeTrack] = []
// TextShape gains: runs: [TextRun] = [], paragraph: ParagraphStyle? = nil, onPath: TextOnPath? = nil
```

`FlareFormat.validate` (EC-6) adds: finite values, `feather` and `opacity`
in range, at most 32 masks per layer, a matte's source is another layer of
the same owner and no layer is its own matte's source (directly or through a
chain), runs inside the string and not overlapping, `lineHeight` 0.5...4,
key frames inside the duration and sorted, at most 4,096 keys per track.

Seams (EC-7, EC-8): `CommandRegistry.builtInFamilies` gains `MaskCommands.all`,
`TextStyleCommands.all` and `TrackCommands.all` (each `[]` in its own new
file); `UndoPropertyTests.allSteps` gains each family's `undoSteps` (empty);
`CommandRegistryTests.expectedIDs` becomes the union of a per-family
`expectedIDs` in each family's test file, so a new command touches only its
family's two files. `SVGExporter` and `LottieExporter` move their mask, text
and track writing into `SVGExporter+Masks.swift`, `SVGExporter+Text.swift`,
`SVGExporter+Style.swift`, `LottieExporter+Masks.swift` and
`LottieExporter+Tracks.swift` with no change to any output byte.

## Pseudocode

- **Family routing.** `RenderDispatcher.adjusted(s, a)`: `run(a.family, s)`.
  Each new method: `run(<its family>, s)`; the two composites with a
  backdrop reuse the backdrop path `composite` already has (upload, replace
  the caller's handle).
- **Metal holdout.** `MetalCapabilities` never enables a family in
  `notOnMetalYet`; `AdjustTable` throws `unsupported(.color)` for a `.color`
  case (the dispatcher never sends one); `MetalBackend+Warmup`'s `switch op`
  skips the four. `ParityTests.everyFamilyIsOn` expects
  `all.subtracting(RenderOp.notOnMetalYet)` (and the in-place rule as now).
  R2 removes a family from the set when its kernel and parity test land.
- **Parity files.** `ParitySamples.sampleSet(for:)`'s new arms return
  `MaskedCompositeSamples.all`, `AffineSamples.all`, `EffectSamples.all`,
  `ColorSamples.all` (each `[]`), and `ParityPack.all` appends each file's
  `packs` (each `[]`), so `CPUGoldenTests` has nothing new until a feature
  adds samples and their goldens.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| EC-1 | feature issue | CoreRaster W1 value types with doc comments and their checked inits; `image-ops` and `compositing` parts gain the folders `Sources/CoreRaster/{W1,Masks,Tone,Effects,Affine,Fill,Heal,Hash}/` and `Sources/CoreRaster/Compositing/` and one sentence per folder | `Sources/CoreRaster/W1/W1Values.swift`, `Tests/CoreRasterTests/W1ValuesTests.swift`, `Tests/mutations/CoreRaster.W1Values.json`, `docs/c4/parts/creative-core/coreraster/image-ops.json`, `docs/c4/parts/creative-core/coreraster/compositing.json` | – | ~260, 5 |
| EC-2 | – | `RenderOp`'s four families and `notOnMetalYet`; the W1 `ToneAdjustment` cases and `family`; the new `RenderBackend` requirements and their throwing defaults; `RenderContractTests` counts 13 families; `W1ContractTests` written | `Sources/CoreRender/RenderOp.swift`, `Sources/CoreRender/ToneAdjustment.swift`, `Sources/CoreRender/RenderBackend.swift`, `Sources/CoreRender/RenderBackend+NotOnThisBackend.swift`, `Tests/CoreRenderTests/RenderContractTests.swift`, `Tests/CoreRenderTests/W1ContractTests.swift`, `Tests/mutations/CoreRender.W1Contract.json`, `docs/c4/parts/creative-core/corerender/contract.json` | EC-1 | ~320, 8 |
| EC-3 | – | `FakeBackend` records the five new calls and honours its `supports` for them; the Metal holdout (`AdjustTable`, `MetalCapabilities`, `MetalBackend+Warmup`, `everyFamilyIsOn`); `Unverified on Linux:` the two Metal files, `Mac-Finish-Wanted` | `Sources/CoreRender/FakeBackend.swift`, `Sources/CoreRender/Metal/AdjustTable.swift`, `Sources/CoreRender/Metal/MetalCapabilities.swift`, `Sources/CoreRenderMetal/MetalBackend+Warmup.swift`, `Tests/CoreRenderTests/RenderBackendFakeTests.swift`, `Tests/CoreRenderTests/AdjustTableTests.swift`, `Tests/CoreRenderMetalTests/ParityTests.swift`, `Tests/mutations/CoreRenderFake.json`, `docs/c4/parts/creative-core/corerender/metal-support.json` | EC-2 | ~240, 9 |
| EC-4 | – | `RenderDispatcher` forwarders for the five methods and `adjusted` by `family`; the CPU stubs, one file per family (`CPUBackend+MaskedComposite.swift`, `+Affine`, `+Effect`, `+Color`), and the `.color` arm in `CPUBackend+Ops`'s `switch` calling `+Color` | `Sources/CoreRender/RenderDispatcher.swift`, `Sources/CoreRender/CPU/CPUBackend+Ops.swift`, `Sources/CoreRender/CPU/CPUBackend+MaskedComposite.swift`, `Sources/CoreRender/CPU/CPUBackend+Affine.swift`, `Sources/CoreRender/CPU/CPUBackend+Effect.swift`, `Sources/CoreRender/CPU/CPUBackend+Color.swift`, `Tests/CoreRenderTests/RenderDispatcherW1Tests.swift`, `Tests/mutations/CoreRenderDispatcherW1.json`, `docs/c4/parts/creative-core/corerender/dispatcher.json`, `docs/c4/parts/creative-core/corerender/cpu-backend.json` | EC-2 | ~300, 10 |
| EC-5 | – | The parity seams: the four new `sampleSet` arms, `ParityPack.all` appending each family file's `packs`, the empty `Samples+MaskedComposite.swift`, `+Affine`, `+Effect`, `+Color` | `Sources/CoreRender/Parity/ParitySamples.swift`, `Sources/CoreRender/Parity/ParityPack.swift`, `Sources/CoreRender/Parity/Samples+MaskedComposite.swift`, `Sources/CoreRender/Parity/Samples+Affine.swift`, `Sources/CoreRender/Parity/Samples+Effect.swift`, `Sources/CoreRender/Parity/Samples+Color.swift`, `Tests/CoreRenderTests/ParityHarnessTests.swift`, `docs/c4/parts/creative-core/corerender/parity.json` | EC-2 | ~160, 8 |
| EC-6 | – | The W1 model fields in `Document.swift` and `W1Model.swift`, their `FlareFormat.validate` rules, the old-file decode test and a fuzz pass over the new fields; `document-commands` and `timeline` parts name the new files as globs, so a feature's second file needs no part edit (`W1Model.swift`, `MaskCommands*.swift`, `TextStyleCommands*.swift`, `TextLayout*.swift`, `TrackCommands*.swift`, `Sampling+Tracks*.swift`) | `Sources/FlareCore/Document.swift`, `Sources/FlareCore/W1Model.swift`, `Sources/FlareCore/FlareFormat.swift`, `Tests/FlareCoreTests/W1ModelTests.swift`, `Tests/mutations/FlareW1Model.json`, `docs/c4/parts/creative-core/flarecore/document-commands.json`, `docs/c4/parts/creative-core/flarecore/timeline.json` | – | ~360, 7 |
| EC-7 | – | Registry and undo seams: the three empty families and their test files with empty `undoSteps` and `expectedIDs`; `CommandRegistryTests.expectedIDs` as the union of every family's list | `Sources/FlareCore/CommandRegistry.swift`, `Sources/FlareCore/MaskCommands.swift`, `Sources/FlareCore/TextStyleCommands.swift`, `Sources/FlareCore/TrackCommands.swift`, `Tests/FlareCoreTests/CommandRegistryTests.swift`, `Tests/FlareCoreTests/UndoPropertyTests.swift`, `Tests/FlareCoreTests/MaskCommandsTests.swift`, `Tests/FlareCoreTests/TextStyleCommandsTests.swift`, `Tests/FlareCoreTests/TrackCommandsTests.swift` | EC-6 | ~240, 9 |
| EC-8 | – | Exporter seams: move mask, text, style and track writing into the five extension files, byte for byte (the existing exporter tests and goldens are the oracle) | `Sources/FlareCore/Export/SVGExporter.swift`, `Sources/FlareCore/Export/SVGExporter+Masks.swift`, `Sources/FlareCore/Export/SVGExporter+Text.swift`, `Sources/FlareCore/Export/SVGExporter+Style.swift`, `Sources/FlareCore/Export/LottieExporter.swift`, `Sources/FlareCore/Export/LottieExporter+Masks.swift`, `Sources/FlareCore/Export/LottieExporter+Tracks.swift`, `docs/c4/parts/creative-core/flarecore/export.json` | EC-6 | ~300, 8 |
| EC-9 | – | KJ-EC, the walk over the fakes and both files | `Tests/CoreRenderTests/W1ContractWalkTests.swift`, `Tests/FlareCoreTests/W1FileWalkTests.swift` | EC-3, EC-4, EC-5, EC-7, EC-8 | ~160, 2 |
| EC-10 | – | The packet's status line; `docs/engineering.md` names the CPU-first families, the seam files and the path-ops rules; `feature-done` | `docs/blueprints/core/features/engine-contracts.md`, `docs/engineering.md` | EC-9 | ~80, 2 |

EC-1 and EC-6 share nothing, so the render and the FlareCore halves start
together. EC-3, EC-4 and EC-5 each own different files after EC-2. EC-7 and
EC-8 split after EC-6. `CPUBackend+Ops.swift` is the one existing CPU file
touched (EC-4); later features own only their `+<Family>` file.

## Build waves

- Wave 1: EC-1, EC-6. Independent in this wave: both.
- Wave 2: EC-2, EC-7, EC-8. Independent in this wave: all three.
- Wave 3: EC-3, EC-4, EC-5. Independent in this wave: all three.
- Wave 4: EC-9. Independent in this wave: EC-9 alone.
- Wave 5: EC-10 (`feature-done`, final). Independent in this wave: EC-10 alone.

Longest chain: EC-1 → EC-2 → EC-3 → EC-9 → EC-10 (5). Chain of 5: EC-2's
protocol needs EC-1's values, EC-3 conforms the fake and Metal to it, the
walk calls all of it, EC-10 is the final prose task.

## Acceptance test per task

Checks first (rule 13): `W1ContractTests` lands in EC-2, EC-a's first code
task, with its fake-call cases disabled by name (`waits on EC-3`).
`RenderDispatcherW1Tests` lands in EC-4, EC-b's first code task, and
`W1ModelTests` in EC-6, EC-f's first.

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| EC-1 | `W1ValuesTests`: `AffineMatrix.identity.inverse == identity`, a singular matrix's `inverse` is nil, a scale-rotate's inverse composes to identity within 1e-12; `ColorLUT` refuses size 1 and 66 and a short table; every value is `Hashable` | a singular matrix inverts or a bad LUT is made | `CoreRaster.W1Values`: determinant test `== 0` becomes `< 1e-300` → `W1ValuesTests.singularHasNoInverse`; LUT count check `<` for `!=` → `.refusesShortTable` |
| EC-2 | `W1ContractTests`: 13 families; `notOnMetalYet` is exactly the four; every old tone case has `family == .adjust` and every new one `.color`; a backend with only the defaults throws `unsupported(<family>)` from each new method | a case maps to the wrong family or a default throws the wrong family | `CoreRender.W1Contract`: `.invert` mapped to `.adjust` → `W1ContractTests.colorCasesAreColor`; `flipped` default throws `.transform` → `.defaultsNameTheirFamily` |
| EC-3 | `RenderBackendFakeTests`: the fake records each new call and throws `unsupported` for a family it doesn't list; `AdjustTableTests`: a `.color` case throws `unsupported(.color)`; on the Mac, `ParityTests.everyFamilyIsOn` | the fake drops a call or Metal claims a W1 family | `CoreRenderFake`: new calls ignore `supports` → `RenderBackendFakeTests.w1HonoursSupports`; recorded call loses the mask offset → `.w1RecordsArguments` |
| EC-4 | `RenderDispatcherW1Tests`: with a fake preferring every old family, each new method reaches the CPU with `lastFallback == (<family>, "unsupported")`; `.contrast` goes to the fake and `.vibrance` to the CPU; a fake backdrop for the masked composite is uploaded and the caller's handle replaced | a W1 call goes to a backend that can't run it | `CoreRenderDispatcherW1`: `adjusted` routes by `.adjust` always → `RenderDispatcherW1Tests.colorCasesFallBack`; masked composite routed by `.composite` → `.maskedCompositeIsItsOwnFamily` |
| EC-5 | `ParityHarnessTests`: `sampleSet(for:)` of each new family is `[]` and deterministic; `ParityPack.all.count` unchanged; every old family's set is unchanged | an old family's samples change | none: seams (the old-family assertions guard them) |
| EC-6 | `W1ModelTests`: a v1 file decodes with every new field at its default and re-encodes with no new key; a file with each field round-trips; `validate` refuses a NaN feather, opacity 1.5, a self matte, a two-layer matte cycle, overlapping runs, a run past the string, `lineHeight` 5, an unsorted colour track, 4,097 keys; 200 seeded fuzz mutations of the new fields throw or validate, never crash | an old file gains keys, or a bad value validates | `FlareW1Model`: matte cycle check looks one step only → `W1ModelTests.refusesMatteCycleTwoDeep`; run overlap uses `<` for `<=` → `.refusesTouchingRunsThatOverlap`; key cap 4096 becomes 4097 → `.capsKeysAt4096` |
| EC-7 | `CommandRegistryTests`: the union of family lists equals `ids` (58 today) and every family file's list is unique; the three new families are registered and empty; `UndoPropertyTests` unchanged and green | a family's ids leak into another's list | none: seams |
| EC-8 | `SVGExporterTests`, `SVGRenderListTests`, `LottieExporterTests`, `LottieTracksTests`, `LottieGradientAlphaTests`: every existing expectation and golden byte unchanged | any output byte moves | none: a move (the existing tests guard it) |
| EC-9 | `W1ContractWalkTests.walk`, `W1FileWalkTests.walk` (KJ-EC) | a stub traps, or an old file stops loading | none: walk |
| EC-10 | `docs/engineering.md` names every seam file once; status line says built | a seam file is unnamed | none |

## Quality tests

| quality row | budget | test |
|---|---|---|
| No pixel moves | every existing CPU, dispatcher and parity test passes unchanged | `scripts/ci` |
| Old files load | a v1 `.flare` decodes and re-encodes byte for byte | `W1ModelTests.v1RoundTripsByteForByte` |
| Metal stays green | Metal claims no W1 family; `everyFamilyIsOn` holds on the Mac | `ParityTests.everyFamilyIsOn` (Mac finisher) |
| Linux-safe | no new import beyond FoundationEssentials or Foundation | `scripts/ci` |
| No crash | the no-crash lint; the fuzz pass over the new fields | `scripts/ci`, `W1ModelTests.fuzzNeverCrashes` |

## Done check

Per slice: tasks merged, tests green on the newest dev run containing the
slice's last PR, every plan scored with no escape. EC-a also needs the Mac
finisher's `Mac-Finish: EC-a` for `everyFamilyIsOn` and the Warmup switch
(rule 17). Then `Belt-Contact-Sheet:` and the wave-6 leads start: each W1
packet names the `engine-contracts:<slice>` it waits on.

## Adopted later

Nothing adopts this directly; it is the seam. Its families are filled by the
wave-6 packets and ported to Metal by R2 (beta-80 plan W4).

## Not in this packet

Any op body (each W1 feature). Metal kernels for the four families (R2). A
`retouch` heal family: `retouch-heal` runs on CoreRaster directly, so the
contract does not grow a fifth family (see that packet). The kernel's
`Effects` stack (S2, creative-apps).
