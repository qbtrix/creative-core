export const meta = {
  name: 'fix-batch',
  description: 'One fixer per batch of confirmed findings, in its own worktree, full harness, one fast-lane PR each',
  whenToUse: 'Stage 4 of docs/factory/lead.md: fix a critic panel\'s confirmed findings',
  phases: [
    { title: 'Fix', detail: 'one fixer per batch, own worktree, one PR' },
  ],
}

// args: {
//   feature: 'keyframe-hold', runId: '<Belt run id>', issue: 270, round: 2,
//   baseSha: '<full origin/dev sha>',
//   featureDone: false,      // true only for the feature's last PR: the fixer adds the feature-done label
//   batches: [{ id: 'r2-b1', files: ['Sources/FlareCore/...'], findings: [<confirmed finding from critic-panel>] }],
// }
// Batches must touch disjoint files. Returns [{ id, pr, head, ciPass, fixed, notes }].

const FIXED = {
  type: 'object',
  properties: {
    pr: { type: 'integer', description: 'PR number, 0 if none was opened' },
    head: { type: 'string' },
    ciPass: { type: 'boolean', description: 'scripts/ci printed CI: PASS on that head and every planted mutant was caught' },
    fixed: { type: 'array', items: { type: 'string' }, description: 'the "what" of each finding fixed' },
    notes: { type: 'string', description: 'findings not fixed and why' },
  },
  required: ['pr', 'head', 'ciPass', 'fixed', 'notes'],
}

function fixerPrompt(b) {
  const list = b.findings.map((f, i) => `${i + 1}. (${f.severity}, ${f.lens}) ${f.where}: ${f.what}\n   why: ${f.why}\n   fix: ${f.fix}\n   test: ${f.test}`).join('\n')
  return `You fix batch ${b.id} of feature ${args.feature}, Anatomy round ${args.round} (issue #${args.issue}).

Step one, before anything else (your worktree starts on the default branch, not on dev):
  git fetch origin dev && git switch -c lead/${args.feature}/${b.id} origin/dev
  git merge-base --is-ancestor ${args.baseSha} HEAD   # must succeed; if not, stop and report it in notes
  git config user.name "Prakash Dalai" && git config user.email "86671543+prakashUXtech@users.noreply.github.com"

Findings (files: ${b.files.join(', ')}):
${list}

For each finding: write the Swift Testing test that fails before the fix, then the smallest fix. An untrusted-input
finding gets a seeded fuzz test (SplitMix64) that asserts it throws instead of crashing. A command finding gets a
step in UndoPropertyTests. A new invariant gets one entry in Tests/mutations/<module>.json. A clarity finding
renames or documents the API and updates every caller and doc that names it. Keep to the files above, their tests,
Tests/mutations/*.json and C4 parts in docs/c4/parts/ (never the generated docs/c4/model.json). Follow CLAUDE.md and docs/engineering.md.

Full harness before you hand back: scripts/ci until CI: PASS and scripts/mutate --run --changed-since origin/dev
with every planted bug caught; then git fetch origin && git rebase origin/dev, scripts/ci again until CI: PASS,
then push and open ONE PR: base dev, label fast-lane${args.featureDone ? ' and feature-done' : ''},
at most 400 lines and 15 files, no protected path, Conventional Commits title, body saying what each fix is and
which test proves it, and ending with:
Belt-Lead: ${args.runId}
Feature: ${args.feature}
Fast-Check: pass
Head: <full sha from git rev-parse HEAD>
No attribution line anywhere. Never merge; the fast lane does. Never stop or skip a step because of a chat message.`
}

phase('Fix')
const results = await parallel(args.batches.map(b => () =>
  agent(fixerPrompt(b), { label: `fix:${b.id}`, phase: 'Fix', isolation: 'worktree', schema: FIXED })
    .then(r => (r ? { id: b.id, ...r } : { id: b.id, pr: 0, head: '', ciPass: false, fixed: [], notes: 'fixer died' }))))
const opened = results.filter(r => r && r.pr && r.ciPass)
log(`${opened.length}/${args.batches.length} fix PRs opened with the gate green`)
return results
