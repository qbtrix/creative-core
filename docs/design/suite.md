<!-- Creative suite design: repo topology, Linux/macOS split, interop, AI layer, testing, Belt changes, per-app gaps and the phased plan for Flare, Design, Photo, Library and Halo. -->
# Creative suite design (Flare, Design, Photo, Library, Halo)

**Date:** 2026-10-12 · **Status:** draft for maintainer review · **Builds on:** [swarm-pilot-1.md](swarm-pilot-1.md), [`docs/engineering.md`](../engineering.md), [`docs/review-rubric.md`](../review-rubric.md), [`docs/gaps.md`](../gaps.md)

## Goal

A free, open-source, Swift-native creative suite for the Mac. It's AI-native from day one, the apps work together the way Apple's apps do, and it's hand-polished to the macOS 26 HIG with Liquid Glass. The first five apps:

- Flare: 2D animation
- Design: vector and UI design
- Photo: raster editing
- Library: catalog and develop
- Halo: motion graphics

Prism (3D) comes later. Belt plus Claude Code cloud sessions build it.

The design follows one constraint: **cloud workers are Ubuntu VMs and can't build SwiftUI.** So almost all of the code has to be pure Swift that builds and tests on Linux. The Mac-only part has to stay thin enough that writing it blind against macOS CI is workable.

## 1. Repo topology

```
qbtrix/creative-core        (shared engines, Linux + macOS, GPL-3.0)
  CoreDocument   Command, CommandEngine, CommandRegistry, envelope, journal, Asset model, format helpers
  CoreGeometry   Matrix, Transform, Path, bounds, hit test, flattening, fills, strokes
  CoreTimeline   Easing, keyframe tracks, sampling, playback mapping
  CoreColor      color spaces (sRGB, linear, Display P3, XYZ, OKLab), swatches
  CoreRaster     PixelBuffer, blend modes, filters, masks, resample, histogram, tiles
  CoreCatalog    metadata schema + queries over SQLite (GRDB)
  CoreExport     SVG and Lottie writers
  FlareCore      today's animation model (scenes, symbols, state machines), on top of the above

qbtrix/flare  qbtrix/design  qbtrix/photo  qbtrix/library  qbtrix/halo   (one repo per app)
  Package.swift   <App>Core      Linux-safe, app-only model and commands (Flare reuses FlareCore)
                  <App>Platform  macOS-only adapters (ImageIO, Core Image/Metal, PhotoKit, Foundation Models)
  project.yml     XcodeGen spec for the SwiftUI app + UITests target (no hand-edited .pbxproj)
  App/            the SwiftUI shell: views, scenes, menus, toolbar. No logic.
  UITests/        XCUITest journeys, one file per feature
```

Rules:

- **A module goes in creative-core only when two or more apps import it.** Otherwise it lives in the app repo as `<App>Core`. FlareCore stays in creative-core for Phase 0. It moves to the flare repo only if nothing else imports it by Phase 2. Subtract first, move later.
- **Module boundaries are SwiftPM targets.** The compiler enforces them, which is the mechanical check the charter asks for. Each core keeps one error type, as `docs/engineering.md` says.
- **Every core keeps the creative-core rules:** Foundation only (via `FoundationEssentials`), Swift 6 mode, value types, no crashes on untrusted input, every edit is a `Command`.
- **Versioning.** creative-core gets semver tags, with minor bumps for breaking changes while it's pre-1.0. App repos pin `exact:` versions. Dependabot's Swift ecosystem opens the bump PRs, and app CI proves them. For a change that spans core and app, the worker lands the core PR and tags it first, then opens the app PR. No cross-repo atomic changes. Locally, `swift package edit` covers iteration.

## 2. The Linux/macOS split

```
              builds on        verified by                        cloud worker can
  Core*       Linux + macOS    swift test, property/fuzz, golden  build, test, ship alone
  <App>Core   Linux + macOS    swift test, property/fuzz          build, test, ship alone
  <App>Plat.  macOS only       unit tests on xcode-27 runner      write blind, iterate on CI
  App shell   macOS only       xcodebuild, XCUITest, screenshots  write blind, iterate on CI
  Taste       n/a              maintainer                            nothing
```

- **Engines carry the logic.** Anything that can be a pure function or a command over a value-type document goes in a Linux-safe target. That includes layout math, compositing, color, catalog queries, export bytes and command catalogs.
- **Platform adapters are narrow.** Codecs go through ImageIO. GPU rendering uses Core Image and Metal, and text shaping uses Core Text. PhotoKit reads the Photos library, and Foundation Models runs the on-device model. Each adapter implements a protocol declared in a Linux-safe target, so the core tests it against a fake. Example: auto layout takes a `TextMeasurer` protocol, macOS backs it with Core Text, and tests use a fixed-width fake.
- **CPU reference renderer = the oracle.** CoreRaster's compositor runs on Linux. The Metal renderer in `<App>Platform` gets snapshot-compared against it on macOS CI within a tolerance. Then a GPU bug shows up as a failing diff, not a taste call.
- **Shells are thin.** A view reads document state and calls `engine.perform(command)`. Nothing else mutates the document. The rubric checks this, and a grep in `scripts/ci` fails on document assignment outside the engine.
- **macOS CI per app repo.** Two jobs. `linux` runs `scripts/ci` in `swift:6.3.3-noble`, the same as creative-core. `macos` runs on GitHub's `xcode-27` image (Xcode 27, the same Xcode as the team's Macs), because Liquid Glass and Foundation Models need the macOS 26 SDK or later. creative-core uses the same image. The label comes from `vars.MACOS_RUNNER` when set, so a self-hosted Mac can replace it by changing one value. The `macos` job runs `xcodegen`, `xcodebuild build test` and the UITests, then uploads the `.xcresult`. Standard runners are free for public repos. Workers push, read the failed check log with `gh run view --log-failed`, fix and push again.
- **What can't be verified anywhere but a human eye:** spacing, motion feel, glass legibility over real content, and whether a flow feels right. Those PRs never take the fast lane.

## 3. Interconnection (native first)

**Document types.** Each app exports one `UTType` in its Info.plist. A shared package type carries assets between apps:

```
org.<brand>.flare     .flare     conforms to public.data      (JSON, existing v1 format)
org.<brand>.design    .design    conforms to com.apple.package
org.<brand>.photo     .photo     conforms to com.apple.package (manifest + raw tiles)
org.<brand>.library   .library   conforms to com.apple.package (SQLite + previews)
org.<brand>.halo      .halo      conforms to com.apple.package
org.<brand>.asset     .asset     conforms to com.apple.package (manifest.json + payload)
```

**One asset model.** It lives in CoreDocument and is Linux-safe:

- `Asset {id: UUID, kind, name, tags, version, source app, payload ref}`
- kinds: vector, raster, animation, comp, swatch, palette, symbol, preset

Every app can import and export an `Asset`. A placed asset keeps `AssetRef(id, version)`, so "update to latest" is possible later without inventing live links now.

**Drag and drop, copy and paste.** Each asset kind conforms to `Transferable`:

- `CodableRepresentation(contentType: .asset)` handles suite-to-suite moves.
- `FileRepresentation` handles the package.
- `DataRepresentation(exportedContentType: .png)` (and `.svg`, or a `FileRepresentation` for MP4) exports for apps outside the suite.

Dragging a Design component into Flare moves an `Asset`. Dragging it into Mail moves a PNG. The Services menu and `NSItemProvider` come for free.

**Shared library.** An App Group container (`<team>.<brand>`) holds a CoreCatalog SQLite database plus asset blobs. Library is the full browser for it, and every other app gets a small Library panel. Each app reads the system Photos library through PhotoKit and never copies it. File edits round-trip through `NSFileCoordinator` and `NSFilePresenter`. Library's "Edit in Photo" opens the file with `NSWorkspace.open(_:withApplicationAt:)`, and Library sees the save.

**App Intents and Shortcuts.** Documents and assets become `AppEntity` types. A short hand-picked set of `AppIntent`s per app (open, export, apply preset, add to library) gives us Shortcuts, Spotlight and Siri with no extra code. Not every command becomes an intent; that's what the AI surface below is for.

Skipped for now: iCloud sync (CloudKit, later and paid), Handoff, live linked assets.

## 4. AI-native layer

**Commands are the action surface.** The `CommandRegistry` already decodes any command from a JSON envelope `{"id": "keyframe.move", "params": {...}}`, and every command has an exact undo. That's the whole agent API:

1. The model gets the command catalog as tools (S4 below adds a param schema per command).
2. The model returns envelopes. The registry decodes them, so an unknown id or bad params throws and never crashes.
3. The app runs them inside one command group. One Undo reverts the whole AI edit, and the journal (S5) records it.
4. Preview runs the group on a copy of the document first.

The same envelopes drive the CLI, tests, the control port and the human UI. We already have it.

**One provider protocol.** `ModelProvider` is declared in CoreDocument and is Linux-safe. It takes a prompt, tool specs and a document summary, and streams back envelopes. Three backends sit in `<App>Platform`, or in a shared macOS package once a second app needs them:

| Backend | How | Cost | Good for |
|---|---|---|---|
| On-device | Foundation Models `LanguageModelSession` with `Tool` conformances generated from the catalog | free, offline | short edits: rename, tag, "make it bounce", captions |
| User's subscription | spawn the local `claude -p --output-format stream-json` or `codex exec` with an MCP server the app exposes over the registry (tools: `list_commands`, `perform`, `read_document`, `render_preview`); detect the CLI on PATH and its login state for zero setup | user's plan | multi-step edits, generation |
| Our credits | the same tool loop through our model gateway | metered | users with no subscription |

Use the official MCP Swift SDK for the server. Check its Linux support before it goes in a core; otherwise it lives in the macOS target. Spawning CLIs needs a non-sandboxed app (see open question 1).

## 5. Human-like testing station

- **One XCUITest journey per feature** in `UITests/`, named after the feature. Every control gets an `accessibilityIdentifier`, which the accessibility pass needs anyway. Each journey attaches screenshots with `XCTAttachment(screenshot:)` in Light and Dark.
- **The control port is the first rung.** Debug builds expose the same MCP server on a local socket. A journey can set up state through commands, click the one thing under test, then read the document back. That's faster and less flaky than clicking everything.
- **Snapshot tests** for views use `swift-snapshot-testing` (pointfreeco) on the macOS job.
- **Feature map.** Reuse the `verify-<app>` skill pattern: `.claude/skills/verify-<app>/features/<feature>.md` maps each feature to its journey and the screenshots it expects. A feature without a map file isn't done.
- **Unverified: XCUITest on hosted runners.** We found only third-party claims that hosted macOS runners have an interactive session and that TCC won't block a plain XCUITest. Phase 0 runs a 15-minute spike: one journey that clicks one button on `macos-26`. If it's blocked, journeys drop to the control port plus screenshots, and a self-hosted Mac mini runner (GUI session, TCC granted once) becomes the escalation. That runner only takes non-fork PRs and Belt dispatches, never fork code.

What Belt needs to run them:

1. Treat the `macos` check as required.
2. Read the `.xcresult` summary (`xcrun xcresulttool`) from the CI artifact.
3. Attach the screenshots to the Instinct diff gate entry, so the maintainer judges taste from the gate without checking out the branch.

## 6. Belt changes (each is one small PR)

| # | Change | Hook (from the pilot) | Size |
|---|---|---|---|
| B1 | **Multi-repo.** `FACTORY_CLOUD_LAUNCH_DIR` becomes a mandate field, `launch_clone`, one per repo. The env var stays as the default. | `develop_station.py::wire_from_env`, `cloud_station.py` | S |
| B2 | **Trusted launch clones.** Fresh clones hang on the CLI's folder-trust prompt. Onboarding a repo makes its clone under `paw-worktrees/launch/<repo>`, and the maintainer trusts it once by hand. Same PR: keep the pty output on timeout, and add a retry endpoint for a failed run. | pty runner, runs API | S |
| B3 | **GitHub issues patrol.** Today's issues patrol only speaks GitLab, and the pilot fed sightings by hand. Add a GitHub variant: `gh issue list --label gap --state open --json`, deduped by issue URL. | patrols | S |
| B4 | **Plan-gate auto policy, rule first.** Auto-approve when every task cites an open `gap` issue, the plan is within the shift budget, and no task names a `says_no` path. Clef stays in shadow and keeps logging next to the supervisor. It gets a vote only after about 20 gate-log rows with no missed reject. The log has 2 rows today. | after `_belt_plan` propose in `mandates/service.py` | S |
| B5 | **Size-aware diff gate = read the lane.** The fast lane already enforces 400 lines, 15 files, protected paths and green checks. Belt maps lane-merged to landed. Lane-refused goes to the Instinct diff gate, tagged with a size class and the screenshots. Any PR touching `App/` always escalates. | cloud runner PR poll | S |
| B6 | **Lane kit.** Move `fast-lane.yml`, `fast-lane.sh` and the main guard to a reusable workflow (`workflow_call`) in creative-core. App repos call it instead of copying. Fix starvation in the same move (oldest PR first). | creative-core `.github/` | M |

The headless per-diff policy in `_attach_diff` (status step 6) stays parked. Cloud mode lands through the lane, so the lane is the diff gate.

## 7. Per app

The gap tables use the `docs/gaps.md` style compressed to one row each. The foreman expands each row into a full issue (priority, depends, behavior, acceptance, files) from the gaps.md template. Repo is creative-core (`cc`) or the app repo. Every row is Linux-buildable.

### Shared cores (land first, in creative-core)

| id | behavior | acceptance test | size |
|---|---|---|---|
| S2 | CoreColor: sRGB, linear, Display P3, XYZ and OKLab conversions | seeded round trips within 1e-6; known reference values | M |
| S3 | `Asset` and `AssetRef` model plus `manifest.json` codec with size limits | round trip; old manifest decodes; seeded fuzz throws, never crashes | M |
| S4 | Command catalog: `CommandRegistry.catalog()` returns id, summary and a JSON param schema per command | every registered command has a summary, and its sample envelope validates against its schema | M |
| S5 | Command journal: append-only JSONL of envelopes, plus replay | replaying a random 200-step journal yields the same document; a truncated last line is skipped | S |
| S6 | `PixelBuffer`: RGBA Float32 linear, bounds-checked, megapixel cap | dims fuzz throws; get/set round trip; cap exceeded throws | S |

S1 is the module split itself. It touches `Package.swift`, a protected path, so it's Phase 0 work by one supervised agent, reviewed by the maintainer, not a swarm issue.

### Flare: 2D animation

A successor to the classic 2D web animation tools. Draw, tween, add symbols and interactive state machines, then export to SVG and Lottie for the web. Mac-native and free.
**Modules:** CoreDocument, CoreGeometry, CoreTimeline, CoreExport, FlareCore.
**MVP:**
- canvas with pen, shape and select tools
- timeline with layers and keyframes
- motion tweens with easing
- onion skin
- symbols and instances
- state machine editor and preview
- playback
- SVG, Lottie and PNG-sequence export
- library panel
- AI: "animate this" through commands

| id | behavior | acceptance test | size |
|---|---|---|---|
| G45 | Render list: `Scene.renderList(at:)` flattens visible layers and nested instances into ordered draw items (path, fill, stroke, world matrix, opacity) | SVG exporter moved onto it stays byte-identical to the golden; hidden layers absent | M |
| G46 | Onion skin frames: `Layer.onionFrames(at:before:after:)` | at frame 10 with 2/2 gives [8,9,11,12], clamped to the scene | S |
| G47 | Copy and paste frames as an envelope clipboard payload | paste at an offset, undo exact, locked layer throws | M |
| G48 | Shape tween: interpolate two paths, resampling mismatched segment counts | t=0 equals A, t=1 equals B, empty path throws | M |
| G49 | Bones: bone hierarchy with rotation tracks and forward kinematics | two-bone chain at 90 degrees puts the tip at the expected point within 1e-9; a cycle throws | M |
| G50 | Audio track on a scene (asset ref, start frame, gain) | old file decodes with no audio; start < 0 fails `validate` | S |
| G51 | Scene assets use `Asset` from CoreDocument, plus an `ImportAsset` command | import, undo, round trip; depends on S3 | S |
| G52 | Lottie export of opacity, scale and rotation tracks | golden JSON per track | M |
| G53 | `ConvertSceneFPS(to:)` rescales keyframes with a stated rounding rule | 24 to 30 to 24 restores frames; undo exact | S |
| G54 | PNG-sequence export plan: frame list plus file names for a range and step | 0..48 step 2 gives 25 names with zero-padded indices | S |

### Design: vector and UI design

Frames, components and auto layout, like the tools designers already know, on a native canvas. It shares symbols and colors with every other app in the suite.
**Modules:** CoreDocument, CoreGeometry, CoreColor, CoreExport, DesignCore.
**MVP:**
- pages and frames
- shapes, paths and text
- select, move and resize with snapping
- constraints
- auto layout
- components with overrides
- color and number variables with light and dark modes
- inspector
- layers sidebar
- SVG and PNG export
- AI: "lay this out" through commands

| id | behavior | acceptance test | size |
|---|---|---|---|
| D1 | Node tree: document > page > node (frame, group, rect, ellipse, path, text, instance) with `validate` | round trip; a duplicate id throws | M |
| D2 | Node commands: add, remove, reparent, reorder | undo exact; reparenting into a descendant throws | M |
| D3 | Constraints: left, right, center and scale on parent resize | table of resize cases | S |
| D4 | Auto layout: direction, gap, padding, alignment, hug and fill | known layouts; zero children; nested stacks | M |
| D5 | Components and instances with overrides; a detach command | edit to the main component propagates; override survives; detach then undo | M |
| D6 | Variables with modes; nodes bind to variables | value resolves per mode; a missing variable throws | S |
| D7 | Text style model plus a `TextMeasurer` protocol used by auto-layout hug | fake fixed-width measurer gives the expected frame size | S |
| D8 | Snapping and guides: snapped offset plus guide lines within a threshold | edge, center and spacing cases | M |
| D9 | Point and marquee hit test over the node tree with transforms, skipping hidden and locked nodes | reuses CoreGeometry; seeded cases | S |
| D10 | Frame to SVG through CoreExport | golden SVG; unsupported node kind throws | M |

### Photo: raster editing

Layers, masks, adjustments and brushes in a fast native editor. Every edit is undoable. It opens straight from Library and returns to it.
**Modules:** CoreDocument, CoreColor, CoreRaster, PhotoCore.
**MVP:**
- open and save `.photo` plus PNG, JPEG and HEIC (ImageIO)
- layers with blend modes
- masks
- selection tools
- brush and eraser
- adjustment layers (levels, curves, hue/saturation)
- crop and resize
- blur and sharpen
- history
- Edit in Photo from Library
- AI: on-device "select subject" via Vision, a native API

| id | repo | behavior | acceptance test | size |
|---|---|---|---|---|
| P1 | cc | Blend modes per the W3C Compositing spec, premultiplied | table of known pixel results per mode | M |
| P2 | photo | Layer stack (pixel, adjustment, group) with opacity, blend, mask and visibility, composited to a buffer | multiply of two layers equals P1; hidden ignored | M |
| P3 | cc | Adjustments: exposure, levels, monotone-cubic curves, hue/saturation | identity params return the input exactly; the curve passes through its points | M |
| P4 | cc | Selection masks: rect, ellipse and polygon rasterized with antialiasing; add, subtract, intersect | area within 1%; ops on empty masks | M |
| P5 | cc | Tiles: buffer split into 256-pixel tiles, with a tile-diff undo | undo restores bytes exactly; only touched tiles are stored | M |
| P6 | photo | Brush dab engine: spacing, size, hardness, opacity along a path | dab count from spacing; hardness 1 gives a crisp edge | M |
| P7 | cc | Resample: bilinear and Lanczos3, crop, rotate 90 | a constant image stays constant; output dims | M |
| P8 | cc | Separable Gaussian blur and unsharp mask with edge clamp | a constant image is unchanged; impulse weights sum to 1 | S |
| P9 | photo | `.photo` package: manifest plus raw tile blobs, with decoder size limits | round trip; seeded fuzz throws, never crashes | M |
| P10 | photo | Paint and fill commands on a layer through tiles | undo property test steps added | S |

### Library: catalog and develop

Import, rate, keyword and find thousands of photos. Develop edits stay non-destructive, and any photo hands off to Photo. The shared asset library for the whole suite lives here.
**Modules:** CoreDocument, CoreColor, CoreRaster, CoreCatalog, LibraryCore.
**MVP:**
- import folders and the Photos library (PhotoKit)
- grid and loupe
- ratings, flags and color labels
- keywords
- collections and smart collections
- develop panel (exposure, white balance, contrast, highlights/shadows, crop)
- presets
- histogram
- XMP sidecars
- Edit in Photo
- AI: on-device auto-tagging and search

| id | repo | behavior | acceptance test | size |
|---|---|---|---|---|
| L1 | cc | CoreCatalog schema with migrations on GRDB (system SQLite; GRDB builds on Linux with Swift 6.2). Needs an approved-dependency issue first. | empty to v1 migration, in-memory DB on Linux | M |
| L2 | library | Import plan: add, skip duplicates by content hash, mark moved | decision table | S |
| L3 | library | Normalize an ImageIO-shaped metadata dictionary into a typed `PhotoMetadata` (date, camera, lens, ISO, orientation) | fixture dictionaries; missing and garbage keys never crash | S |
| L4 | cc | Smart collection rule tree compiled to SQL | matches an in-memory filter on seeded random catalogs | M |
| L5 | library | Rating, flag and label commands over a selection | undo exact; out-of-range rating throws | S |
| L6 | library | Develop settings: versioned, Codable, copy and paste a subset, presets | old record decodes; partial paste | S |
| L7 | library | Develop pipeline over CoreRaster ops in a fixed order | default settings are the identity; the order test holds | M |
| L8 | cc | Histogram per channel plus clipping counts | known counts on fixtures | S |
| L9 | library | Keyword hierarchy with synonyms, implying the parent on assign | assign child gives parent; a cycle throws | S |
| L10 | library | XMP sidecar writer for rating, label and keywords, XML-escaped | golden XMP; hostile keyword is escaped | S |

### Halo: motion graphics and compositing

Compositions, layers, parenting and effects on a timeline, with a GPU renderer checked against a CPU reference. Flare scenes and Design frames drop in as layers.
**Modules:** CoreDocument, CoreGeometry, CoreTimeline, CoreColor, CoreRaster, CoreExport, HaloCore.
**MVP:**
- compositions
- solid, image, shape, text, null and precomp layers
- parenting
- keyframes with a graph editor
- masks and track mattes
- 3 effects (blur, fill, levels)
- motion blur
- RAM preview
- export to ProRes and H.264 (AVFoundation)
- Flare scene as a layer
- AI: "animate in" presets through commands

| id | repo | behavior | acceptance test | size |
|---|---|---|---|---|
| H1 | halo | Composition model: size, fps, duration; layers with in/out points, parent, blend | round trip; out < in fails `validate` | M |
| H2 | halo | Parenting world transforms via CoreGeometry | known chain; a cycle throws | S |
| H3 | halo | Sample a comp at a time: every layer's transform and anchor point via CoreTimeline | fixture comp at 3 times | S |
| H4 | halo | Precomp time: stretch, start offset and a time-remap track | nested local times table | S |
| H5 | halo | Render graph: comp at a time gives ordered draw ops (buffer ref, matrix, opacity, blend, matte) | matches hand-built ops; layers outside in/out absent | M |
| H6 | cc | CPU reference compositor: draw ops into a `PixelBuffer` with affine bilinear sampling | identity draw is a copy; 2x scale dims and edges | M |
| H7 | halo | Effects stack model plus blur, fill and levels via CoreRaster | identity effect params are a no-op; order matters test | M |
| H8 | halo | Track mattes: alpha and luma, normal and inverted | known pixel table | S |
| H9 | halo | Motion blur sample times from shutter angle and phase | 180 degrees, 8 samples spans half a frame | S |
| H10 | halo | Flare scene as a precomp layer via FlareCore's render list | depends on G45; frame mapping table | M |

## 8. Phased plan

These numbers come from the pilot: 41 gaps in 3 h 17 min, workers taking 3 to 10 minutes per PR, about 18 merges an hour at peak, and about 1 merge per 3-minute CI cycle under the main guard.

```
Phase 0  split + scaffold + CI      ~8 agent-h    1 day wall-clock (maintainer review bound)
Phase 1  engine gaps, 5 repos       ~15 agent-h   1 evening to 1 night
Phase 2  app shells                 ~20 agent-h/app, 3-5 days wall-clock for all 5
Phase 3  interop + AI layer         ~25 agent-h   ~1 week wall-clock
```

**Phase 0.** These are supervised, not swarm work.

- S1 module split: one agent, about 2 h. It's a `Package.swift` change, so the maintainer reviews it.
- 5 app repos from one template: XcodeGen `project.yml`, the `<App>Core` and `<App>Platform` targets, `scripts/ci`, CLAUDE.md, engineering.md and rubric copied from creative-core, `macos-26` CI, `cloud-setup.sh`.
- The XCUITest spike (section 5).
- Belt B1 to B3.

Exit: every repo is green on Linux and macOS, one app window opens on CI, and the spike result is known.

**Phase 1.**

- File S2 to S6 and the 50 app rows as issues.
- Run 5 mandates in parallel, one per repo, with creative-core first because S3, S6 and P1 unblock others.
- Turn on B4 in shadow and B5 live.

At pilot rates the shared and Flare rows land in about 1 to 2 hours and the app repos run alongside. Wall-clock is bound by the lane's one merge slot per repo, not by workers.

**Phase 2.**

- Shells, app by app: Flare first, because its engine is furthest along.
- Each feature is one PR: the view, its journey, its feature map and screenshots.
- The slow part is honest. Every SwiftUI compile error is a 10 to 15 minute macOS CI round trip, since workers can't compile it locally. Taste review is the maintainer, in batches.
- Use the `apple-hig` skill for every shell PR. It's in git history and not merged yet (paw-workspace#290), so merge it first.

**Phase 3.**

- UTTypes and `Transferable`
- the App Group library
- App Intents
- the `ModelProvider` with its three backends
- the MCP server over the registry
- journeys that cross apps (drag Design into Flare, Edit in Photo from Library)

**Risks.**

- **Usage limits.** Cloud sessions share the subscription plan's 5-hour and weekly limits. Cloud adds machines, not tokens. Measure with `/usage` after Phase 1 before scaling Phase 2.
- **macOS CI concurrency.** Standard runners are free on public repos, but an org gets only a handful of concurrent macOS jobs (about 5 on Free and Team; check the current limit). Five app repos share that pool, so shell PRs will queue. Keep journeys short and cancel superseded runs.
- **Xcode drift.** CI runs the `xcode-27` image, whose only Xcode is 27, so CI matches the team's Macs. When the image gains a second Xcode, pin it with `xcode-select`. The floor is Swift 6.1, set by GRDB (L1): 7.10.0 is the first GRDB release that links against Ubuntu's SQLite, and it needs tools 6.1.
- **Hosted XCUITest may be blocked by TCC.** The fallback is the control port plus a self-hosted Mac mini.
- **SwiftUI polish needs a human eye.** No gate catches spacing or motion feel. Budget maintainer review time, not agent time. It's the real bottleneck in Phase 2.
- **CPU raster speed.** The Linux reference compositor is the oracle, not the product path. Interactive rendering is Metal in `<App>Platform`, so it has the slowest feedback loop.
- **Clean-room and trademarks.** Behavior comes only from public docs and specs (W3C Compositing, Lottie, XMP). No product names in code or UI.

## 9. Open questions for the maintainer

1. **Distribution.** GPL-3.0 and the Mac App Store don't mix well, and the App Sandbox can't spawn `claude` or `codex`. Proposal: a notarized direct download with Sparkle updates, and no App Store. Confirm?
2. **Subscriptions.** Are Anthropic's and OpenAI's terms OK with a third-party app driving a user's own CLI login? This is still unchecked. Until it is, the subscription backend ships behind a setting, and on-device plus credits are the defaults.
3. **Brand and identifiers.** UTType and bundle IDs (`org.<brand>.*`) are painful to change after release, and "Afterglow", "Flare" and "Halo" all have known collisions. Pick the org name before Phase 0 scaffolds the repos?
4. **Core license.** Should the cores stay GPL-3.0, or move to LGPL or Apache so marketplace plugins can link them? Decide before the first outside contribution.
5. **macOS floor.** Should we require macOS 26 only? That gets us Liquid Glass and Foundation Models with no fallbacks. Also, may we buy a Mac mini as the self-hosted UI-test runner if the spike fails?
