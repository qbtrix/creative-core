# FlareCore: agent instructions

FlareCore is the pure-Swift engine of Flare, a Mac-native 2D vector animation
studio ("Flare" is a working name). This repo holds only the engine: document
model, commands with undo, timeline, easing, file format and export. The Mac
app lives in another repo. Many agents work here at once; these rules keep
that safe and fast. AGENTS.md points here.

## Modules

- `Sources/FlareCore`: the animation engine (document, commands, timeline, format, export).
- `Sources/CoreColor`: color spaces and conversions, shared by every app. Depends on nothing.
- `Sources/CoreRaster`: pixel buffers, compositing and image operations. Depends only on CoreColor.
- `Sources/CoreAsset`: the shared asset model (`Asset`, `AssetRef`) and its manifest codec. Depends on nothing.
- `Sources/CoreCatalog`: the photo and metadata catalog over SQLite. Depends only on GRDB.
- `Sources/CoreRender`: the `RenderBackend` contract, the CPU backend, the dispatcher and the parity harness. Depends only on CoreRaster and CoreColor.
- `Sources/CoreRenderMetal`: the Metal `RenderBackend`, macOS only. Depends only on CoreRender. The one module allowed to import Metal.

Each module has one error type (`ColorError`, `RasterError`, `AssetError`,
`CatalogError`, `RenderError`, which CoreRenderMetal shares) and its own test target. A new shared module needs an issue
that approves it, because it edits `Package.swift`. FlareCore must not import
the other modules yet.

## Start here

1. If you were given an issue, do that issue.
2. Otherwise pick the highest-priority open issue labelled `gap` that is not
   labelled `in-progress` (`p1` before `p2` before `p3`, then the lowest G
   number). Add the `in-progress` label to it before you start:
   ```bash
   gh issue list --label gap --state open --json number,title,labels
   gh issue edit <n> --add-label in-progress
   ```
3. The full ranked list, with acceptance tests, is `docs/gaps.md`.

## The loop

1. **Orient.** Read this file, the issue, and the code it touches. Check the
   issue's "Depends on"; if a dependency has not merged, pick another issue.
2. **Branch from dev.** `git fetch origin && git switch -c <branch> origin/dev`.
   Never branch from or target `main`: it only takes `dev` SHAs that passed
   full CI.
3. **Implement with tests.** Write the test from the issue's acceptance test,
   then the code.
4. **Gate.** Run `scripts/ci`. It must print `CI: PASS`. It is your whole
   check: no CI runs on your PR, and you never start CI yourself for routine
   work (no `gh workflow run`). Full CI runs on `dev` once a feature is built.
5. **Ship.** `git fetch origin && git rebase origin/dev`, rerun `scripts/ci`
   (it must print `CI: PASS` again), push, then open ONE small PR to `dev`
   with `Closes #<n>`, the `fast-lane` label, and these two lines at the end
   of the body for the head you pushed:
   ```
   Fast-Check: pass
   Head: <full sha from git rev-parse HEAD>
   ```
   After every later push, rerun `scripts/ci` and update the `Head:` line to
   the new head; the lane ignores a marker for an older head. Then stop.
   ```bash
   # body.md: what and why, Closes #<n>, then the two lines for $(git rev-parse HEAD)
   gh pr create --base dev --label fast-lane --title "<type(scope): what>" --body-file body.md
   # after a later push, once scripts/ci passed on it: move the marker to the new head
   gh pr view <n> --json body --jq .body | sed "s/^Head: .*/Head: $(git rev-parse HEAD)/" >body.md
   gh pr edit <n> --body-file body.md
   ```
6. Don't ask questions. If the issue is impossible as written, comment on the
   issue saying why, remove `in-progress`, and stop.

## Rules

- **One behavior per PR.** Ideally under 200 changed lines, hard cap 400, at
  most 15 files.
- **Check current docs, not memory.** Before using any platform or library
  API (SwiftUI, AppKit, macOS 26 APIs, GRDB, Swift stdlib), check current docs
  with the docs MCP tools; don't rely on memory. If the tools are unavailable,
  say so in the PR body. `.mcp.json` provides them: `apple-docs`
  (`searchAppleDocumentation`, then `fetchAppleDocumentation`; Apple's
  developer docs, Swift stdlib and HIG, read live from developer.apple.com)
  and `context7` (`resolve-library-id`, then `query-docs`; GRDB is
  `/groue/grdb.swift/v7.11.1`, the version `Package.swift` pins, and Swift is
  `/swiftlang/swift`).
- **Every new source file has a C4 owner.** `scripts/ci` fails when a file
  under `Sources/` is not in exactly one component's `paths` in the C4 model.
  The model is assembled from one file per component in `docs/c4/parts/`
  (`<system>/<container>/<component>.json`) by `scripts/c4-assemble`: add the
  file to its component's part, or add a part for a new component, in the
  same PR, and keep that component's description true. Never edit the
  generated `docs/c4/model.json`; the Generated workflow rewrites it on `dev`.
- **Everything is a command.** Any change to a `Document` goes through a type
  that conforms to `Command` (see `Sources/FlareCore/Command.swift`), with
  `execute` and an exact `undo`. Add new commands to the random steps in
  `Tests/FlareCoreTests/UndoPropertyTests.swift`.
- **Never crash.** Untrusted input throws a typed error. `scripts/ci` fails on
  `try!`, `as!`, `fatalError(`, `preconditionFailure(`, `precondition(`,
  `unowned ` and `.first!` / `.last!` anywhere in `Sources/`. Also avoid
  unchecked array indexing and Int overflow on values from files.
- **Every module stays Linux-safe.** Foundation only (CoreCatalog may also
  import GRDB), imported as
  `#if canImport(FoundationEssentials) import FoundationEssentials #else import Foundation #endif`.
  No AppKit, SwiftUI, Metal, CoreGraphics, Combine, `NSRegularExpression`,
  `String(format:)` or other Darwin-only API. Swift 6 language mode; code must
  compile with Swift 6.1 (the macOS runner's Xcode may be older than Linux's).
  **One exception: Metal, in `CoreRenderMetal` only** (captain, 2026-10-17).
  Every file under `Sources/CoreRenderMetal/` is wrapped whole in
  `#if canImport(Metal)`, so Linux builds it as an empty module and `scripts/ci`
  stays green there. The Metal backend's Linux-safe parts (capabilities,
  tiling math, cache keys) live in `Sources/CoreRender/Metal/` with no Metal
  import, so their tests and mutations run on Linux. No other module imports
  Metal or depends on `CoreRenderMetal`.
- **Value types and Sendable.** Model types are `struct`/`enum`, `Codable`,
  `Sendable`, `Hashable`. No classes in the model, no shared mutable state.
- **Old files keep loading.** A new model field must decode from v1 files that
  lack it (optional, or a custom `init(from:)` with `decodeIfPresent` and a
  default). Add a test that decodes a file without the field.
- **Every change gets a test.** Swift Testing (`import Testing`, `@Test`,
  `#expect`). Seeded randomness only (`SplitMix64` in `Tests/FlareCoreTests/Support.swift`).
- **Invariants get a mutation entry.** New logic with an invariant (a guard,
  a limit, a formula, an undo path) adds one entry to
  `Tests/mutations/<module>.json` in the same PR, and
  `scripts/mutate --run --only "<words from its note>"` must report it caught.
  A refactor that moves an anchor repoints it. See `docs/engineering.md`,
  "Mutation testing".
- **Parsers get property and fuzz tests.** Anything that reads untrusted bytes
  gets a seeded fuzz test that asserts it throws instead of crashing.
- **No new dependencies** without an issue that approves them. GRDB is
  approved for CoreCatalog only, pinned `exact:` in `Package.swift`; no other
  target may depend on it. On Linux it needs `libsqlite3-dev`, which
  `scripts/cloud-setup.sh` and the Linux CI job install. Ubuntu's SQLite has no
  WAL snapshots, so GRDB compiles its snapshot API out on Linux: use
  `DatabaseQueue`, `DatabaseMigrator`, records and SQL, never `DatabasePool`,
  `DatabaseSnapshotPool` or snapshot-backed observation.
- **PR title** in Conventional Commits (`feat(timeline): hold easing`). The body
  says what changed, why, and which test proves it.
- **No AI attribution anywhere.** Commits, PR titles and bodies, and issue
  comments carry no `Co-Authored-By: Claude`, no `Claude-Session:` link and no
  "Generated with Claude Code" line. `.claude/settings.json` turns these off;
  if your tooling adds one anyway, delete it before you push. The fast lane
  also strips them from the squash commit.
- **No product names.** Don't name other companies' creative apps in code,
  docs or UI; describe the behavior instead.
- **Clean-room.** Never copy code, files or text from proprietary creative
  software or from GPL-incompatible sources. This repo is GPL-3.0. Behavior
  comes only from public documentation, published specs (W3C, Lottie, SVG,
  PDF, OpenRaster, XMP and the like) and code under a GPL-3.0-compatible
  license. Permissive code (MIT, Apache-2.0) may be studied and reused with
  attribution, after you read the license file of that exact repo at that
  exact commit; storytold's craft apps were MIT OR Apache-2.0 on 2026-10-10.
  Record the source repo, commit and license in `NOTICE`, or in the header of
  the copied file.
- **Never reverse engineer an app we don't own.** No decompiling,
  disassembling, or inspecting its binaries or bundles, and no
  reverse-engineering tools or MCPs (REA, Hopper, Ghidra, IDA and the like).
  Don't automate or scrape competitors' apps either. Reverse engineering a
  file format so we can open users' files is a legal call: get the captain's
  sign-off first.

## Quality

- Read `docs/engineering.md` before you write code. It holds the design rules
  for this codebase (layers, errors, reuse, validity, commands, export, tests).
- Before you open a PR, check your diff against `docs/review-rubric.md` and
  fix every "no".
- `scripts/ci` enforces the mechanical rules (no-crash lint, C4 ownership,
  duplicate code, build, tests). The rest are review-only, and the reviewer
  applies the rubric.

## Parallel agents

- Many agents work at once. Keep to your issue's files. Prefer adding a new
  file (one per command family, e.g. `SceneCommands.swift`) over appending to
  a shared one; it avoids merge conflicts.
- Rebase on `origin/dev` before opening the PR, and rerun `scripts/ci` after.
- If `scripts/ci` fails on `origin/dev` itself because of someone else's merge
  (look for the open `dev-red` issue), do not fix it in your PR. Comment on
  your issue with the failing test name and stop.
- **Never edit** `.github/`, `.claude/`, `CLAUDE.md`, `AGENTS.md`,
  `scripts/ci`, `scripts/cloud-setup.sh`, `scripts/fast-lane.sh`,
  `scripts/mutate`, `scripts/c4-assemble`, `Package.swift`, `Package.resolved`
  or `LICENSE` unless your issue says to, and never the generated
  `docs/c4/model.json` at all (edit its parts in docs/c4/parts/). Those PRs
  need human review. The fast lane refuses
  exactly this list (PROTECTED in scripts/fast-lane.sh; its tests read this
  bullet), so every path here goes in backticks and nothing else.

## Feature leads

A session started from a `feature-lead` issue is a lead: it follows
`docs/factory/lead.md` (packet, build waves, Anatomy loop, contact sheet) and
its workflow templates in `docs/factory/workflows/`. A packet with a Slices
table runs the v3 loop (lead.md rules 12 to 19) with two levels of done:
merged-done (`Belt-Slice-Done:`) when the slice's PRs merged and dev's
`Linux` job is green with them, and verified (`Belt-Slice-Verified:`) when
its budgets and parity hold on the Mac. Every PR a lead or its
agents open carries `Belt-Lead: <run id>` and `Feature: <feature>` lines
above the `Fast-Check:` / `Head:` lines. `Belt-Lead:` PRs don't wait for
`belt/review`; the lead's critic panel is their review.

## Fast lane

Crew PRs merge into `dev` at once; `main` moves only when full CI passes on
`dev`.

- `.github/workflows/fast-lane.yml` squash-merges a PR labelled `fast-lane`
  into `dev` when all of these hold: base `dev`, author on the allowlist in
  `scripts/fast-lane.sh`, at most 400 changed lines and 15 files, no protected
  path touched (the list above), mergeable, no red or running check on the
  head, and proof the head passed the gate: the `Fast-Check: pass` /
  `Head: <sha>` lines for the current head, or a passing CI check on it.
- Each lane run merges every eligible PR, oldest first. A PR that conflicts
  after an earlier merge gets one comment and waits for a rebase. A fast-lane
  PR opened against `main` is retargeted to `dev`.
- A Belt PR (its body has a `Belt-Run:` or `Belt-Test:` line) also waits for
  Belt's `belt/review` commit status to be success on its head;
  `REQUIRE_BELT_REVIEW` in `scripts/fast-lane.sh` turns that off.
- A PR that breaks a hard rule (author, size, protected path) loses the label
  with a comment saying why and waits for human review.
- Full CI (Linux, macOS, mutation) runs on `dev` once a feature is built, not
  per merge: when the supervisor or Belt dispatches it, when the lane merges a
  PR labelled `feature-done`, after every 10 merged PRs since the last CI run
  (at most once per lane run), and once a day. Green: `main` fast-forwards to
  that exact SHA. Red: one issue titled "dev is red" (label `dev-red`) names
  the failing jobs and the culprit range `main..<sha>`. The lane keeps
  merging while it is open; the next green run moves `main` and closes it.
- A PR into `dev` that touches the Metal backend (`Sources/CoreRenderMetal/`,
  `Sources/CoreRender/Metal/`, `Tests/CoreRenderMetalTests/`) gets one check of
  its own, `Metal (macOS)` from `.github/workflows/metal-pr.yml`: it builds
  with tests and runs the Metal tests. The lane waits while it runs and holds
  the PR while it is red. Linux builds the Metal module empty, so this is the
  only place a Metal break shows up before `dev`.
- A human reviews fast-lane merges after the fact and reverts anything wrong.

## Commands

```bash
scripts/ci                                  # lint + C4 ownership + build + test: the gate
scripts/c4-assemble --check                 # docs/c4/model.json matches docs/c4/parts/ (on dev)
swift test --filter EasingTests             # one suite while iterating
bash Tests/fast_lane/test_fast_lane.sh      # fast-lane decision tests (needs jq)
scripts/mutate --validate                   # every mutation anchor resolves once
scripts/mutate --run --changed-since origin/dev   # plant the bugs your diff touches
```

## Layout

- `Sources/FlareCore/Document.swift`: model (Document, Scene, Layer, Keyframe, Shape)
- `Sources/FlareCore/Command.swift`: `Command` protocol, `CommandEngine` (undo, redo, groups)
- `Sources/FlareCore/Commands.swift`: built-in commands
- `Sources/FlareCore/Easing.swift`, `Timeline.swift`: tweening
- `Sources/FlareCore/FlareFormat.swift`: `.flare` JSON format v1 and validation
- `Tests/FlareCoreTests/`: one test file per area, plus `Support.swift`
- `docs/gaps.md`: the ranked work list
