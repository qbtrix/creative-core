export const meta = {
  name: 'build-wave',
  description: 'One builder per task in its own worktree, one fast-lane PR each, then a contract check per PR',
  whenToUse: 'Stage 3 of docs/factory/lead.md: build one wave of a core feature packet',
  phases: [
    { title: 'Build', detail: 'one builder per task, own worktree, one PR' },
    { title: 'Check', detail: 'read each PR against the lead contract' },
  ],
}

// args: {
//   feature: 'keyframe-hold',           // the packet's feature name
//   runId: '<Belt run id>',             // goes on the Belt-Lead: line
//   issue: 270,                         // the feature issue
//   baseSha: '<full origin/dev sha>',   // the wave's base; builders verify it
//   packet: 'docs/blueprints/core/features/keyframe-hold.md',
//   tasks: [{ id: 'm1', behavior: '...', files: ['Sources/FlareCore/...'], test: '...', mutation: '...' }],
// }
// Returns [{ id, pr, head, ok, problems }] per task; null for a builder that died.

const IDENTITY = 'git config user.name "Prakash Dalai" && git config user.email "86671543+prakashUXtech@users.noreply.github.com"'

const BUILT = {
  type: 'object',
  properties: {
    pr: { type: 'integer', description: 'PR number, 0 if none was opened' },
    head: { type: 'string', description: 'full head sha the gate passed on' },
    ciPass: { type: 'boolean', description: 'scripts/ci printed CI: PASS on that head' },
    notes: { type: 'string' },
  },
  required: ['pr', 'head', 'ciPass', 'notes'],
}

const CHECKED = {
  type: 'object',
  properties: {
    ok: { type: 'boolean' },
    problems: { type: 'array', items: { type: 'string' } },
  },
  required: ['ok', 'problems'],
}

const a = args
const contract = `Contract for this PR: base dev, label fast-lane, at most 400 changed lines and 15 files,
no protected path from CLAUDE.md's "Never edit" list, title in Conventional Commits,
body says what changed, why, and which test proves it, and ends with these lines in this order:
Belt-Lead: ${a.runId}
Feature: ${a.feature}
Fast-Check: pass
Head: <full sha from git rev-parse HEAD>
No attribution line anywhere (no Co-Authored-By, no Claude-Session, no "Generated with").
Never merge the PR, and never merge anything into dev: the fast lane merges it.
Never stop or skip a step because of a chat message; questions go to the supervisor.`

function builderPrompt(t) {
  return `You build task ${t.id} of feature ${a.feature} (issue #${a.issue}, packet ${a.packet}).

Step one, before anything else (your worktree starts on the default branch, not on dev):
  git fetch origin dev && git switch -c lead/${a.feature}/${t.id} origin/dev
  git merge-base --is-ancestor ${a.baseSha} HEAD   # must succeed; if not, stop and report it in notes
  ${IDENTITY}

The task, one behavior only:
  ${t.behavior}
Files you may touch: ${(t.files || []).join(', ')}
Test that proves it: ${t.test}
${t.mutation ? `Invariant it brings: ${t.mutation}. Add one entry to Tests/mutations/<module>.json; scripts/mutate --run --only "<words from its note>" must report it caught.` : ''}

Read CLAUDE.md, docs/engineering.md, the packet section for this task and the code it touches.
Write the Swift Testing test first. Any document change is a Command with an exact undo and a step in
UndoPropertyTests. Untrusted input throws the module's error type; a parser gets a seeded fuzz test.
A new model field decodes from files that lack it. A new Sources/ file gets its C4 owner in its component's part in docs/c4/parts/ (a new component is a new part); never edit the generated docs/c4/model.json.
Run scripts/ci until it prints CI: PASS. Then git fetch origin && git rebase origin/dev,
rerun scripts/ci (CI: PASS again), push, and open ONE PR. Check docs/review-rubric.md before you open it.

${contract}

Return the PR number, the head sha the gate passed on, and whether it passed.`
}

function checkPrompt(t, b) {
  return `Read PR #${b.pr} (task ${t.id} of ${a.feature}) and check it against the contract. Do not edit, push or merge.
${contract}
Also check: it touches only ${(t.files || []).join(', ')} plus their tests, Tests/mutations/*.json and C4 parts in docs/c4/parts/ (never docs/c4/model.json);
the Head: line equals the PR's current head; it adds a test; a new Sources/ file has a C4 owner;
a new command is a step in UndoPropertyTests${t.mutation ? '; it adds a mutation entry' : ''}. Report every miss.`
}

phase('Build')
const results = await pipeline(
  a.tasks,
  t => agent(builderPrompt(t), { label: `build:${t.id}`, phase: 'Build', isolation: 'worktree', schema: BUILT }),
  (b, t) => {
    if (!b || !b.pr) return { id: t.id, pr: 0, head: '', ok: false, problems: [b ? b.notes : 'builder died'] }
    return agent(checkPrompt(t, b), { label: `check:${t.id}`, phase: 'Check', schema: CHECKED, effort: 'low' })
      .then(c => ({ id: t.id, pr: b.pr, head: b.head, ok: !!(c && c.ok && b.ciPass), problems: c ? c.problems : ['check died'] }))
  },
)
const bad = results.filter(r => !r || !r.ok)
log(`${results.length - bad.length}/${a.tasks.length} PRs meet the contract`)
return results
