# Feature packet: layer-style-engine

**Feature:** the pixels of a layer style, built once for every app. CoreRaster
gets bevel and emboss (height from the alpha `DistanceField`, then directional
light with highlight and shadow colours, depth, size, soften, angle and
altitude), colour and gradient overlays as style ops, and one compositor,
`PixelBuffer.styled(_ stack: LayerStyleStack)`, that draws every style entry
(drop and inner shadow, outer and inner glow, stroke, overlays, bevel) in a
fixed paint order, each with its own blend mode and opacity, plus the layer's
fill opacity. CoreRender gets a `style` family on the CPU backend, and
CoreRenderMetal a Metal path for it (a jump-flood distance field and the style
kernels), so apps redraw a style live in one GPU pass. The PSD reader keeps
layer effects (`lfx2`) as a `LayerStyleStack` on the layer and names what it
drops, and `BlendMode` gains Linear Dodge and Linear Burn. Linux-safe but the
Metal half.
**Line:** `line:core` · **Wave:** 7 (`waves.md`) · **Lead branch:** `lead/layer-style-engine`
**Status:** planned. Beta (captain, 2026-10-21: "layer styles in beta,
shared"); labels `beta` and `p1` when filed.

**Covers:** creative-apps feature map S2 (the engine half of layer styles;
packet `suiteui/layer-styles` in creative-apps); the core half of
creative-apps findings #3496 (PSD import drops layer effects) and #3497 (PSD
blend keys `lddg` and `lbrn` open as Normal); the effect half of R2 for
styles (the `style` family on Metal; the `effect` family's own Metal port
stays R2's). Effects-engine's "Not in this packet" bevel and emboss.

**Depends on:** effects-engine (built: `DistanceField`, `stroked`,
`glowing`, `shadowed`, three-pass box blur), fill-tools (built:
`RasterGradient`), masks-mattes (built), layered-codecs (built: `PSD.read`,
`LayeredImage`), metal-backend's built kernels (blur, composite, blend). No
open wait.

**Unblocks (creative-apps, each through a `scripts/bump-core` PR):** LE-a
before `suiteui/layer-styles` LS-1 (its model stores `StrokePosition`, which
LE-1 makes `Codable`); LE-cpu before LS-8 (`StyleProgram` on the CPU); LE-metal
before LS-9 (`StyleRoute`); LE-psd before `photo/psd-effects` PS-3 and PS-4.

**C4:** container `coreraster`, components `image-ops`
(`Effects/LayerStyleStack.swift`, `Effects/Bevel.swift`,
`Effects/StyleComposite.swift`), `codecs` (`PSDEffects.swift`,
`PSDDescriptor.swift`) and `compositing` (`BlendMode.swift`); container
`corerender`, components `contract` (`RenderOp.style`), `cpu-backend`
(`CPUBackend+Style.swift`) and `parity` (`Samples+Style.swift`); container
`corerendermetal` (`MetalBackend+Style.swift`, `StyleShader.swift`). New
files sit in folders their parts already cover, so no new part; LE-11 edits
the `image-ops` and `corerendermetal` descriptions.

**Clean-room.** Height from a Euclidean distance field, Lambert and
Blinn-Phong lighting, the jump-flood algorithm (Rong and Tan, "Jump Flooding
in GPU with Applications to Voronoi Diagram and Distance Transform", I3D 2006)
and the separable blend formulas (W3C Compositing and Blending Level 1, which
defines no linear dodge or burn; ours are `min(1, b + s)` and
`max(0, b + s - 1)`) are published. The PSD effects descriptor comes from
Adobe's public Photoshop File Formats Specification (object-based effects
layer info, `lfx2`): a published spec, not reverse engineering, the same
source layered-codecs' reader follows. Defaults are the caller's. No task reads another
product's code.

## Slices

| slice | behavior (one sentence) | tasks | checks | waits on |
|---|---|---|---|---|
| LE-a | The style types, the `style` render family with its CPU, fake, dispatcher and Metal-warmup seams, `LayeredImage`'s `style` and `notes`, and every check are in, the bodies stubbed and the checks disabled. | LE-1, LE-2 | `StyleCompositeTests`, `BevelTests`, `CPUStyleTests`, `PSDEffectsTests`, `MetalStyleTests` | – |
| LE-cpu | Bevel and emboss light an edge from its distance field by angle and altitude in all four shapes, overlays fill the layer's alpha with a colour or gradient, and `styled` draws a stack in paint order with each entry's mode and opacity, equal on the CPU backend. | LE-3, LE-4, LE-5 | `BevelTests`, `StyleCompositeTests`, `CPUStyleTests`, `CPUGoldenTests` | LE-a |
| LE-psd | `PSD.read` turns a layer's `lfx2` effects into its `LayerStyleStack`, notes each effect it can't hold, and opens Linear Dodge and Linear Burn as themselves on CPU and Metal. | LE-6, LE-7 | `PSDEffectsTests`, `BlendModeTests`, `MetalBlendTests` | LE-a; LE-cpu (LE-6 maps onto its ops) |
| LE-metal | The Metal backend claims `style`: a jump-flood distance field and the style kernels draw a stack in one encode, within the parity tolerance of the CPU, and `style` leaves `notOnMetalYet`. | LE-8, LE-9 | `MetalStyleTests`, `MetalStyleParityTests` | LE-cpu |
| LE-z | A walk styles a badge on both backends and from a PSD, the budgets hold, and the feature is built. | LE-10, LE-11 | `StyleWalkTests`, `StyleBudgetTests` | LE-psd, LE-metal |

`ui_slice: none`: engine only. Its screens are creative-apps'
`suiteui/layer-styles` panel and the Photo, Design and Halo adopts.

## Journey steps

Engine only. KJ-LE (`StyleWalkTests.walk`, LE-10): a 400 × 300 white
rounded-rectangle badge on transparency, padded by the stack's `reach`; a
stack of drop shadow (black, Multiply, 50%, dx 6, dy 6, blur 12), outer glow
(Screen, 10 px), stroke (4 px outside, crimson), gradient overlay (blue to
white, top to bottom, 60%), inner shadow and an inner smooth bevel (size 8,
120°, altitude 30); through a `RenderDispatcher` with Metal off, then on:
each `==` the direct `styled` call on the CPU, Metal within tolerance; the
shadow's darkest pixel sits 6 px right and down of the badge's corner, the
lit edge faces 120°, and an entry with `isEnabled: false` changes nothing.
Then the same badge read back from a PSD the test writes with that `lfx2`:
`PSD.read`'s stack equals the one above within each field's PSD precision.

## Screens and states

None.

## Contract slice

```swift
// Sources/CoreRaster/Effects/LayerStyleStack.swift (LE-1; `styled` throws RasterError.invalid("styled is not built (LE-4)") until LE-4)
public enum BevelShape: String, CaseIterable, Codable, Sendable { case innerBevel, outerBevel, emboss, pillowEmboss }
public enum BevelTechnique: String, CaseIterable, Codable, Sendable { case smooth, chiselHard, chiselSoft }
public struct Bevel: Hashable, Sendable {
    public var shape: BevelShape, technique: BevelTechnique
    public var depth: Double, up: Bool, size: Double, soften: Double   // depth 0.01...10, size 0...250, soften 0...16 px
    public var angle: Double, altitude: Double                          // degrees: 0 is +x, 90 is +y (down); altitude 0...90
    public var highlight: RGBA, highlightMode: BlendMode, highlightOpacity: Float
    public var shadow: RGBA, shadowMode: BlendMode, shadowOpacity: Float
}
/// A colour or a gradient in the layer's pixel space.
public enum StyleFill: Hashable, Sendable {
    case color(RGBA)
    case gradient(stops: [RasterGradientStop], shape: RasterGradientShape, from: Mask.Point, to: Mask.Point)
}
public enum StyleOp: Hashable, Sendable {
    case dropShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    case innerShadow(color: RGBA, dx: Double, dy: Double, spread: Double, blur: Double)
    case outerGlow(color: RGBA, spread: Double, size: Double)
    case innerGlow(color: RGBA, spread: Double, size: Double)
    case stroke(fill: StyleFill, width: Double, position: StrokePosition)
    case overlay(StyleFill)
    case bevel(Bevel)
}
public struct StyleEntry: Hashable, Sendable {
    public var op: StyleOp; public var mode: BlendMode; public var opacity: Float; public var isEnabled: Bool
}
public struct LayerStyleStack: Hashable, Sendable {
    public var entries: [StyleEntry]; public var fillOpacity: Float
    public init(entries: [StyleEntry], fillOpacity: Float = 1)
    public var reach: Int { get }                      // px a caller pads on each side so nothing clips
}
extension PixelBuffer {
    public func styled(_ stack: LayerStyleStack) throws -> PixelBuffer                          // LE-4; same size
}
// Sources/CoreRaster/Effects/Bevel.swift (LE-3)
extension PixelBuffer {
    /// The bevel's two light layers, each the buffer's size: where the edge faces the light, and where it faces away.
    public func beveled(_ bevel: Bevel) throws -> (highlight: PixelBuffer, shadow: PixelBuffer)
}
// Sources/CoreRaster/W1/W1Values.swift (LE-1): StrokePosition becomes `String, CaseIterable, Codable`.
// Sources/CoreRaster/Codecs/LayeredImage.swift (LE-2)
public struct PixelLayer { ...; public var style: LayerStyleStack? = nil }   // nil when the file has none
public struct LayeredImage { ...; public var notes: [String] = [] }         // "<layer>: <what> (not kept)", in layer order
// Sources/CoreRaster/BlendMode.swift (LE-7)
public enum BlendMode { ...; case linearDodge, linearBurn }   // separable; PSD keys lddg, lbrn
// Sources/CoreRender/RenderOp.swift, RenderBackend+NotOnThisBackend.swift (LE-1)
public enum RenderOp { ...; case style }                   // in notOnMetalYet until LE-9
extension RenderBackend { func styled(_ s: RenderSurface, _ stack: LayerStyleStack) throws -> RenderSurface }
```

## Pseudocode

- **Paint order** (entries' order inside one kind is kept): under the layer,
  bottom up: drop shadow, outer glow, outside stroke; the layer times
  `fillOpacity`; over it, clipped to its alpha: overlay (a gradient before a
  colour), inner glow, inner shadow, bevel; then inside and centre strokes.
  Each entry composites with its `mode` and `opacity`; a disabled entry is
  skipped.
- **Spread** (shadows and glows): the alpha thresholded at
  `d ≤ spread·size` on the outside distance before the blur (`DistanceField`),
  so spread 1 is a hard edge the size of the reach.
- **Bevel height.** `d` = inside distance (inner bevel), outside distance
  (outer), both halved (emboss), outside inverted (pillow), divided by `size`
  and clamped to 0...1; smooth `h = 1 − (1 − d)²`, chisel hard `h = d`,
  chisel soft `h = d` blurred by 1 px; `up: false` gives `−h`; then box blur by
  `soften`. Normal `n = normalize(−∂h/∂x·depth·size, −∂h/∂y·depth·size, 1)`
  (central differences); light `l` from angle and altitude, y down;
  `s = n·l − l.z`: highlight where `s > 0` with coverage `s / (1 − l.z)`,
  shadow where `s < 0` with `−s / l.z`; both clipped to the alpha (outer
  bevel: to its complement within `size`).
- **Overlay.** The fill over the layer's alpha: a colour flood, or
  `RasterGradient` in the layer's pixel space (fill-tools' ramp and dither).
- **reach.** max over enabled entries: drop shadow `hypot(dx, dy) + blur`,
  outer glow `size`, outside stroke `width`, centre `width / 2`, outer bevel
  and emboss `size`; rounded up.
- **PSD.** A `lfx2` block (version 0, descriptor version 16, one descriptor)
  is read by a small descriptor reader (`long`, `doub`, `UntF`, `bool`,
  `enum`, `Objc`, `VlLs`, `TEXT`), then mapped: `DrSh`, `IrSh`, `OrGl`,
  `IrGl`, `FrFX` (`Styl` OutF, InsF, CtrF), `SoFi`, `GrFl`, `ebbl` (`bvlS`,
  `bvlT`, `srgR`, `bvlD`, `blur`, `Sftn`, `lagl`, `Lald`, `hglM`, `hglC`,
  `hglO`, `sdwM`, `sdwC`, `sdwO`); `Md  ` to `BlendMode` by key, `Opct` to
  opacity, `lagl` with `uglg` to the image's global angle (resources 1037
  and 1049), `masterFXSwitch` off disables every entry; fill opacity from the
  layer's `iOpa`. Satin (`ChFX`), pattern overlay, contours and the `*Multi`
  lists past their first item are noted, never kept. An `lfx2` the reader
  can't parse notes "<layer>: layer effects (unreadable, not kept)" and opens
  the layer bare. `lrFX` (the older block) is noted, not read.
- **Blend keys** (LE-7): `lddg` and `lbrn` read as `.linearDodge` and
  `.linearBurn` (today `.normal`); an unknown key still opens as Normal but
  adds a note naming it. Both join `blendSeparable` on Metal.
- **Metal** (LE-8, LE-9): the alpha's edge seeds a jump-flood pass
  (log2(max side) steps, then one 1+JFA cleanup step) giving inside and
  outside distances; shadows and glows reuse the three-pass box blur as a
  Metal kernel (matching the CPU's, not a Gaussian), and one style kernel per
  op blends into the result in paint order in the same command buffer. The
  stack's distance field is cached per surface until its alpha changes, so a
  colour, angle or opacity change re-runs only the light and blend kernels.

## Tasks

| id | issue | what | owned files | depends on | size |
|---|---|---|---|---|---|
| LE-1 | feature issue | The seam: the style types, `styled` stubbed, `StrokePosition` `Codable`, `RenderOp.style` in `notOnMetalYet`, the backend default, dispatcher routing, the fake, the CPU and parity stubs, every exhaustive switch over `RenderOp` | `Sources/CoreRaster/Effects/LayerStyleStack.swift`, `Sources/CoreRaster/W1/W1Values.swift`, `Sources/CoreRender/RenderOp.swift`, `Sources/CoreRender/RenderBackend+NotOnThisBackend.swift`, `Sources/CoreRender/RenderDispatcher.swift`, `Sources/CoreRender/FakeBackend.swift`, `Sources/CoreRender/CPU/CPUBackend+Style.swift`, `Sources/CoreRender/Parity/Samples+Style.swift`, `Sources/CoreRenderMetal/MetalBackend+Warmup.swift` | – | ~260, 9 |
| LE-2 | – | Checks first: five suites disabled by name; style fixtures (badge, disc, 1 px line, glyph mask); `PixelLayer.style` and `LayeredImage.notes` (stored, empty) | `Tests/CoreRasterTests/StyleCompositeTests.swift`, `Tests/CoreRasterTests/BevelTests.swift`, `Tests/CoreRasterTests/PSDEffectsTests.swift`, `Tests/CoreRasterTests/StyleFixtures.swift`, `Tests/CoreRenderTests/CPUStyleTests.swift`, `Tests/CoreRenderMetalTests/MetalStyleTests.swift`, `Sources/CoreRaster/Codecs/LayeredImage.swift` | – | ~380, 7 |
| LE-3 | – | `beveled`: height in the four shapes and three techniques, soften, lighting; turns on `BevelTests` | `Sources/CoreRaster/Effects/Bevel.swift`, `Tests/CoreRasterTests/BevelTests.swift`, `Tests/mutations/CoreRaster.Bevel.json` | LE-1, LE-2 | ~300, 3 |
| LE-4 | – | `styled`: spread, overlays, paint order, per-entry mode and opacity, fill opacity, `reach`; turns on `StyleCompositeTests` | `Sources/CoreRaster/Effects/StyleComposite.swift`, `Sources/CoreRaster/Effects/LayerStyleStack.swift`, `Tests/CoreRasterTests/StyleCompositeTests.swift`, `Tests/mutations/CoreRaster.StyleComposite.json` | LE-3 | ~340, 4 |
| LE-5 | – | The CPU backend's `styled`, `Samples+Style` and the CPU goldens; turns on `CPUStyleTests` | `Sources/CoreRender/CPU/CPUBackend+Style.swift`, `Sources/CoreRender/Parity/Samples+Style.swift`, `Tests/CoreRenderTests/CPUStyleTests.swift`, `Tests/CoreRenderTests/Golden/style/`, `Tests/mutations/CoreRenderCPUStyle.json` | LE-4 | ~180, 4 + goldens |
| LE-6 | #3496 (creative-apps) | The descriptor reader and the `lfx2` mapping with notes; turns on `PSDEffectsTests` | `Sources/CoreRaster/Codecs/PSDDescriptor.swift`, `Sources/CoreRaster/Codecs/PSDEffects.swift`, `Sources/CoreRaster/Codecs/PSDRead.swift`, `Tests/CoreRasterTests/PSDEffectsTests.swift`, `Tests/mutations/CoreRaster.PSDEffects.json` | LE-2, LE-4 | ~380, 5 |
| LE-7 | #3497 (creative-apps) | `linearDodge` and `linearBurn`: the CPU formulas, the PSD keys and the unknown-key note, the Metal separable shader cases | `Sources/CoreRaster/BlendMode.swift`, `Sources/CoreRaster/Codecs/PSD.swift`, `Sources/CoreRenderMetal/Shaders/BlendSeparableShader.swift`, `Tests/CoreRasterTests/BlendModeTests.swift`, `Tests/CoreRenderMetalTests/MetalBlendTests.swift`, `Tests/mutations/CoreRaster.BlendMode.json` | LE-6 | ~200, 6 |
| LE-8 | – | Metal: the jump-flood distance field and the three-pass box blur kernels, each with a parity test against `DistanceField` and `boxBlurred` | `Sources/CoreRenderMetal/MetalBackend+Distance.swift`, `Sources/CoreRenderMetal/Shaders/DistanceShader.swift`, `Tests/CoreRenderMetalTests/MetalDistanceTests.swift` | LE-5 | ~320, 3 |
| LE-9 | – | Metal: the style kernels and `styled` in one encode with the field cached per surface; `supports` gains `style`, `notOnMetalYet` loses it; turns on `MetalStyleTests` and `MetalStyleParityTests` | `Sources/CoreRenderMetal/MetalBackend+Style.swift`, `Sources/CoreRenderMetal/Shaders/StyleShader.swift`, `Sources/CoreRender/RenderOp.swift`, `Tests/CoreRenderMetalTests/MetalStyleTests.swift`, `Tests/CoreRenderMetalTests/MetalStyleParityTests.swift`, `Sources/CoreRender/Parity/ParityTolerance.swift` | LE-8 | ~380, 6 |
| LE-10 | – | KJ-LE walk; `StyleBudgetTests` (release, `.serialized`) | `Tests/CoreRenderTests/StyleWalkTests.swift`, `Tests/CoreRasterTests/StyleBudgetTests.swift` | LE-7, LE-9 | ~200, 2 |
| LE-11 | – | The `image-ops` and `corerendermetal` part descriptions; this packet's status line; `feature-done` | `docs/c4/parts/creative-core/coreraster/image-ops.json`, `docs/c4/parts/creative-core/corerendermetal/metal-backend.json`, `docs/blueprints/core/features/layer-style-engine.md` | LE-10 | ~20, 3 |

LE-7 edits the Metal shader, so its PR gets the `Metal (macOS)` check
(`metal-pr.yml`), and so do LE-8 and LE-9. LE-2's `LayeredImage` edit is two
stored fields with defaults, so no reader or writer changes until LE-6.

## Build waves

- Wave 1: LE-1, LE-2. Independent in this wave: both.
- Wave 2: LE-3. Independent in this wave: LE-3 alone.
- Wave 3: LE-4. Independent in this wave: LE-4 alone.
- Wave 4: LE-5, LE-6. Independent in this wave: both.
- Wave 5: LE-7, LE-8. Independent in this wave: both.
- Wave 6: LE-9. Independent in this wave: LE-9 alone.
- Wave 7: LE-10. Independent in this wave: LE-10 alone.
- Wave 8: LE-11 (`feature-done`, final). Independent in this wave: LE-11 alone.

Longest chain: LE-1 → LE-3 → LE-4 → LE-5 → LE-8 → LE-9 → LE-10 → LE-11 (8).
Chain of 8: the compositor draws the bevel, the CPU backend wraps the
compositor and renders the goldens Metal is checked against, the Metal style
kernels need the distance and blur kernels, the walk and budgets time both,
LE-11 is the status task.

## Acceptance test per task

| id | test | fails when | mutations (plan: label → filter) |
|---|---|---|---|
| LE-1 | builds on Linux and macOS; `RenderDispatcherTests.everyFamilyIsOn` with `style` on the CPU; a `StrokePosition` round-trips JSON as `"outside"` | a switch misses `style` or Metal claims it | – (seam) |
| LE-2 | suites compile, disabled; every PSD and ORA test unchanged (the fields default to nil and empty) | a codec changes output | – (checks) |
| LE-3 | `BevelTests`: on a disc lit from 0° the brightest highlight pixel is on the +x edge and the darkest shadow on the −x edge; `up: false` swaps them; altitude 90 gives no shadow; size 0 is identity; outer bevel paints only outside the alpha within `size`; soften 4 lowers the highlight peak | the light comes from the wrong side or leaks off the edge | `CoreRaster.Bevel`: y sign flipped in the light → `BevelTests.lightFromBelowAtNinety`; `up` ignored → `.downSwapsLight`; height not clamped at `size` → `.flatPastSize` |
| LE-4 | `StyleCompositeTests`: a disabled entry is identity; fill opacity 0 leaves the drop shadow and removes the layer; a Multiply shadow over white is darker than Normal at the same opacity; paint order puts an inside stroke over a colour overlay; spread 1 gives a hard shadow edge; `reach` of a 6,6 shadow with blur 12 is 21; every op at zero strength is identity | an entry is drawn in the wrong order, mode or place | `CoreRaster.StyleComposite`: entries drawn in list order → `.paintOrderFixed`; fill opacity applied to effects → `.fillOpacityOnlyTheLayer`; overlay not clipped to alpha → `.overlayStaysInside` |
| LE-5 | `CPUStyleTests`: the CPU backend's `styled` `==` the direct call for every op; `CPUGoldenTests` zero delta on the style goldens | a case maps wrong | `CoreRenderCPUStyle`: `fillOpacity` dropped → `CPUStyleTests.fillOpacityKept` |
| LE-6 | `PSDEffectsTests`: a test-written `lfx2` with a stroke and a drop shadow reads to their entries (mode, opacity, angle with global light, distance, size); `masterFXSwitch` off gives every entry disabled; satin and a second drop shadow are notes; an `lfx2` of zeros notes "unreadable" and opens the layer; a file without effects reads byte-for-byte as before | an effect is lost, a field is misread, or a drop is silent | `CoreRaster.PSDEffects`: global angle ignored → `.usesGlobalLight`; `Opct` read as 0...1 → `.opacityIsPercent`; second instance kept → `.multiNoted` |
| LE-7 | `BlendModeTests`: linear dodge of 0.6 over 0.6 is 1, linear burn 0.2 over 0.2 is 0; `lddg` and `lbrn` read as themselves; an unknown key notes its name; `MetalBlendTests` parity for both | a mode clamps wrong or opens as Normal | `CoreRaster.BlendMode`: burn without the −1 → `BlendModeTests.linearBurnFloor`; `lbrn` mapped to dodge → `.keysMapApart` |
| LE-8 | `MetalDistanceTests`: the jump-flood field is within 1 px of `DistanceField` everywhere on the fixtures; the Metal box blur within 1 level of `boxBlurred` | the field or blur drifts | none: kernels (the parity test is the check) |
| LE-9 | `MetalStyleTests`: a step re-encodes only the light and blend kernels when the alpha is unchanged; `MetalStyleParityTests`: every op within the `style` tolerance (2 levels; edge pixels within 8 on at most 0.5% of pixels) | a kernel drifts or the field recomputes every step | none: kernels |
| LE-10 | `StyleWalkTests.walk`; `StyleBudgetTests`: the walk's stack on a 2,000 × 2,000 layer ≤ 250 ms on the CPU and ≤ 16 ms p95 per step on Metal (release, reported) | the walk's checks fail | none |
| LE-11 | status line says built; `scripts/c4-assemble --check` | – | – |

## Quality tests

| quality row | budget | test |
|---|---|---|
| Style stack on a 4 MP layer, CPU | ≤ 250 ms (release) | `StyleBudgetTests.cpuStack` (reported) |
| One style step on Metal, resident | ≤ 16 ms p95, field cached | `StyleBudgetTests.metalStep` (reported, Mac) |
| CPU equals Metal | within the `style` tolerance on every fixture | `MetalStyleParityTests` |
| Identity at zero | every op at zero strength or disabled `==` identity | `StyleCompositeTests` |
| Never crashes | NaN, infinite and over-cap parameters throw; 200 seeded stacks; a truncated `lfx2` notes, never throws | `StyleCompositeTests.fuzz`, `PSDEffectsTests.fuzz` |

## Done check

Per slice as usual; LE-metal and LE-z's Metal budget on the Mac
(`Mac-Finish-Wanted: LE-metal`). Then the contact sheet with the walk on both
backends and the two budget numbers. Each slice's last merge is followed by a
`scripts/bump-core` PR in creative-apps (supervisor) so the waiting
`suiteui/layer-styles` and `photo/psd-effects` tasks can start.

## Not in this packet

Satin, pattern overlay, contours and textures for bevels, several instances of
one effect, writing effects to PSD, the `effect` family's own Metal port
(R2), `lrFX`.
