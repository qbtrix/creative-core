export const meta = {
  name: 'critic-panel',
  description: 'One critic per lens over a core feature\'s diff, gate and mutation output, then a refuting verifier per finding',
  whenToUse: 'Stage 4 of docs/factory/lead.md: one Anatomy loop round\'s review',
  phases: [
    { title: 'Critique', detail: 'one critic per lens' },
    { title: 'Verify', detail: 'one verifier per finding tries to refute it' },
  ],
}

// args: {
//   feature: 'keyframe-hold', round: 2,
//   packet: 'docs/blueprints/core/features/keyframe-hold.md',
//   sha: '<full origin/dev sha the round runs on>',
//   firstBase: '<full sha the feature started from>',   // the diff is firstBase..sha
//   gate: '<scratchpad>/round-2/ci.log',                // scripts/ci output on sha
//   mutation: '<scratchpad>/round-2/mutate.log',        // scripts/mutate --run output on sha
//   run: '<CI run link on dev, or "-">',
//   lenses: ['clarity', 'contract', ...],               // optional; keep the same list after a clean round
// }
// Returns { clean, confirmed: [finding], refuted: n }. clean = no confirmed blocker or major.

const LENSES = {
  clarity: 'First-use clarity: read the public API as a new caller would. What does each type, function, parameter and error case mean to someone new? Flag a name that hides what it does or its unit, an error case or message that does not say what went wrong or how to fix it, a public symbol without a doc comment, and a packet example that does not compile against the API as built.',
  contract: 'The packet: every task\'s behavior and acceptance test. Flag a behavior that is missing, partial, or differs from the packet, and an acceptance test that does not test what it claims.',
  undo: 'Commands (docs/engineering.md, "Commands"): every document change is a Command whose undo restores the document exactly, inside groups and coalesced runs; the document and the undone document pass FlareFormat.validate; every new command is a step in UndoPropertyTests and in its family\'s `all`.',
  robustness: 'Never crash: untrusted input (files, manifests, pixel data, SQL rows) throws the module\'s typed error. Flag unchecked indexing, Int overflow on file values, unbounded allocation, a parser without a seeded fuzz test, and a forbidden construct the lint misses.',
  compat: 'Old files keep loading: a new field decodes from files that lack it, with a test that decodes such a file; format and manifest changes keep earlier files valid; Linux-safe Foundation imports only; code that compiles with Swift 6.1.',
  design: 'docs/engineering.md and docs/review-rubric.md: layers, one error type per module, reuse of existing helpers instead of near-copies, C4 ownership and component descriptions, value types that are Sendable and Hashable. Flag anything that breaks a rule, naming the rule.',
  tests: 'Test quality: every escaped mutant in the mutation output, every new invariant without a Tests/mutations entry, and tests that would still pass with the behavior removed. Name the missing assertion.',
}
const lenses = (args.lenses && args.lenses.length ? args.lenses : ['clarity', 'contract', 'undo', 'robustness', 'tests'])
if (!lenses.includes('clarity')) lenses.unshift('clarity')

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          where: { type: 'string', description: 'file:line or symbol the finding is in, or "-"' },
          what: { type: 'string' },
          why: { type: 'string', description: 'the rule, acceptance test or caller confusion it breaks' },
          fix: { type: 'string', description: 'the smallest change that fixes it' },
          files: { type: 'array', items: { type: 'string' } },
          test: { type: 'string', description: 'the test that would fail before the fix' },
        },
        required: ['severity', 'where', 'what', 'why', 'fix', 'files', 'test'],
      },
    },
  },
  required: ['findings'],
}
const VERDICT = {
  type: 'object',
  properties: { refuted: { type: 'boolean' }, reason: { type: 'string' } },
  required: ['refuted', 'reason'],
}

const ctx = `Feature ${args.feature} (line:core), Anatomy round ${args.round}, on origin/dev ${args.sha}.
Packet: ${args.packet}. Diff: git fetch origin dev && git diff ${args.firstBase}..${args.sha}.
Gate output: ${args.gate}. Mutation output: ${args.mutation}. CI run on dev: ${args.run}.
Read the code itself, not only the diff. Report only; do not edit, push or merge.`

phase('Critique')
const verified = await pipeline(
  lenses,
  lens => agent(`${ctx}\n\nYour lens: ${LENSES[lens] || lens}\nReport each problem once, only from this lens. No problem: return an empty list.`,
    { label: `critic:${lens}`, phase: 'Critique', schema: FINDINGS }),
  (r, lens) => parallel((r ? r.findings : []).map(f => () =>
    agent(`${ctx}\n\nA ${lens} critic reports (${f.severity}) at ${f.where}: ${f.what}\nWhy: ${f.why}\n` +
      'Try to refute it: read the code at that SHA and, where it helps, write a scratch test. refuted=true if it is ' +
      'not in the code, not a problem, already fixed on dev, or outside this feature. Keep it only if you can show it.',
      { label: `verify:${lens}`, phase: 'Verify', schema: VERDICT, effort: 'low' })
      .then(v => ({ ...f, lens, refuted: !v || v.refuted, reason: v ? v.reason : 'verifier died' })))),
)
const all = verified.filter(Boolean).flat().filter(Boolean)
const confirmed = all.filter(f => !f.refuted)
const clean = !confirmed.some(f => f.severity !== 'minor')
log(`round ${args.round}: ${confirmed.length} confirmed, ${all.length - confirmed.length} refuted, ${clean ? 'clean' : 'not clean'}`)
return { clean, confirmed, refuted: all.length - confirmed.length }
