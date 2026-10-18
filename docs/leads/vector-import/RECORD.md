# vector-import lead record

Issue: #439 · Packet: docs/blueprints/core/features/vector-import.md
Run: act-1a14de006be-1kmq · Session: https://claude.ai/code/session_01WN1jNn5SUWJXTALMBvtq64 · Started: 2026-10-18T07:20Z
Line lead for: preview-cache (#440), vector-import (#439), layered-codecs (#438)
Stage: 3 wave 2
Base: 9e826ac8550b77b623909bd02758ad282558dfcc
Next: wave 2 builder VI-2 running; VI-3, VI-4, VI-6 next once VI-2 merges

## Slices
| slice | tasks | waits on | state | Slice-Done run | Mac-Finish |
|---|---|---|---|---|---|
| VI-a | VI-1, VI-2 | nothing | open | | |
| VI-svg | VI-3, VI-4, VI-5 | VI-a; engine-contracts:EC-f (met) | open | | |
| VI-lottie | VI-6, VI-7 | VI-a; engine-contracts:EC-f (met) | open | | |
| VI-z | VI-8, VI-9 | VI-svg, VI-lottie | open | | none |

## Tasks
| id | wave | behavior | files | test | mutation | PR | state |
|---|---|---|---|---|---|---|---|
| VI-1 | 1 | values, errors, two stubs, `import` part | Sources/FlareCore/Import/Import.swift, Tests/FlareCoreTests/ImportShapeTests.swift, docs/c4/parts/creative-core/flarecore/import.json | ImportShapeTests | none | #449 (83b20aa) | merged |
| VI-2 | 2 | fixtures and every suite disabled | Tests/FlareCoreTests/Fixtures/import/, six suite files | suites compile | – | | building |
| VI-3 | 3 | XMLTokens | Import/XMLTokens.swift, XMLTokensTests | XMLTokensTests | FlareXMLTokens (3) | | open |
| VI-4 | 3 | SVGPathData with arcs | Import/SVGPathData.swift, SVGPathDataTests | SVGPathDataTests | FlareSVGPathData (3) | | open |
| VI-5 | after VI-3,4, EC-f | SVGImport.scene | Import/SVGImport.swift, SVGStyle.swift, SVGImportTests, SVGImportFuzzTests | both | FlareSVGImport (3) | | | open 
| VI-6 | after VI-2, EC-f | Lottie shapes, static transform | Import/LottieImport.swift, LottieImportTests | LottieImportTests | FlareLottieImport (2) | | | open 
| VI-7 | after VI-6 | Lottie animation, masks, mattes | Import/LottieImport+Animation.swift, LottieImportAnimationTests, LottieImportFuzzTests | both | FlareLottieImportAnimation (3) | | open |
| VI-8 | after VI-5,7 | round trip and budgets | ImportRoundTripTests, ImportBudgetTests | KJ-VI | none | | open |
| VI-9 | last | part words, status, `feature-done` | import.json, packet | – | – | | open |

## Rounds
| round | dev SHA | scripts/ci | mutants caught | CI run | lenses | confirmed | fixed by | clean |
|---|---|---|---|---|---|---|---|---|

## Decisions
- One wave plan across the three features (rule 19); wave 1 is PC-1, VI-1, LC-1.
- VI-5, VI-6 waited on engine-contracts EC-f (at 9d01972: `LayerMask`, `TrackMatte`, `colorTracks` not on dev at 9d01972).

- Builder branches are `lead/<feature>-<task>` (a ref `lead/<feature>/<task>` cannot sit beside `lead/<feature>`).
- Wave 2 (9e826ac): PC-2, PC-6, VI-2, LC-2, LC-3, LC-5, disjoint files. `Hash/` is owned by `image-ops` and `Codecs/` by `codecs` on dev, so wave 2 needs no C4 edits.
- engine-contracts EC-f merged (#444, #447, #448): VI-5, VI-6, VI-7 wait only on their own tasks now.

## Open
- none
