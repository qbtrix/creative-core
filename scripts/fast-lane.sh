#!/usr/bin/env bash
# scripts/fast-lane.sh: put small, green crew PRs into GitHub's merge queue on
# BASE_BRANCH without captain review. The queue tests them on top of main in
# groups and merges them; the captain batch-reviews merged fast-lane PRs later.
# Agent rules: CLAUDE.md, "Fast lane". Run by .github/workflows/fast-lane.yml
# from trusted main: it only reads PR metadata through the GitHub API and never
# checks out or runs PR code.
#
# Eligible (all must hold): open, not draft, base BASE_BRANCH, label `fast-lane`,
# not queued, author in FAST_LANE_AUTHORS, within MAX_LINES/MAX_FILES, no path
# matching DENY_RE, no AI attribution in commit messages (the queue squashes
# them into main), mergeable, every check green with a passing CI_WORKFLOWS
# check (none fails closed), not removed from the queue since its head's CI ran,
# base head CI not red, and a merge queue on the base. The lane strips
# attribution from the PR body and enqueues the PR at the judged head.
#
# GITHUB_TOKEN enqueues fire no merge_group workflow, so each run also
# dispatches CI on lane-queued groups with no run (kick_queue) and closes the
# linked issues of merged fast-lane PRs (sweep_merged).
#
# `decide` is the pure decision function (no network): PR JSON (gh pr view
# fields plus .mq = {enabled, inQueue}), file list, check rollup, base CI health
# (green|red), queue removal reason ("" = none). It logs each rule to stderr and
# prints one of: skip|why  not-eligible|reasons  pending|why  red|checks
# dequeued|reason  eligible|lines|files|green. Tests/fast_lane/ feeds it fixtures.
#
# Usage: scripts/fast-lane.sh [--dry-run] [PR ...]   (no PR: every open fast-lane PR)
#        scripts/fast-lane.sh [--dry-run] --sha SHA  (open fast-lane PRs at head SHA,
#        else every one). --dry-run makes no API writes. Needs gh and jq.
set -euo pipefail

# Logins as `gh pr view --json author` reports them. Cloud Claude Code sessions
# open PRs with the captain's own GitHub token, so they appear as prakashUXtech.
FAST_LANE_AUTHORS="prakashUXtech"
MAX_LINES=400
MAX_FILES=15
BASE_BRANCH="${FAST_LANE_BASE:-main}"
LABEL="fast-lane"
MERGED_LABEL="fast-lane-merged"
CI_WORKFLOWS=("CI")
# CI job names, so CI runs started by workflow_dispatch (no PR association) still count.
CI_CHECKS=("Linux" "macOS")
CI_FILE="ci.yml"  # the CI workflow file, for run lookups and dispatch
SELF_WORKFLOW="Fast Lane"
DENY_RE='^\.github/|^\.claude/|(^|/)(CLAUDE|AGENTS)\.md$|^scripts/(ci|cloud-setup\.sh|fast-lane\.sh)$|(^|/)Package\.(swift|resolved)$|^LICENSE'
# AI attribution lines: co-author trailers, session links, "Generated with" footers.
ATTRIBUTION_RE='^[[:space:]]*(co-authored-by:.*(claude|anthropic)|claude-session:|_?generated (with|by) \[?claude)'

REPO="${GH_REPO:-qbtrix/creative-core}"
DRY_RUN=0
ENQUEUED_ANY=0
MAIN_HEALTH=green
MAIN_RED_URL=""
# GitHub recomputes `mergeable` lazily after any push to the base branch and
# reports UNKNOWN meanwhile. Re-read the PR this many times, 5s apart, before
# calling it not ready; otherwise a PR checked right after a merge stalls.
UNKNOWN_RETRIES="${FAST_LANE_UNKNOWN_RETRIES:-8}"

strip_attribution() { grep -v -i -E "$ATTRIBUTION_RE" || true; }

log() { printf '  %s\n' "$*" >&2; }

# decide <pr.json> <files.txt> <checks.json> <main health> <dequeued reason>
decide() {
  local pr="$1" files="$2" checks="$3" main_health="$4" dequeued="$5"
  local state draft base has_label author adds dels nfiles lines mergeable mstate in_queue mq_enabled
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
  in_queue=$(jq -r '.mq.inQueue // false' "$pr")
  mq_enabled=$(jq -r '.mq.enabled // false' "$pr")
  lines=$((adds + dels))

  local skip="" reasons=() pending="" red="" ngreen=0

  log "state=$state draft=$draft base=$base label=$has_label queued=$in_queue"
  [[ "$state" == "OPEN" ]] || skip="PR is $state"
  [[ -n "$skip" || "$draft" != "true" ]] || skip="PR is a draft"
  [[ -n "$skip" || "$base" == "$BASE_BRANCH" ]] || skip="base is $base, not $BASE_BRANCH"
  [[ -n "$skip" || "$has_label" == "true" ]] || skip="no $LABEL label"
  [[ -n "$skip" || "$in_queue" != "true" ]] || skip="already in the merge queue"

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
  # The queue squashes commit messages into main, so attribution there would land.
  if jq -r '.commits[]? | .messageHeadline, .messageBody' "$pr" | grep -qi -E -- "$ATTRIBUTION_RE"; then
    log "commits: FAIL (AI attribution)"
    reasons+=("a commit message carries AI attribution, which the merge queue would squash into main")
  else
    log "commits: ok"
  fi

  # BLOCKED is not a stop: under a merge-queue ruleset a green PR can report it
  # until queued. Red, running and missing checks are judged from the rollup below.
  if [[ "$mergeable" == "MERGEABLE" && ! "$mstate" =~ ^(DIRTY|UNKNOWN|DRAFT)$ ]]; then
    log "mergeable: ok ($mstate)"
  else
    log "mergeable: not ready ($mergeable/$mstate)"; pending="not mergeable yet ($mergeable/$mstate)"
  fi

  # Drop our own check and Copilot review checks, then classify the rest.
  local ci_json summary
  ci_json=$(printf '%s\n' "${CI_WORKFLOWS[@]}" "${CI_CHECKS[@]}" | jq -R . | jq -s .)
  summary=$(jq -c --arg self "$SELF_WORKFLOW" --argjson ci "$ci_json" '
    [ .[]
      | select((.workflowName // "") != $self)
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
  local npending nci
  npending=$(jq -r '.pending | length' <<<"$summary")
  nci=$(jq -r '.ci_passed' <<<"$summary")
  # ponytail: "required CI exists" = at least one *passing* check from CI_WORKFLOWS,
  # so a head where every CI job was skipped still fails closed.
  log "checks: green=$ngreen pending=$npending red=[${red}] ci_passed=$nci"

  if [[ -n "$skip" ]]; then echo "skip|$skip"; return; fi
  if (( ${#reasons[@]} )); then
    local IFS=';'; echo "not-eligible|${reasons[*]}"; return
  fi
  if [[ -n "$red" ]]; then echo "red|$red"; return; fi
  if [[ -n "$pending" ]]; then echo "pending|$pending"; return; fi
  if (( npending )); then echo "pending|$npending checks still running"; return; fi
  if (( nci == 0 )); then local IFS=,; echo "pending|no passing check from ${CI_WORKFLOWS[*]} yet"; return; fi
  # A PR the queue removed (failed group CI, manual removal) stays out until its
  # head changes; re-adding it every sweep would loop or undo a human's call.
  if [[ -n "$dequeued" ]]; then echo "dequeued|$dequeued"; return; fi
  log "main: $main_health, merge queue: $mq_enabled"
  # A red main fails every group the queue builds, so hold until it is green.
  if [[ "$main_health" == "red" ]]; then echo "pending|main is red"; return; fi
  if [[ "$mq_enabled" != "true" ]]; then echo "pending|no merge queue on $BASE_BRANCH"; return; fi
  echo "eligible|$lines|$nfiles|$ngreen"
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

gql() {  # gql <query> [gh api -F/-f args...]: GraphQL against REPO's owner/name
  local q="$1"; shift
  gh api graphql -f owner="${REPO%/*}" -f name="${REPO#*/}" -f query="$q" "$@"
}

# Sets MAIN_HEALTH to red when the newest finished CI run on the base head
# failed, else green. No run yet, or one still going, is green: the queue tests
# every group on top of the base anyway.
main_health() {
  local last
  last=$(gh run list -R "$REPO" --workflow "$CI_FILE" --commit "$1" --limit 10 \
    --json conclusion,status,url \
    --jq '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped")][0] // empty')
  MAIN_HEALTH=green
  if [[ -n "$last" && "$(jq -r .conclusion <<<"$last")" != "success" ]]; then
    MAIN_HEALTH=red; MAIN_RED_URL=$(jq -r .url <<<"$last")
  fi
}

# dequeue_reason <removed at> <reason> <newest head CI run created at>: prints
# the reason when the queue removed the PR after its head's newest CI run was
# created, i.e. this same head was already tried. A push starts a new CI run
# and clears it. No CI run at all fails closed.
dequeue_reason() {
  local removed_at="$1" reason="$2" ci_at="$3"
  [[ -n "$removed_at" && "$reason" != "merged" ]] || return 0
  if [[ -z "$ci_at" || "$removed_at" > "$ci_at" ]]; then echo "${reason:-removed}"; fi
}

evaluate() {
  local n="$1" tmp
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "fast-lane: bad PR number: $n" >&2; return 1; }
  tmp=$(mktemp -d)
  local tries=0
  while :; do
    gh pr view "$n" -R "$REPO" --json number,state,isDraft,baseRefName,labels,author,additions,deletions,changedFiles,mergeable,mergeStateStatus,headRefOid,statusCheckRollup,commits >"$tmp/pr.json"
    [[ "$(jq -r '.state + .mergeable' "$tmp/pr.json")" == "OPENUNKNOWN" ]] || break
    (( tries++ < UNKNOWN_RETRIES )) || break
    sleep 5
  done
  # Merge-queue state is GraphQL-only: queue on/off, queued now, last removal.
  gql 'query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){pullRequest(number:$n){
      id isInMergeQueue isMergeQueueEnabled
      timelineItems(last:1,itemTypes:[REMOVED_FROM_MERGE_QUEUE_EVENT]){nodes{... on RemovedFromMergeQueueEvent{createdAt reason}}}}}}' \
    -F n="$n" --jq '.data.repository.pullRequest
      | {id, enabled: .isMergeQueueEnabled, inQueue: .isInMergeQueue, removed: (.timelineItems.nodes[0] // null)}' >"$tmp/mq.json"
  jq --slurpfile mq "$tmp/mq.json" '.mq = $mq[0]' "$tmp/pr.json" >"$tmp/pr2.json" && mv "$tmp/pr2.json" "$tmp/pr.json"
  # Read check runs off the head commit itself, newest per name, skipping runs
  # GitHub parks as action_required for bot pushes.
  local head
  head=$(jq -r '.headRefOid' "$tmp/pr.json")
  if gh api "repos/$REPO/commits/$head/check-runs?per_page=100" --jq '.check_runs' >"$tmp/runs.json" 2>/dev/null; then
    jq '[ group_by(.name)[] | sort_by(.started_at // "") | last
          | select(.conclusion != "action_required")
          | { __typename: "CheckRun", name, status: (.status | ascii_upcase),
              conclusion: ((.conclusion // "") | ascii_upcase), workflowName: "" } ]' \
      "$tmp/runs.json" >"$tmp/checks.json"
  else
    jq '.statusCheckRollup // []' "$tmp/pr.json" >"$tmp/checks.json"
  fi
  gh api "repos/$REPO/pulls/$n/files" --paginate --jq '.[].filename' >"$tmp/files.txt"

  local removed_at reason ci_at="" dequeued
  removed_at=$(jq -r '.mq.removed.createdAt // ""' "$tmp/pr.json")
  reason=$(jq -r '.mq.removed.reason // ""' "$tmp/pr.json")
  if [[ -n "$removed_at" && "$reason" != "merged" ]]; then
    ci_at=$(gh run list -R "$REPO" --workflow "$CI_FILE" --commit "$head" --limit 20 \
      --json createdAt --jq '[.[].createdAt] | max // ""')
  fi
  dequeued=$(dequeue_reason "$removed_at" "$reason" "$ci_at")

  echo "PR #$n:" >&2
  local decision kind rest
  decision=$(decide "$tmp/pr.json" "$tmp/files.txt" "$tmp/checks.json" "$MAIN_HEALTH" "$dequeued")
  echo "decision: $decision"
  kind="${decision%%|*}"; rest="${decision#*|}"

  case "$kind" in
    skip) ;;
    pending)
      [[ "$rest" != "main is red" ]] || comment_once "$n" "Fast lane: waiting, main is red ($MAIN_RED_URL)"
      ;;
    not-eligible)
      write gh pr edit "$n" -R "$REPO" --remove-label "$LABEL" || log "could not remove label"
      comment_once "$n" "Fast lane: not eligible. ${rest//;/; }. This PR now needs normal captain review."
      ;;
    red)
      comment_once "$n" "Fast lane: waiting, CI is red ($rest)"
      ;;
    dequeued)
      comment_once "$n" "Fast lane: the merge queue removed this PR ($rest). Push a fix to try again."
      ;;
    eligible)
      local lines files green body id
      IFS='|' read -r lines files green <<<"$rest"
      id=$(jq -r '.mq.id' "$tmp/pr.json")
      # Cloud sessions append a "Generated by Claude Code" footer to the PR body; drop it.
      body=$(gh pr view "$n" -R "$REPO" --json body --jq .body | strip_attribution)
      write gh pr edit "$n" -R "$REPO" --body "$body" || log "could not strip attribution from the PR body"
      # enqueuePullRequest, not `gh pr merge --auto`: gh routes a queued merge through
      # enablePullRequestAutoMerge, which fails while repo auto-merge is off.
      # expectedHeadOid refuses the enqueue if the head moved since it was judged.
      if write gql 'mutation($id:ID!,$sha:GitObjectID!){enqueuePullRequest(input:{pullRequestId:$id,expectedHeadOid:$sha}){mergeQueueEntry{position}}}' \
          -f id="$id" -f sha="$head" --jq '.data.enqueuePullRequest.mergeQueueEntry.position' >&2; then
        ENQUEUED_ANY=1
        comment_once "$n" "Fast lane: queued ($lines lines, $files files, $green checks green). The merge queue tests it on top of $BASE_BRANCH and merges it."
      else
        log "could not enqueue #$n"
      fi
      ;;
  esac
  rm -rf "$tmp"
}

# Dispatch CI on queue groups the lane enqueued that have no CI run. A
# GITHUB_TOKEN enqueue fires no merge_group workflow, and the queue waits for
# the required checks on each group's head commit; workflow_dispatch is the one
# trigger GITHUB_TOKEN may fire. Groups queued by a person get merge_group runs.
kick_queue() {
  local shas refs sha ref
  shas=$(gql 'query($owner:String!,$name:String!,$b:String!){repository(owner:$owner,name:$name){mergeQueue(branch:$b){entries(first:100){nodes{enqueuer{login} headCommit{oid}}}}}}' \
    -f b="$BASE_BRANCH" --jq '.data.repository.mergeQueue.entries.nodes[]?
      | select(.enqueuer.login | test("^github-actions")) | .headCommit.oid // empty')
  [[ -n "$shas" ]] || return 0
  refs=$(gh api "repos/$REPO/git/matching-refs/heads/gh-readonly-queue/$BASE_BRANCH/" --jq '.[] | "\(.object.sha) \(.ref)"')
  for sha in $shas; do
    ref=$(awk -v s="$sha" '$1 == s { sub("^refs/heads/", "", $2); print $2; exit }' <<<"$refs")
    [[ -n "$ref" ]] || continue
    if [[ "$(gh run list -R "$REPO" --workflow "$CI_FILE" --commit "$sha" --limit 1 --json databaseId --jq length)" == "0" ]]; then
      log "queue group $ref has no CI run; dispatching"
      write gh workflow run "$CI_FILE" -R "$REPO" --ref "$ref" || log "could not dispatch CI on $ref"
    fi
  done
}

# Close the linked issues of merged fast-lane PRs and mark them done. Idempotent:
# the fast-lane-merged label is the marker, whoever did the merge.
sweep_merged() {
  local n issue
  for n in $(gh pr list -R "$REPO" --state merged --base "$BASE_BRANCH" --label "$LABEL" --limit 20 \
      --json number,labels --jq ".[] | select([.labels[].name] | index(\"$MERGED_LABEL\") | not) | .number"); do
    log "PR #$n merged; closing its linked issues"
    for issue in $(gh pr view "$n" -R "$REPO" --json closingIssuesReferences --jq '.closingIssuesReferences[].number'); do
      write gh issue close "$issue" -R "$REPO" --reason completed --comment "Done in #$n (fast lane)." || log "could not close #$issue"
      write gh issue edit "$issue" -R "$REPO" --remove-label in-progress || true
    done
    write gh pr edit "$n" -R "$REPO" --add-label "$MERGED_LABEL" || log "could not add $MERGED_LABEL label"
  done
}

main() {
  local sha="" prs=()
  while (( $# )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --sha) sha="${2:?--sha needs a value}"; shift ;;
      -h|--help) sed -n '2,29p' "$0"; return 0 ;;
      *) prs+=("$1") ;;
    esac
    shift
  done
  if (( ${#prs[@]} == 0 )); then
    local q='.[].number'
    [[ -n "$sha" ]] && q=".[] | select(.headRefOid == \"$sha\") | .number"
    [[ -z "$sha" || "$sha" =~ ^[0-9a-f]{7,40}$ ]] || { echo "fast-lane: bad sha" >&2; return 1; }
    while read -r n; do [[ -n "$n" ]] && prs+=("$n"); done < <(
      gh pr list -R "$REPO" --state open --base "$BASE_BRANCH" --label "$LABEL" \
        --limit 100 --json number,headRefOid --jq "$q" | sort -n)
    # A SHA no PR has (CI finished on main, or on a superseded head): sweep all.
    if [[ -n "$sha" && ${#prs[@]} -eq 0 ]]; then
      while read -r n; do [[ -n "$n" ]] && prs+=("$n"); done < <(
        gh pr list -R "$REPO" --state open --base "$BASE_BRANCH" --label "$LABEL" \
          --limit 100 --json number --jq '.[].number')
    fi
  fi
  if (( ${#prs[@]} )); then
    main_health "$(gh api "repos/$REPO/commits/$BASE_BRANCH" --jq .sha)"
    local n
    for n in "${prs[@]}"; do evaluate "$n"; done
  else
    echo "fast-lane: no matching open $LABEL PRs" >&2
  fi
  sweep_merged
  # The queue builds a group a few seconds after an enqueue; look twice.
  if (( ENQUEUED_ANY )); then sleep 15; kick_queue; sleep 15; fi
  kick_queue
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
