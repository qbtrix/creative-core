# text-engine lead record

Issue: #437 · Packet: docs/blueprints/core/features/text-engine.md
Run: act-1a157fd0281-warg · Session: 2df03724-340d-5741-940b-d32d0ef62e2a · Resumed: 2026-10-20T06:25Z
Stage: done (merged-done; contact sheet posted)
Base: fa40b3427c6950e982d58c55d769f2dc5f7f1923
Next: Mac finisher verifies TE-z release budgets

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| TE-1 | W1 | The layout and command stubs, `ResolvedRun`, `resolvedRuns` (real: it is a contract value), `FixedAdvances`; `TextShapeTests` | `Sources/FlareCore/TextLayout.swift`, `Sources/FlareCore/TextLayout+Path.swift`, `Sources/FlareCore/TextStyleCommands.swift`, `Tests/FlareCoreTests/TextShapeTests.swift`, `Tests/mutations/FlareResolvedRuns.json` | `TextShapeTests`: `resolvedRuns` of a plain shape is one run over the string; with a bold run in the middle, three runs that tile the string; emoji count as one grapheme; stubs throw | `FlareResolvedRuns`: gap filler skipped at the end → `TextShapeTests.runsTileTheString`; `utf16.count` for `count` → `.emojiIsOneGrapheme` | #567 | merged |
| TE-2 | W2 | Checks first: `TextStyleCommandsTests` (and its `undoSteps`, `expectedIDs`), `TextLayoutTests`, `TextOnPathTests`, `SVGTextExportTests`, disabled by name; text fixtures (Latin, emoji, combining marks, a 10,000-grapheme paragraph) | `Tests/FlareCoreTests/TextStyleCommandsTests.swift`, `Tests/FlareCoreTests/TextLayoutTests.swift`, `Tests/FlareCoreTests/TextOnPathTests.swift`, `Tests/FlareCoreTests/SVGTextExportTests.swift`, `Tests/FlareCoreTests/TextFixtures.swift` | suites compile, disabled | – | #614 | merged |
| TE-3 | W3 | `ApplyTextStyle`, `ClearTextStyle`, `EditTextString`; turns on their cases | `Sources/FlareCore/TextStyleCommands.swift`, `Tests/FlareCoreTests/TextStyleCommandsTests.swift`, `Tests/mutations/FlareTextStyleCommands.json` | `TextStyleCommandsTests`: bold on 6..<11 of "Bring the light" gives three runs; bold again on 6..<8 changes nothing; bold on 0..<15 then clear gives no runs; editing before a run shifts it, inside it grows it, across it shrinks it; inserted text takes the style before it; a range past the end or on a locked layer is refused unchanged; exact undo in `UndoPropertyTests` | `FlareTextStyleCommands`: merge skipped (equal neighbours stay split) → `TextStyleCommandsTests.equalNeighboursMerge`; shift uses `>=` for `>` at the edit point → `.runAtEditPointGrows`; range check `<=` for `<` → `.rangePastEndRefused` | #615 | merged, Mutate 3/3 FlareTextStyleCommands |
| TE-4 | W3 | `SetParagraphStyle`, `SetTextOnPath` in a second file, with the drag merge | `Sources/FlareCore/TextStyleCommands+Paragraph.swift`, `Tests/FlareCoreTests/TextParagraphCommandsTests.swift`, `Tests/mutations/FlareTextParagraphCommands.json` | `TextParagraphCommandsTests`: set, change and clear paragraph and path settings with exact undo; a drag of `lineHeight` merges into one step; `lineHeight` 5 refused | `FlareTextParagraphCommands`: merge on a different field → `TextParagraphCommandsTests.mergeOnlySameField`; validation skipped → `.lineHeightFiveRefused` | #619 | merged, Mutate 4/4 FlareTextParagraphCommands |
| TE-5 | W3 | `TextLayout.lay`; turns on `TextLayoutTests` | `Sources/FlareCore/TextLayout.swift`, `Tests/FlareCoreTests/TextLayoutTests.swift`, `Tests/mutations/FlareTextLayout.json` | `TextLayoutTests` on `FixedAdvances`: 10 graphemes of 12 pt at box 30 wrap into 2 lines at the space; a 20-grapheme word breaks by grapheme; trailing space not counted; centre shifts by half the slack; justified first line ends at the box edge and the last line doesn't; line gap = 1.5 × 24; a newline adds paragraph spacing; tracking adds per grapheme; 10,000 graphemes lay out; more than `maxGraphemes` throws | `FlareTextLayout`: trailing whitespace counted → `TextLayoutTests.trailingSpaceDoesNotWrap`; justify the last line → `.lastLineNotJustified`; line height from the first run only → `.mixedSizesUseTallest`; tracking added once per line → `.trackingPerGrapheme` | #618 | merged, Mutate 4/4 FlareTextLayout |
| TE-6 | blocked (PG-measure) | `onPath`; turns on `TextOnPathTests` | `Sources/FlareCore/TextLayout+Path.swift`, `Tests/FlareCoreTests/TextOnPathTests.swift`, `Tests/mutations/FlareTextOnPath.json` | `TextOnPathTests`: on a 100-unit straight line, offset 0.25, glyphs start at x 25 at 0°; on a circle the tangent is perpendicular to the radius within 1e-6; flip runs the other way; glyphs past the end of an open path are not placed; a closed path wraps | `FlareTextOnPath`: centre at `s + x` without `advance / 2` → `TextOnPathTests.glyphCentredOnPath`; flip ignored → `.flipReverses` |  | open |
| TE-7 | W4 | SVG text writer for runs, lines and alignment; turns on those cases | `Sources/FlareCore/Export/SVGExporter+Text.swift`, `Tests/FlareCoreTests/SVGTextExportTests.swift`, `Tests/mutations/FlareSVGText.json` | `SVGTextExportTests`: the fixture writes one `text` with three `tspan`s and their attributes, two line `tspan`s at their baselines, `text-anchor` middle for centre, explicit `x` lists on a justified line; byte-stable over two runs | `FlareSVGText`: `font-weight` from the shape, not the run → `SVGTextExportTests.runWeightWritten`; baseline from line index × size → `.baselinesFromLayout` | #679 | merged |
| TE-8 | after TE-6 | SVG `textPath` in a second file; its cases in a second suite | `Sources/FlareCore/Export/SVGExporter+TextPath.swift`, `Tests/FlareCoreTests/SVGTextPathExportTests.swift` | `SVGTextPathExportTests`: `textPath` with `startOffset` as a percentage and the path in `defs`; flip reverses the path data | none beyond TE-7's plan (one formatting path) |  | open |
| TE-9 | after TE-8 | KJ-TE walk; `TextBudgetTests` (release, `.serialized`) | `Tests/FlareCoreTests/TextWalkTests.swift`, `Tests/FlareCoreTests/TextBudgetTests.swift` | `TextWalkTests.walk` (KJ-TE); `TextBudgetTests`: lay out 10,000 graphemes ≤ 4 ms; 500 glyphs on a path ≤ 2 ms (release, reported) | none |  | open |
| TE-10 | last | The packet's status line; `feature-done` | `docs/blueprints/core/features/text-engine.md` | status line says built | – |  | open |

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| TE-a | TE-1, TE-2 | engine-contracts:EC-f | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39190181936 | – |
| TE-cmd | TE-3, TE-4 | TE-a | merged-done | https://github.com/qbtrix/creative-core/actions/runs/39196728473 | – |
| TE-lay | TE-5, TE-6 | TE-a; path-geometry:PG-measure (TE-6) | merged-done (#761) | https://github.com/qbtrix/creative-core/actions/runs/39389993450 | – |
| TE-svg | TE-7, TE-8 | TE-cmd, TE-lay | merged-done (#763) | https://github.com/qbtrix/creative-core/actions/runs/39389993450 | – |
| TE-z | TE-9, TE-10 | TE-svg | merged-done (#764 feature-done) | https://github.com/qbtrix/creative-core/actions/runs/39389993450 | wanted (release time budgets), Mac-Finish-Wanted posted |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|
| 1 | 27f5e36 | PASS | see confirmed | | | gate CI: PASS, mutants 11/11 caught, 15 confirmed (majors: lineHeight unit doc, grapheme invalidIndex undocumented, hyphen break untested, lay throws unasserted), 0 refuted. Fix batches r1-cmd (1,2,4,14) and r1-lay (0,3,5,6,9-13). Findings 7 (TE-8 owns SVGTextPathExportTests) and 8 (TE-6 circle tangent tolerance) go to the TE-6/TE-8 builders. | | no |
| 2 | 5142795 | PASS | see confirmed | | | gate PASS, mutants 14/14 4/4 5/5; panel 15 confirmed (2 major: TE-7 not built; spacing-at-hard-break untested), 0 refuted. Not clean. | | no |
| 3 | 097fa44 | PASS | 35/35 | 39230628738 (queued, earlier sha) | clarity contract undo robustness tests | 14 (4 major, 10 minor), 0 refuted | r3-svg, r3-lay, r3-undo (running) | no |
| 4 | 4ad2c5a | PASS | 45/45 | pending (39238594196 on 8613770 queued) | clarity contract undo robustness tests | 10 (3 major, 7 minor), 1 refuted | filed #706 #707 #708 | no |

## Decisions
- Line lead over text-engine #437, retouch-heal #436, fill-tools #435: one wave plan; tasks share a wave only with disjoint files.
- Cross-feature waves (revised): W1 TE-1 FT-0 FT-2 RH-0 RH-2; W2 TE-2 FT-1 RH-1; W3 TE-3 TE-4 TE-5 FT-3 FT-4 FT-5 RH-3 RH-5 RH-6; W4 TE-7 FT-6 RH-4; W5 FT-7 RH-7; W6 FT-8 RH-8.
- Rule 18: fill-tools and retouch-heal have no stubs on dev, so their disabled checks (FT-1, RH-1) could not compile. Added FT-0 and RH-0 "declare the stubs" (signatures verbatim from the Contract slice, bodies throw RasterError.invalid) to wave 1; checks move to wave 2.
- TE-1 puts the SetParagraphStyle and SetTextOnPath stubs in TextStyleCommands+Paragraph.swift, the file TE-4 owns.
- engine-contracts is built (EC-a, EC-f met); C4 parts already own the planned paths, so no C4 edits.
- Builder branches are lead/<feature>-<task> (lead/<feature>/<task> cannot exist next to the lead branch lead/<feature>).
- TE-1 touched Tests/FlareCoreTests/CommandFuzzTests.swift (one line: subtract CommandRegistryTests.notBuiltIDs) so the fuzz test skips the stubs; accepted. The five stub commands join UndoPropertyTests when TE-3 and TE-4 build their bodies.
- #567 said Closes #437 and closed the feature issue; reopened it. Task PRs now say Part of #<issue>.
- The GitHub MCP server appends an attribution footer to PR bodies and comments; builders now edit it out right after posting (an edit does not re-add it). The lane strips it from squash commits.
- Container restart killed the running builders before they pushed. Their local commits were kept as tags keep/<task> and new builders cherry-pick them (no work redone).
- TE-3 edited TextShapeTests (stub-check skip) and added a styled run to CommandRegistryTests sampleDocument: needed for the registry to cover runs; accepted.
- TE-4 edited TextStyleCommandsTests (owner of notBuiltIDs); lineHeight validation reuses the FlareFormat check; accepted.
- TE-5 removed layoutStubsThrowNotBuilt lines and strengthened lastLineNotJustified; docs MCP not consulted (stdlib only); accepted.
- r1-cmd #656 5/5 FlareTextStyleCommands, gated CI: PASS.
- TE-7 was missed in wave 4 though its waits (TE-3, TE-5) merged; built now as batch r2-te7. TE-6 tolerance finding (#7) deferred to the TE-6 builder (PG-measure still not on dev affd140). CommandError gets no new case for the fusing-grapheme error (shared Command.swift); message and doc instead.
- Round 4 was the last Anatomy round (lead.md round budget). The 10 open findings went to 3 gap issues grouped by area rather than 10 single issues, matching how other leads filed theirs (#703-#705).

## Open
- #706 fixed by #763 (TE-8); closes with it. #707 #708 stay open as gap issues.
