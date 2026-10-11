# FlareCore v0.1 gaps

The ranked work list for FlareCore v0.1. Each item is one behavior, sized for
one agent in under an hour, and lands as one small PR with a test. Items are
grouped by area and ordered by dependency and value; lower numbers first unless
an item says otherwise. G1 to G20 are also open GitHub issues labelled `gap`.

Size: **S** is about 30 minutes, **M** is about an hour. Priority: **p1** first,
then **p2**, then **p3**.

Rules that apply to every item (details in CLAUDE.md): the change is a command
if it edits a document, it never crashes on bad input, it stays Linux-safe, and
new model fields must still decode from v1 files that lack them.

## Foundations

### G1: Command registry decodes any command by id
- Priority p1, size M. Depends on nothing.
- Behavior: a `CommandRegistry` maps `Command.id` to a decoder, so a JSON envelope `{"id": "keyframe.move", "params": {...}}` decodes to `any Command`, and any command encodes to that envelope. All built-in commands are registered by default.
- Acceptance test: every built-in command encodes to the envelope and decodes back to an equal-behaving command (execute both on the fixture document, compare results). An unknown id throws `CommandError.unknownCommand(id)`. Malformed params throw, never crash.
- Files: new `Sources/FlareCore/CommandRegistry.swift`, `Command.swift` (error case), new test file.

### G2: Scene canvas size and background
- Priority p1, size S. Depends on nothing.
- Behavior: `Scene` gains `width`, `height` (Double, default 550 x 400) and `background` (`Color`, default white). v1 files without these fields decode with the defaults. `validate` rejects non-positive or non-finite sizes.
- Acceptance test: decode a v1 file that lacks the fields and get the defaults; round trip stays byte-stable; width 0 throws `FormatError.invalid`.
- Files: `Document.swift`, `FlareFormat.swift`, tests.

### G3: Scene commands
- Priority p1, size M. Depends on nothing.
- Behavior: `AddScene`, `RemoveScene` and `SetSceneTiming(fps:durationFrames:)` commands. Duplicate scene ids, fps <= 0 and negative durations throw. Undo restores exactly, including scene order.
- Acceptance test: each command's undo returns the original document; invalid params throw and leave the document unchanged. Add the three commands to the undo property test's random steps.
- Files: new `Sources/FlareCore/SceneCommands.swift`, `UndoPropertyTests.swift`, new test file.

### G4: Reorder layers
- Priority p1, size S. Depends on nothing.
- Behavior: `ReorderLayer(sceneID:layerID:toIndex:)` moves a layer within its scene. Out-of-range index throws `CommandError.invalidIndex`.
- Acceptance test: move first to last and back; undo restores order; out-of-range throws without changes. Add to the undo property test.
- Files: new `Sources/FlareCore/LayerCommands.swift`, tests.

### G5: Layer visibility and lock
- Priority p2, size M. Depends on nothing.
- Behavior: `Layer` gains `isVisible` (default true) and `isLocked` (default false), decoded with defaults from v1 files. `SetLayerFlags` command changes them. Commands that edit a locked layer's content (keyframes, shapes) throw `CommandError.layerLocked`.
- Acceptance test: old file decodes with defaults; locking then `SetKeyframe` throws; unlock and it works; undo of `SetLayerFlags` restores.
- Files: `Document.swift`, `Commands.swift` (lock check in `withLayer` callers), tests.

### G6: Undo depth limit
- Priority p2, size S. Depends on nothing.
- Behavior: `CommandEngine(document:maxUndoDepth:)`, default 500. When the undo stack is full, the oldest entry is dropped.
- Acceptance test: depth 3, perform 5 commands, exactly 3 undos succeed and the 4th throws `nothingToUndo`; document after 3 undos equals the state after command 2.
- Files: `Command.swift`, tests.

### G7: Coalesced undo for drags
- Priority p2, size M. Depends on nothing.
- Behavior: `perform(_:coalesceKey:)`: consecutive commands with the same non-nil key merge into one undo entry (a 60-step drag undoes in one step). A different key, a nil key, an undo or a group ends coalescing.
- Acceptance test: 10 `MoveKeyframe` steps with one key make one undo entry, and one undo returns the original document; a different key starts a new entry.
- Files: `Command.swift`, tests.

## Timeline and tweening

### G8: Hold easing
- Priority p1, size S. Depends on nothing.
- Behavior: `Easing.hold` keeps the keyframe's value until the next keyframe, then jumps.
- Acceptance test: track 0 -> 10 with hold, value at frame 9.99 is 0, at 10 is 10; Codable round trip.
- Files: `Easing.swift`, `Timeline.swift`, tests.

### G9: Change a keyframe's easing
- Priority p1, size S. Depends on nothing.
- Behavior: `SetKeyframeEasing(sceneID:layerID:property:frame:easing:)`. Missing keyframe throws `keyframeNotFound`.
- Acceptance test: set, undo, redo; missing keyframe throws without changes. Add to the undo property test.
- Files: new `Sources/FlareCore/KeyframeCommands.swift`, tests.

### G10: Sample a layer at a frame
- Priority p1, size S. Depends on nothing.
- Behavior: `Layer.sample(at frame: Double) -> [String: Double]` returns every track's value, plus defaults for the standard properties that have no track: x 0, y 0, scaleX 1, scaleY 1, rotation 0, opacity 1. Opacity is clamped to 0...1.
- Acceptance test: fixture ball layer at frames 0, 12 and 24; empty layer returns the defaults; opacity track at 1.5 samples as 1.
- Files: new `Sources/FlareCore/Sampling.swift`, tests.

### G11: Transform and affine matrix
- Priority p1, size M. Depends on nothing.
- Behavior: `Transform` (x, y, scaleX, scaleY, rotation in degrees) and a 2D affine `Matrix` with identity, multiply, apply to `Point`, and `inverted() throws` (singular matrix throws). `Transform.matrix` composes translate * rotate * scale.
- Acceptance test: known values (rotate 90 maps (1,0) to (0,1) within 1e-12); `m * m.inverted()` is identity within 1e-9 for random seeded transforms; scale 0 inversion throws.
- Files: new `Sources/FlareCore/Geometry.swift`, tests.

### G12: Playback frame mapping
- Priority p2, size S. Depends on nothing.
- Behavior: `Timeline.playbackFrame(elapsed:fps:durationFrames:loop:)` maps elapsed seconds to a frame: loop wraps, play-once clamps to the last frame. Duration 0 returns 0. Invalid fps throws.
- Acceptance test: 24 fps, 48 frames: 2.5 s loops to frame 12, play-once gives 47; negative elapsed gives 0.
- Files: `Timeline.swift`, tests.

### G13: Shift keyframes in a range
- Priority p2, size M. Depends on nothing.
- Behavior: `ShiftKeyframes(sceneID:layerID:fromFrame:toFrame:delta:)` moves every keyframe in the inclusive range on every track of the layer by `delta`. Throws if any result is negative or collides with a keyframe outside the range.
- Acceptance test: shift by +5 and undo; collision throws without changes. Add to the undo property test.
- Files: `KeyframeCommands.swift` (create if G9 has not landed), tests.

## Symbols and instances

### G14: Symbol definitions
- Priority p1, size M. Depends on nothing.
- Behavior: `Document.symbols: [Symbol]`, where a `Symbol` has `id`, `name`, `durationFrames` and its own `layers`. Missing in v1 files means empty. `validate` rejects duplicate symbol ids and symbol layer problems, like scene layers.
- Acceptance test: old file decodes with no symbols; a document with symbols round-trips byte-stable; duplicate symbol id throws.
- Files: `Document.swift`, `FlareFormat.swift`, tests.

### G15: Instances on layers
- Priority p2, size M. Depends on G11, G14.
- Behavior: `Layer.instances: [Instance]` (default empty), where an `Instance` has `symbolID`, a `Transform`, `firstFrame` and a `loop` mode (`loop`, `playOnce`, `singleFrame`). `validate` rejects instances of unknown symbols.
- Acceptance test: round trip; unknown symbol id throws `FormatError.invalid`.
- Files: `Document.swift`, `FlareFormat.swift`, tests.

### G16: Instance local frame
- Priority p2, size S. Depends on G15.
- Behavior: `Instance.localFrame(parentFrame:symbolDuration:)` returns the symbol frame to show: loop wraps, play-once clamps, single-frame always returns `firstFrame`.
- Acceptance test: table of parent frames for each mode, including symbol duration 0 and 1.
- Files: `Sources/FlareCore/Symbols.swift` (new), tests.

### G17: Symbol cycle detection
- Priority p2, size M. Depends on G15.
- Behavior: a symbol that contains an instance of itself, directly or through other symbols, is rejected by `validate` with `FormatError.invalid("symbol cycle ...")`.
- Acceptance test: A contains A throws; A contains B contains A throws; a diamond (A uses B and C, both use D) passes. Deep chains of 10k symbols do not overflow the stack (iterative walk).
- Files: `FlareFormat.swift` or `Symbols.swift`, tests.

### G18: Add and remove symbols
- Priority p2, size S. Depends on G14 (G15 for the in-use check).
- Behavior: `AddSymbol` and `RemoveSymbol` commands. Removing a symbol that an instance still uses throws `CommandError.symbolInUse`.
- Acceptance test: add, undo, redo; removing an in-use symbol throws without changes.
- Files: new `Sources/FlareCore/SymbolCommands.swift`, tests.

### G19: Convert layers to a symbol
- Priority p2, size M. Depends on G15, G18.
- Behavior: `ConvertToSymbol(sceneID:layerIDs:symbolID:name:)` moves the given layers into a new symbol and puts one layer with an instance of it in their place. One undo restores the original document.
- Acceptance test: convert two fixture layers, check structure, undo equals original; unknown layer id throws without changes.
- Files: `SymbolCommands.swift`, tests.

## Shapes and paths

### G20: Path type with curves
- Priority p1, size M. Depends on nothing.
- Behavior: `Path` with elements `move`, `line`, `quad`, `cubic` and `close`, and `Shape.path: Path?`. When `path` is set it wins over `points`. Old shapes decode unchanged.
- Acceptance test: Codable round trip of every element kind; v1 shape with only points still decodes; byte-stable round trip.
- Files: new `Sources/FlareCore/Path.swift`, `Document.swift`, tests.

### G21: Shape bounds
- Priority p2, size M. Depends on G20.
- Behavior: `Shape.bounds -> Rect?` is the tight axis-aligned box, including cubic and quadratic extrema (not just control points). Empty shape returns nil.
- Acceptance test: a cubic whose control points stick out has bounds tighter than its control box, checked against a densely sampled curve within 1e-9.
- Files: `Path.swift`, `Geometry.swift`, tests.

### G22: Stroke style
- Priority p3, size S. Depends on nothing.
- Behavior: `Shape.stroke: Stroke?` with color, width, join (miter, round, bevel) and cap (butt, round, square). Negative or non-finite width is rejected by `validate`.
- Acceptance test: round trip; old shape decodes with nil stroke; width -1 throws.
- Files: `Document.swift`, `FlareFormat.swift`, tests.

### G23: Hit testing
- Priority p3, size M. Depends on nothing (uses `Path` if G20 has landed).
- Behavior: `Shape.contains(_ point: Point, rule: FillRule)` for closed shapes with even-odd and nonzero rules. Open shapes contain nothing.
- Acceptance test: square, concave L shape, self-intersecting star under both rules; points on a vertex do not crash.
- Files: new `Sources/FlareCore/HitTest.swift`, tests.

### G24: Path flattening
- Priority p3, size M. Depends on G20.
- Behavior: `Path.flattened(tolerance:) -> [[Point]]` turns curves into polylines whose max distance from the true curve is within `tolerance`. Tolerance <= 0 or non-finite throws.
- Acceptance test: seeded random cubics, every flattened segment midpoint is within tolerance of the curve; point count grows as tolerance shrinks.
- Files: `Path.swift`, tests.

### G25: Shape edit commands
- Priority p2, size M. Depends on nothing.
- Behavior: `RemoveShape`, `SetShapeFill` and `TranslateShape(dx:dy:)` commands, addressed by layer and shape index. Bad index throws `shapeNotFound`.
- Acceptance test: each command's undo restores; bad index throws without changes. Add to the undo property test.
- Files: new `Sources/FlareCore/ShapeCommands.swift`, tests.

### G26: Gradient fills
- Priority p3, size M. Depends on nothing.
- Behavior: `Fill` enum (`solid(Color)`, `linear(stops, start, end)`, `radial(stops, center, radius)`). A v1 shape whose `fill` is a plain color still decodes as `solid`. Stops must be sorted with offsets in 0...1.
- Acceptance test: old file decodes; gradient round trip; unsorted stops throw.
- Files: `Document.swift`, `FlareFormat.swift`, tests.

## Interactivity (state machines)

### G27: State machine model
- Priority p2, size M. Depends on nothing.
- Behavior: `Document.stateMachines` (default empty). A `StateMachine` has `id`, `states` (id, name, scene id, frame range), `transitions` (from, to, trigger) and `initialState`. `validate` rejects references to unknown states or scenes and frame ranges outside the scene.
- Acceptance test: round trip; each kind of bad reference throws `FormatError.invalid`.
- Files: new `Sources/FlareCore/StateMachine.swift`, `FlareFormat.swift`, tests.

### G28: State machine step
- Priority p2, size S. Depends on G27.
- Behavior: pure `StateMachine.next(from:trigger:) -> String` returns the next state id. Unknown triggers keep the current state. When several transitions match, the first in declaration order wins.
- Acceptance test: a three-state button (idle, hover, pressed) driven through a trigger script; unknown trigger is a no-op.
- Files: `StateMachine.swift`, tests.

### G29: Inputs and conditions
- Priority p3, size M. Depends on G28.
- Behavior: state machines declare inputs (bool or number with defaults); transitions may carry conditions (`input == value`, `<`, `>`). `next` takes the current input values. Unknown inputs in conditions are rejected by `validate`.
- Acceptance test: a transition fires only when its condition holds; validation catches an unknown input name.
- Files: `StateMachine.swift`, tests.

### G30: Frame labels
- Priority p3, size S. Depends on nothing.
- Behavior: `Scene.labels: [String: Int]` (default empty) names frames. `SetFrameLabel` and `RemoveFrameLabel` commands. Label frames must be within the scene duration.
- Acceptance test: add, undo, redo; label past duration throws; old file decodes with no labels.
- Files: `Document.swift`, new `Sources/FlareCore/LabelCommands.swift`, tests.

## Format

### G31: Golden file test
- Priority p2, size S. Depends on nothing.
- Behavior: a checked-in `Tests/FlareCoreTests/Fixtures/basic.flare` that `FlareFormat.encode(Fixtures.document())` must match byte for byte, on Linux and macOS. This catches encoder differences between platforms.
- Acceptance test: the golden comparison itself, plus decoding the golden file gives the fixture document. Uses `Bundle.module` resources only if that works on Linux; otherwise embed the expected text in the test.
- Files: new test file (and fixture). Note: a resource needs a `Package.swift` change, which the fast lane will not merge; prefer the embedded string.

### G32: Document metadata
- Priority p3, size S. Depends on nothing.
- Behavior: `Document.metadata` (title, author, generator string; all optional) plus a `SetMetadata` command.
- Acceptance test: old file decodes with empty metadata; round trip; undo of `SetMetadata`.
- Files: `Document.swift`, new command file, tests.

## Export

### G33: SVG frame export
- Priority p2, size M. Depends on G2, G10, G11.
- Behavior: `SVGExporter.export(scene:frame:) throws -> String` renders visible layers bottom to top as `<path>` elements with fills, applying each layer's sampled transform. Canvas size from the scene.
- Acceptance test: exact expected SVG string for a one-square scene at two frames (the square moves).
- Files: new `Sources/FlareCore/Export/SVGExporter.swift`, tests.

### G34: SVG escaping and number safety
- Priority p2, size S. Depends on G33.
- Behavior: layer names and ids are XML-escaped in the output; non-finite coordinates throw instead of writing `nan`; numbers print without exponent notation.
- Acceptance test: a layer named `<a & "b">` exports escaped; a NaN point throws.
- Files: `SVGExporter.swift`, tests.

### G35: Lottie export, static subset
- Priority p3, size M. Depends on G2.
- Behavior: `LottieExporter.export(scene:) throws -> Data` writes a Lottie JSON subset from the public format docs: top level `v`, `fr`, `ip`, `op`, `w`, `h`, and one shape layer per Flare layer with its fills. Output uses sorted keys.
- Acceptance test: decode the output with `JSONSerialization` and check the top-level fields and layer count for the fixture; byte-stable across two exports.
- Files: new `Sources/FlareCore/Export/LottieExporter.swift`, tests.

### G36: Lottie animated position and easing
- Priority p3, size M. Depends on G35, G8.
- Behavior: x/y tracks export as animated position keyframes; cubic-bezier easing maps to Lottie `o`/`i` tangents, hold maps to `h: 1`, linear maps to straight tangents.
- Acceptance test: fixture ball's ease-in-out keyframe exports with `o` = (0.42, 0) and `i` = (0.58, 1).
- Files: `LottieExporter.swift`, tests.

## Robustness

### G37: Decoder size limits
- Priority p2, size S. Depends on nothing.
- Behavior: `FlareFormat.decode` rejects input over 64 MB before parsing, and documents with more than 10,000 layers per scene or 1,000,000 points in total, with `FormatError.tooLarge`.
- Acceptance test: oversize data throws `tooLarge` quickly; a document at the limits still decodes.
- Files: `FlareFormat.swift`, tests.

### G38: Command fuzz
- Priority p2, size M. Depends on G1.
- Behavior: a seeded fuzz test that builds random command envelopes (valid ids, random and corrupted params), decodes them through the registry and performs them on random documents. Nothing crashes; every failure is a typed error; the document is unchanged after any throw.
- Acceptance test: the fuzz test itself, 5,000 iterations under 5 seconds.
- Files: new test file only.

## Performance

### G39: Binary search when sampling
- Priority p3, size S. Depends on nothing.
- Behavior: `Timeline.value(of:at:)` finds the segment by binary search instead of a linear scan.
- Acceptance test: seeded random sorted tracks of 1 to 1,000 keyframes give identical results to the old linear scan (keep it as a test oracle).
- Files: `Timeline.swift`, tests.

### G40: Engine stress budget
- Priority p3, size M. Depends on nothing.
- Behavior: `CommandEngine` stays fast on big documents. The engine runs each command on a copy of the document (copy-on-write, so the cost is the touched arrays, not a deep copy); confirm that holds and fix any command that copies more than it touches.
- Acceptance test: on a seeded document with 10,000 layers, 1,000 random commands plus undo-all finish within 5 seconds in a debug build on CI, and the result equals the original document.
- Files: new test file; `Command.swift` or `Commands.swift` only if the budget fails.
