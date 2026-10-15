#!/usr/bin/env bash
# scripts/fast-lane.sh: merge small, checked crew PRs into BASE_BRANCH (dev)
# without waiting for captain review. The captain batch-reviews merged
# fast-lane PRs later and reverts anything wrong. Rules for agents: CLAUDE.md,
# "Fast lane".
#
# Run by .github/workflows/fast-lane.yml with this file from the trusted main
# branch. It only reads PR metadata through the GitHub API. It never checks out
# or runs PR code.
#
# The branch model: workers run scripts/ci on their own machine, the lane merges
# into dev at once, full CI runs on dev once a feature is built, and the
# `promote` job in ci.yml fast-forwards main to a dev SHA only when that run is
# green. A red dev run opens the "dev is red" issue. The lane keeps merging
# while dev is red, on purpose: promotion is the guard that keeps main green,
# and holding the lane would only stack the queue behind one bad merge.
#
# Eligibility (all must hold): open, not draft, label `fast-lane`, base
# BASE_BRANCH, author in FAST_LANE_AUTHORS, size within MAX_LINES/MAX_FILES, no
# changed or renamed-away path under PROTECTED (CLAUDE.md's "Never edit" list),
# MERGEABLE, no red or running check on the head,
# and proof the head passed the gate: a passing check from CI_WORKFLOWS on the
# head, or the worker's marker in the PR body, a line `Fast-Check: pass`
# followed by the line `Head: <full head sha>` for the current head (the same
# shape as Belt's `Belt-Review: pass` / `Head:` verdict). A Belt PR (a body line
# starting `Belt-Run:` or `Belt-Test:`) also needs Belt's `belt/review` commit
# status at success on its head while REQUIRE_BELT_REVIEW=1. A fast-lane PR
# based on main is retargeted to BASE_BRANCH. A PR that conflicts with the base
# gets one comment per head and keeps its label for Belt's fixer.
#
# Every run sweeps all open fast-lane PRs, oldest first, and merges each
# eligible one. After its merges the lane dispatches CI on BASE_BRANCH at most
# once per run (dispatch_reason), when it merged a PR labelled FEATURE_LABEL or
# BASE_BRANCH holds DISPATCH_EVERY merged PRs since the last CI run's head.
# Leads can't dispatch CI themselves (403), so the lane does it for them.
# Trade-off: breakage only the full CI catches (the macOS build, mutation
# testing) sits on dev until that run, so the dev-red culprit range can span
# several PRs.
#
# `decide` is the pure decision function (no network). It reads a PR JSON file,
# a file-list file (one path per line) and a check-rollup JSON file, logs each
# rule to stderr, and prints one line to stdout:
#   skip|<why>  retarget|<from base>  not-eligible|<reasons>  red|<checks>
#   conflict|<head sha>  pending|<why>  eligible|<lines>|<files>|<proof>
# Tests/fast_lane/test_fast_lane.sh sources this file and feeds `decide` fixtures.
#
# Usage: scripts/fast-lane.sh [--dry-run] [PR ...]   (no PR: every open fast-lane PR)
# --dry-run prints the decision and makes no API writes. Needs gh and jq.
set -euo pipefail

# Logins as `gh pr view --json author` reports them. Cloud Claude Code sessions
# open PRs with the captain's own GitHub token, so they appear as prakashUXtech.
FAST_LANE_AUTHORS="prakashUXtech"
MAX_LINES=400
MAX_FILES=15
# Belt PRs wait for Belt's pre-merge review: the `belt/review` commit status on
# the head must be success (missing or pending waits, failure is red). Not a
# ruleset-required check, since merge-queue group commits would never get it.
# Set to 0 to turn the gate off if Belt's reviewer misbehaves.
REQUIRE_BELT_REVIEW=0
BELT_REVIEW_CONTEXT="belt/review"
BASE_BRANCH="${FAST_LANE_BASE:-dev}"
LABEL="fast-lane"
MERGED_LABEL="fast-lane-merged"
FEATURE_LABEL="feature-done"  # merging one dispatches full CI on BASE_BRANCH
CI_WORKFLOWS=("CI")
# CI job names, so CI runs started by workflow_dispatch (no PR association) still count.
CI_CHECKS=("Linux" "macOS" "Mutation anchors" "Mutation")
CI_FILE="ci.yml"  # the CI workflow file, dispatched on BASE_BRANCH after merges
SELF_WORKFLOW="Fast Lane"
# The lane job's own check run on the head. Check runs read off the commit carry
# no workflow name, so the lane drops its own (running) check by this name.
SELF_CHECK="fast-lane"
# PROTECTED is exactly the backticked paths in CLAUDE.md's "**Never edit**"
# bullet; Tests/fast_lane checks the two match. A path ending in / is that
# folder at the root, a path with a / is that file, and a bare name is that
# file in any folder (docs/AGENTS.md too). Matching ignores case.
# docs/c4/model.json is generated on dev from docs/c4/parts/ by scripts/c4-assemble
# (.github/workflows/generated.yml), so PRs never edit it, nor its generator.
PROTECTED=(Package.swift Package.resolved .github/ .claude/ scripts/ci scripts/cloud-setup.sh
  scripts/fast-lane.sh scripts/mutate scripts/c4-assemble CLAUDE.md AGENTS.md LICENSE
  docs/c4/model.json)
deny_re() {
  local p re=""
  for p in "${PROTECTED[@]}"; do
    p="${p//./\\.}"
    case "$p" in */) p="^$p" ;; */*) p="^$p\$" ;; *) p="(^|/)$p\$" ;; esac
    re+="${re:+|}$p"
  done
  echo "$re"
}
DENY_RE=$(deny_re)

# The worker's proof that scripts/ci passed on the head: this line, then `Head: <sha>`.
MARKER_LINE="Fast-Check: pass"
HEAD_LINE="Head: "

REPO="${GH_REPO:-qbtrix/creative-core}"
DRY_RUN=0
MERGED_ANY=0
DISPATCH_FEATURE=0  # merged a FEATURE_LABEL PR this run
MERGED_RUN=0        # PRs merged this run
DISPATCH_EVERY=10   # dispatch once the base holds this many merged PRs since the last CI run
# GitHub recomputes `mergeable` lazily after any push to the base branch and
# reports UNKNOWN meanwhile. Re-read the PR this many times, 5s apart, before
# calling it not ready; otherwise a PR checked right after another merge stalls.
UNKNOWN_RETRIES="${FAST_LANE_UNKNOWN_RETRIES:-8}"

# Drops AI attribution lines (co-author trailers, session links, "Generated with" footers).
strip_attribution() {
  grep -v -i -E '^[[:space:]]*(co-authored-by:.*(claude|anthropic)|claude-session:|_?generated (with|by) \[?claude)' || true
}

log() { printf '  %s\n' "$*" >&2; }

# has_marker <pr.json> <head sha>: the body has the line MARKER_LINE directly
# followed by `Head: <head sha>`, each compared after trimming spaces (Belt's
# verdict parsing). A marker for an older head does not count.
has_marker() {
  jq -r '.body // ""' "$1" | tr -d '\r' | awk -v mark="$MARKER_LINE" -v head="$HEAD_LINE$2" '
    { sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
    prev == mark && $0 == head { found = 1 }
    { prev = $0 }
    END { exit !found }'
}

# decide <pr.json> <files.txt> <checks.json>
decide() {
  local pr="$1" files="$2" checks="$3"
  local state draft base has_label author adds dels nfiles lines mergeable mstate head
  state=$(jq -r '.state' "$pr")
  draft=$(jq -r '.isDraft' "$pr")
  base=$(jq -r '.baseRefName' "$pr")
  has_label=$(jq -r --arg l "$LABEL" '[.labels[]?.name] | index($l) != null' "$pr")
  author=$(jq -r '.author.login' "$pr")
  adds=$(jq -r '.additions' "$pr")
  dels=$(jq -r '.deletions' "$pr")
  nfiles=$(jq -r '.changedFiles' "$pr")
  mergeable=$(jq -r '.mergeable' "$pr")
  mstate=$(jq -r '.mergeStateStatus' "$pr")
  head=$(jq -r '.headRefOid' "$pr")
  lines=$((adds + dels))

  local skip="" retarget="" reasons=() pending="" red="" ngreen=0 review=""

  log "state=$state draft=$draft base=$base label=$has_label"
  [[ "$state" == "OPEN" ]] || skip="PR is $state"
  [[ -n "$skip" || "$draft" != "true" ]] || skip="PR is a draft"
  [[ -n "$skip" || "$has_label" == "true" ]] || skip="no $LABEL label"
  if [[ -z "$skip" && "$base" != "$BASE_BRANCH" ]]; then
    if [[ "$base" == "main" ]]; then retarget="$base"; else skip="base is $base, not $BASE_BRANCH"; fi
  fi

  if [[ " $FAST_LANE_AUTHORS " == *" $author "* ]]; then
    log "author: ok ($author)"
  else
    log "author: FAIL ($author)"; reasons+=("author $author is not on the fast-lane allowlist")
  fi
  if (( lines <= MAX_LINES && nfiles <= MAX_FILES )); then
    log "size: ok ($lines lines, $nfiles files)"
  else
    log "size: FAIL ($lines lines, $nfiles files)"
    reasons+=("too big: $lines lines, $nfiles files (max $MAX_LINES lines, $MAX_FILES files)")
  fi
  local denied
  denied=$(grep -Ei -- "$DENY_RE" "$files" | paste -sd, - || true)
  if [[ -z "$denied" ]]; then
    log "paths: ok"
  else
    log "paths: FAIL ($denied)"; reasons+=("touches protected paths: ${denied//,/, }")
  fi

  local conflict=0
  if [[ "$mergeable" == "MERGEABLE" && ! "$mstate" =~ ^(DIRTY|UNKNOWN|BLOCKED|DRAFT)$ ]]; then
    log "mergeable: ok ($mstate)"
  elif [[ "$mergeable" == "CONFLICTING" ]]; then
    log "mergeable: CONFLICTING ($mstate)"; conflict=1
  else
    log "mergeable: not ready ($mergeable/$mstate)"; pending="not mergeable yet ($mergeable/$mstate)"
  fi

  # Belt's review status is judged on its own below, and only for Belt PRs.
  local belt=0
  if (( REQUIRE_BELT_REVIEW )) && jq -r '.body // ""' "$pr" | grep -qE '^[[:space:]]*Belt-(Run|Test):'; then
    belt=1
    review=$(jq -r --arg c "$BELT_REVIEW_CONTEXT" \
      '[.[] | select((.context // .name // "") == $c) | (.state // .conclusion // "")][0] // "MISSING"' "$checks")
    log "belt review: $review"
  fi

  # Drop our own check, Belt's review and Copilot review checks, then classify the rest.
  local ci_json summary
  ci_json=$(printf '%s\n' "${CI_WORKFLOWS[@]}" "${CI_CHECKS[@]}" | jq -R . | jq -s .)
  summary=$(jq -c --arg self "$SELF_WORKFLOW" --arg selfcheck "$SELF_CHECK" \
      --arg review "$BELT_REVIEW_CONTEXT" --argjson ci "$ci_json" '
    [ .[]
      | select((.workflowName // "") != $self and (.name // "") != $selfcheck)
      | select((.context // .name // "") != $review)
      | select(((.name // .context // "") + " " + (.workflowName // "")) | test("copilot"; "i") | not)
      | { name: (.name // .context),
          wf: (.workflowName // ""),
          s: (if .__typename == "StatusContext" then
                (if .state == "SUCCESS" then "ok"
                 elif (.state == "PENDING" or .state == "EXPECTED") then "pending"
                 else "red" end)
              elif .status != "COMPLETED" then "pending"
              elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "ok"
              else "red" end) } ]
    | { red: [ .[] | select(.s == "red") | .name ],
        pending: [ .[] | select(.s == "pending") | .name ],
        green: ([ .[] | select(.s == "ok") ] | length),
        ci_passed: ([ .[] | select(.s == "ok" and ((.wf as $w | $ci | index($w) != null) or (.name as $n | $ci | index($n) != null))) ] | length) }' "$checks")
  red=$(jq -r '.red | join(", ")' <<<"$summary")
  ngreen=$(jq -r '.green' <<<"$summary")
  local npending nci marker=0
  npending=$(jq -r '.pending | length' <<<"$summary")
  nci=$(jq -r '.ci_passed' <<<"$summary")
  if has_marker "$pr" "$head"; then marker=1; fi
  # ponytail: "CI passed" = at least one *passing* check from CI_WORKFLOWS, so a
  # head where every CI job was skipped still needs the worker's marker.
  log "checks: green=$ngreen pending=$npending red=[${red}] ci_passed=$nci marker=$marker"

  if [[ -n "$skip" ]]; then echo "skip|$skip"; return; fi
  if [[ -n "$retarget" ]]; then echo "retarget|$retarget"; return; fi
  if (( ${#reasons[@]} )); then
    local IFS=';'; echo "not-eligible|${reasons[*]}"; return
  fi
  if [[ -n "$red" ]]; then echo "red|$red"; return; fi
  if (( belt )) && [[ "$review" =~ ^(FAILURE|ERROR)$ ]]; then echo "red|review failed"; return; fi
  if (( conflict )); then echo "conflict|$head"; return; fi
  if [[ -n "$pending" ]]; then echo "pending|$pending"; return; fi
  if (( npending )); then echo "pending|$npending checks still running"; return; fi
  if (( nci == 0 && marker == 0 )); then
    echo "pending|no passing CI check and no $MARKER_LINE marker for head $head"; return
  fi
  if (( belt )) && [[ "$review" != "SUCCESS" ]]; then echo "pending|waiting for review"; return; fi
  local proof="Fast-Check marker"
  (( nci == 0 )) || proof="$ngreen checks green"
  echo "eligible|$lines|$nfiles|$proof"
}

write() {  # run a mutating command unless --dry-run
  if (( DRY_RUN )); then log "dry-run, would: $*"; else "$@"; fi
}

comment_once() {  # comment unless an identical comment already exists
  local n="$1" body="$2"
  local existing
  existing=$(gh api "repos/$REPO/issues/$n/comments" --paginate --jq '.[].body')
  if grep -Fxq -- "$body" <<<"$existing"; then
    log "comment already present, not repeating"
    return
  fi
  write gh pr comment "$n" -R "$REPO" --body "$body"
}

evaluate() {
  local n="$1" tmp
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "fast-lane: bad PR number: $n" >&2; return 1; }
  tmp=$(mktemp -d)
  local tries=0
  while :; do
    gh pr view "$n" -R "$REPO" --json number,state,isDraft,baseRefName,labels,author,body,additions,deletions,changedFiles,mergeable,mergeStateStatus,headRefOid,headRefName,statusCheckRollup >"$tmp/pr.json"
    [[ "$(jq -r '.mergeable' "$tmp/pr.json")" == "UNKNOWN" ]] || break
    (( tries++ < UNKNOWN_RETRIES )) || break
    sleep 5
  done
  # Read check runs off the head commit itself, newest per name. The PR's rollup
  # misses CI dispatched on the branch, and keeps the PR-event run that GitHub
  # parks as action_required for bot pushes.
  local head
  head=$(jq -r '.headRefOid' "$tmp/pr.json")
  if gh api "repos/$REPO/commits/$head/check-runs?per_page=100" --jq '.check_runs' >"$tmp/runs.json" 2>/dev/null; then
    jq '[ group_by(.name)[] | sort_by(.started_at // "") | last
          | select(.conclusion != "action_required")
          | { __typename: "CheckRun", name, status: (.status | ascii_upcase),
              conclusion: ((.conclusion // "") | ascii_upcase), workflowName: "" } ]' \
      "$tmp/runs.json" >"$tmp/checks.json"
    # Check runs carry no commit statuses; add Belt's review status from the head.
    gh api "repos/$REPO/commits/$head/status" --jq "[.statuses[] | select(.context == \"$BELT_REVIEW_CONTEXT\")
      | {__typename: \"StatusContext\", context, state: (.state | ascii_upcase)}]" \
      >"$tmp/status.json" 2>/dev/null || echo '[]' >"$tmp/status.json"
    jq -s 'add' "$tmp/checks.json" "$tmp/status.json" >"$tmp/all.json" && mv "$tmp/all.json" "$tmp/checks.json"
  else
    jq '.statusCheckRollup // []' "$tmp/pr.json" >"$tmp/checks.json"
  fi
  # A rename counts under both names, so moving a protected file away is caught.
  gh api "repos/$REPO/pulls/$n/files" --paginate --jq '.[] | .filename, (.previous_filename // empty)' >"$tmp/files.txt"

  echo "PR #$n:" >&2
  local decision kind rest
  decision=$(decide "$tmp/pr.json" "$tmp/files.txt" "$tmp/checks.json")
  echo "decision: $decision"
  kind="${decision%%|*}"; rest="${decision#*|}"

  case "$kind" in
    skip|pending) ;;
    retarget)
      # mergeable goes UNKNOWN after the edit; the next sweep evaluates it on the new base.
      if write gh pr edit "$n" -R "$REPO" --base "$BASE_BRANCH"; then
        comment_once "$n" "Fast lane: retargeted from $rest to $BASE_BRANCH. Crew PRs merge into $BASE_BRANCH; $rest only takes $BASE_BRANCH heads whose full CI is green."
      else
        log "could not retarget to $BASE_BRANCH"
      fi
      ;;
    conflict)
      # Usually an earlier merge in this sweep. Belt's fixer rebases it; the label stays.
      comment_once "$n" "Fast lane: not merged, this PR conflicts with $BASE_BRANCH at head $rest. Rebase on origin/$BASE_BRANCH, rerun scripts/ci, and update the Fast-Check marker."
      ;;
    not-eligible)
      write gh pr edit "$n" -R "$REPO" --remove-label "$LABEL" || log "could not remove label"
      comment_once "$n" "Fast lane: not eligible. ${rest//;/; }. This PR now needs normal captain review."
      ;;
    red)
      if [[ "$rest" == "review failed" ]]; then
        comment_once "$n" "Fast lane: waiting, Belt's review failed ($BELT_REVIEW_CONTEXT is failure on the head)."
      else
        comment_once "$n" "Fast lane: waiting, CI is red ($rest)"
      fi
      ;;
    eligible)
      local lines files proof
      IFS='|' read -r lines files proof <<<"$rest"
      # Squash message = PR title + body, minus any AI attribution lines.
      local title body
      title=$(gh pr view "$n" -R "$REPO" --json title --jq .title)
      body=$(gh pr view "$n" -R "$REPO" --json body --jq .body | strip_attribution)
      # Cloud sessions append a "Generated by Claude Code" footer to the PR body; drop it there too.
      write gh pr edit "$n" -R "$REPO" --body "$body" || log "could not strip attribution from the PR body"
      # A failed merge (head moved, or the base changed under it) is left for the next sweep.
      if ! write gh pr merge "$n" -R "$REPO" --squash --delete-branch=false --match-head-commit "$head" \
          --subject "$title (#$n)" --body "$body"; then
        log "merge failed; the next sweep looks again"; rm -rf "$tmp"; return
      fi
      MERGED_ANY=1
      MERGED_RUN=$((MERGED_RUN + 1))
      # GITHUB_TOKEN merges fire no workflows; a finished feature gets its full CI run.
      if jq -e --arg l "$FEATURE_LABEL" '[.labels[]?.name] | index($l) != null' "$tmp/pr.json" >/dev/null; then
        DISPATCH_FEATURE=1
      fi
      # GitHub does not auto-close linked issues when GITHUB_TOKEN merges, so close them here.
      local issue
      for issue in $(gh pr view "$n" -R "$REPO" --json closingIssuesReferences --jq '.closingIssuesReferences[].number'); do
        write gh issue close "$issue" -R "$REPO" --reason completed --comment "Done in #$n (fast lane)." || log "could not close #$issue"
        write gh issue edit "$issue" -R "$REPO" --remove-label in-progress || true
      done
      write gh pr edit "$n" -R "$REPO" --add-label "$MERGED_LABEL" || log "could not add $MERGED_LABEL label"
      comment_once "$n" "Fast lane: merged into $BASE_BRANCH ($lines lines, $files files, $proof)."
      ;;
  esac
  rm -rf "$tmp"
}

# dispatch_reason <feature 0|1> <merged PRs since the last CI run, or empty when
# unknown>: why CI on the base should run now, nothing when it shouldn't. Pure,
# so the self-tests can call it.
dispatch_reason() {
  if (( $1 )); then echo "merged a $FEATURE_LABEL PR"; return; fi
  if [[ "$2" =~ ^[0-9]+$ ]] && (( $2 >= DISPATCH_EVERY )); then echo "$2 merged PRs since the last CI run"; fi
}

# merges_since_ci: the merged PRs (squash subjects ending in `(#n)`) on the base
# since the head of its latest CI run, any status. A base with no CI run counts
# as DISPATCH_EVERY; an API failure prints nothing, so the count rule waits.
merges_since_ci() {
  local sha
  sha=$(gh run list -R "$REPO" --workflow "$CI_FILE" --branch "$BASE_BRANCH" --limit 1 --json headSha --jq '.[0].headSha // ""') || return 0
  if [[ -z "$sha" ]]; then echo "$DISPATCH_EVERY"; return; fi
  gh api "repos/$REPO/compare/$sha...$BASE_BRANCH" \
    --jq '[.commits[] | select(.commit.message | split("\n")[0] | test("\\(#[0-9]+\\)$"))] | length' || true
}

# Open fast-lane PRs on any base, oldest first (decide retargets main and skips the rest).
open_prs() {
  gh pr list -R "$REPO" --state open --label "$LABEL" --limit 100 --json number --jq '.[].number' | sort -n
}

main() {
  local prs=()
  while (( $# )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      -h|--help) sed -n '2,48p' "$0"; return 0 ;;
      *) prs+=("$1") ;;
    esac
    shift
  done
  if (( ${#prs[@]} == 0 )); then
    while read -r n; do [[ -n "$n" ]] && prs+=("$n"); done < <(open_prs)
  fi
  (( ${#prs[@]} )) || { echo "fast-lane: no open $LABEL PRs" >&2; return 0; }
  local n pass
  for n in "${prs[@]}"; do evaluate "$n"; done
  # A merge changes every other PR's mergeable state, and GitHub reports
  # UNKNOWN until it recomputes. Sweep again after any merge, until a pass
  # merges nothing, so a PR that settles late still merges in this run.
  for (( pass = 0; MERGED_ANY && pass < 5; pass++ )); do
    MERGED_ANY=0
    while read -r n; do [[ -n "$n" ]] && evaluate "$n"; done < <(open_prs)
  done
  # At most one dispatch per run, and only after a run that merged something.
  (( MERGED_RUN )) || return 0
  local since="" why
  (( DISPATCH_FEATURE )) || since=$(merges_since_ci)
  why=$(dispatch_reason "$DISPATCH_FEATURE" "$since")
  if [[ -n "$why" ]]; then
    log "dispatching CI on $BASE_BRANCH: $why"
    write gh workflow run "$CI_FILE" -R "$REPO" --ref "$BASE_BRANCH" || log "could not dispatch CI on $BASE_BRANCH"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
