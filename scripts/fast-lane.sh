#!/usr/bin/env bash
# scripts/fast-lane.sh: merge small, green crew PRs into BASE_BRANCH without
# waiting for captain review. The captain batch-reviews merged fast-lane PRs
# later and reverts anything wrong. Rules for agents: CLAUDE.md, "Fast lane".
#
# Run by .github/workflows/fast-lane.yml from the trusted main branch. It only
# reads PR metadata through the GitHub API. It never checks out or runs PR code.
#
# Eligibility (all must hold): open, not draft, base BASE_BRANCH, label
# `fast-lane`, author in FAST_LANE_AUTHORS, size within MAX_LINES/MAX_FILES, no
# changed path matching DENY_RE, MERGEABLE, every check green with at least one
# passing check from CI_WORKFLOWS (no checks at all fails closed), CI on the
# base branch's head is green (not red, running, or missing), and the PR's CI
# ran after the base branch's latest commit. A Belt PR (a body line starting
# `Belt-Run:` or `Belt-Test:`) also needs Belt's `belt/review` commit status at
# success on its head while REQUIRE_BELT_REVIEW=1. A stale PR is refreshed:
# its branch is updated and CI is dispatched on it. Merges made with
# GITHUB_TOKEN fire no workflows, so after any merge (or when the base head has
# no CI run) the lane dispatches CI on the base branch; that run's completion
# re-triggers the lane.
#
# `decide` is the pure decision function (no network). It reads a PR JSON file,
# a file-list file (one path per line), a check-rollup JSON file, the base
# branch's CI health (green|red|running) and a freshness flag (true|false), logs
# each rule to stderr, and prints one line to stdout:
#   skip|<why>  not-eligible|<reasons>  pending|<why>  red|<checks>
#   eligible|<lines>|<files>|<green checks>
# Tests/fast_lane/test_fast_lane.sh sources this file and feeds `decide` fixtures.
#
# Usage: scripts/fast-lane.sh [--dry-run] [PR ...]   (no PR: every open fast-lane PR)
#        scripts/fast-lane.sh [--dry-run] --sha SHA  (open fast-lane PRs at head
#        SHA; if none matches, e.g. a CI run on main, every open fast-lane PR)
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
BASE_BRANCH="${FAST_LANE_BASE:-main}"
LABEL="fast-lane"
MERGED_LABEL="fast-lane-merged"
CI_WORKFLOWS=("CI")
# CI job names, so CI runs started by workflow_dispatch (no PR association) still count.
CI_CHECKS=("Linux" "macOS" "Mutation anchors" "Mutation")
CI_FILE="ci.yml"  # the CI workflow file, for run lookups and dispatch
SELF_WORKFLOW="Fast Lane"
DENY_RE='^\.github/|^\.claude/|(^|/)(CLAUDE|AGENTS)\.md$|^scripts/(ci|cloud-setup\.sh|fast-lane\.sh|mutate)$|(^|/)Package\.(swift|resolved)$|^LICENSE'

REPO="${GH_REPO:-qbtrix/flare-core}"
DRY_RUN=0
MERGED_ANY=0
DISPATCH_BASE_CI=0  # set when the base branch needs a CI run at the end
REFRESH_SLOT_TAKEN=0  # set once a stale PR is being refreshed this sweep
MAIN_RED_URL=""
# GitHub recomputes `mergeable` lazily after any push to the base branch and
# reports UNKNOWN meanwhile. Re-read the PR this many times, 5s apart, before
# calling it not ready; otherwise a PR checked right after another merge stalls.
UNKNOWN_RETRIES="${FAST_LANE_UNKNOWN_RETRIES:-8}"

# Drops AI attribution lines (co-author trailers, session links, "Generated with" footers).
strip_attribution() {
  grep -v -i -E '^[[:space:]]*(co-authored-by:.*(claude|anthropic)|claude-session:|_?generated (with|by) \[?claude)' || true
}

log() { printf '  %s\n' "$*" >&2; }

# decide <pr.json> <files.txt> <checks.json> <main health> <fresh>
decide() {
  local pr="$1" files="$2" checks="$3" main_health="$4" fresh="$5"
  local state draft base has_label author adds dels nfiles lines mergeable mstate
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
  lines=$((adds + dels))

  local skip="" reasons=() pending="" red="" ngreen=0 review=""

  log "state=$state draft=$draft base=$base label=$has_label"
  [[ "$state" == "OPEN" ]] || skip="PR is $state"
  [[ -n "$skip" || "$draft" != "true" ]] || skip="PR is a draft"
  [[ -n "$skip" || "$base" == "$BASE_BRANCH" ]] || skip="base is $base, not $BASE_BRANCH"
  [[ -n "$skip" || "$has_label" == "true" ]] || skip="no $LABEL label"

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

  if [[ "$mergeable" == "MERGEABLE" && ! "$mstate" =~ ^(DIRTY|UNKNOWN|BLOCKED|DRAFT)$ ]]; then
    log "mergeable: ok ($mstate)"
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
  summary=$(jq -c --arg self "$SELF_WORKFLOW" --arg review "$BELT_REVIEW_CONTEXT" --argjson ci "$ci_json" '
    [ .[]
      | select((.workflowName // "") != $self)
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
  if (( belt )) && [[ "$review" =~ ^(FAILURE|ERROR)$ ]]; then echo "red|review failed"; return; fi
  if [[ -n "$pending" ]]; then echo "pending|$pending"; return; fi
  if (( npending )); then echo "pending|$npending checks still running"; return; fi
  if (( nci == 0 )); then local IFS=,; echo "pending|no passing check from ${CI_WORKFLOWS[*]} yet"; return; fi
  if (( belt )) && [[ "$review" != "SUCCESS" ]]; then echo "pending|waiting for review"; return; fi
  log "main: $main_health, fresh: $fresh"
  if [[ "$main_health" == "red" ]]; then echo "pending|main is red"; return; fi
  if [[ "$main_health" != "green" ]]; then echo "pending|main CI running"; return; fi
  if [[ "$fresh" != "true" ]]; then echo "pending|refreshing against main"; return; fi
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

# Prints green|red|running for CI on the base branch's head. Sets MAIN_RED_URL.
# No run at all for the head (a GITHUB_TOKEN merge fires none) counts as
# running and asks for a dispatch at the end of this run.
main_health() {
  local head="$1" runs
  runs=$(gh run list -R "$REPO" --workflow "$CI_FILE" --branch "$BASE_BRANCH" --limit 5 \
    --json headSha,conclusion,status,url)
  if jq -e --arg h "$head" 'any(.[]; .headSha == $h and .status != "completed")' <<<"$runs" >/dev/null; then
    echo running; return
  fi
  if ! jq -e --arg h "$head" 'any(.[]; .headSha == $h)' <<<"$runs" >/dev/null; then
    DISPATCH_BASE_CI=1; echo running; return
  fi
  # Newest completed run, ignoring cancelled/skipped ones.
  local last
  last=$(jq -c '[.[] | select(.status == "completed" and .conclusion != "cancelled" and .conclusion != "skipped")][0] // empty' <<<"$runs")
  if [[ -n "$last" && "$(jq -r .conclusion <<<"$last")" != "success" ]]; then
    MAIN_RED_URL=$(jq -r .url <<<"$last"); echo red; return
  fi
  echo green
}

# fresh <head sha> <base head commit date>: true unless the newest successful CI
# run for the head was created before the base branch's latest commit.
fresh() {
  local created
  created=$(gh run list -R "$REPO" --workflow "$CI_FILE" --commit "$1" --limit 20 \
    --json createdAt,conclusion --jq '[.[] | select(.conclusion == "success") | .createdAt] | max // ""')
  # No successful run: the "no passing check" rule already holds the PR.
  if [[ -z "$created" || ! "$created" < "$2" ]]; then echo true; else echo false; fi
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
  # misses CI that the lane dispatched after refreshing a branch, and keeps the
  # PR-event run that GitHub parks as action_required for bot pushes.
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
  gh api "repos/$REPO/pulls/$n/files" --paginate --jq '.[].filename' >"$tmp/files.txt"

  local base_head base_date health is_fresh
  read -r base_head base_date < <(gh api "repos/$REPO/commits/$BASE_BRANCH" --jq '"\(.sha) \(.commit.committer.date)"')
  # Not in a $(...) subshell: main_health sets globals.
  main_health "$base_head" >"$tmp/health"
  health=$(<"$tmp/health")
  is_fresh=$(fresh "$(jq -r .headRefOid "$tmp/pr.json")" "$base_date")

  echo "PR #$n:" >&2
  local decision kind rest
  decision=$(decide "$tmp/pr.json" "$tmp/files.txt" "$tmp/checks.json" "$health" "$is_fresh")
  echo "decision: $decision"
  kind="${decision%%|*}"; rest="${decision#*|}"

  case "$kind" in
    skip) ;;
    pending)
      case "$rest" in
        "main is red")
          comment_once "$n" "Fast lane: waiting, main is red ($MAIN_RED_URL)" ;;
        "refreshing against main")
          local old_sha ref i
          old_sha=$(jq -r .headRefOid "$tmp/pr.json")
          ref=$(jq -r .headRefName "$tmp/pr.json")
          # One refresh at a time, oldest PR first. Refreshing every stale PR on
          # every sweep made each new CI dispatch cancel the run already going on
          # the same branch, so nothing finished and nothing merged.
          if (( REFRESH_SLOT_TAKEN )); then
            log "queued behind the PR being refreshed"; rm -rf "$tmp"; return
          fi
          if [[ "$(gh run list -R "$REPO" --workflow "$CI_FILE" --branch "$ref" --limit 10 \
                --json status --jq '[.[] | select(.status != "completed")] | length')" != "0" ]]; then
            log "CI already running on $ref; waiting for it"; REFRESH_SLOT_TAKEN=1; rm -rf "$tmp"; return
          fi
          REFRESH_SLOT_TAKEN=1
          write gh pr update-branch "$n" -R "$REPO" || { log "could not update branch"; rm -rf "$tmp"; return; }
          # update-branch is async; dispatch only once the new head exists, or CI
          # would run on the old one. A GITHUB_TOKEN push fires no pull_request CI.
          for (( i = 0; !DRY_RUN && i < 12; i++ )); do
            [[ "$(gh api "repos/$REPO/pulls/$n" --jq .head.sha)" != "$old_sha" ]] && break
            sleep 5
          done
          write gh workflow run "$CI_FILE" -R "$REPO" --ref "$ref" || log "could not dispatch CI on $ref"
          ;;
      esac
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
      local lines files green sha
      DISPATCH_BASE_CI=1  # this merge fires no CI on main by itself
      IFS='|' read -r lines files green <<<"$rest"
      sha=$(jq -r '.headRefOid' "$tmp/pr.json")
      # Squash message = PR title + body, minus any AI attribution lines.
      local title body
      title=$(gh pr view "$n" -R "$REPO" --json title --jq .title)
      body=$(gh pr view "$n" -R "$REPO" --json body --jq .body | strip_attribution)
      # Cloud sessions append a "Generated by Claude Code" footer to the PR body; drop it there too.
      write gh pr edit "$n" -R "$REPO" --body "$body" || log "could not strip attribution from the PR body"
      write gh pr merge "$n" -R "$REPO" --squash --delete-branch=false --match-head-commit "$sha" \
        --subject "$title (#$n)" --body "$body"
      MERGED_ANY=1
      # GitHub does not auto-close linked issues when GITHUB_TOKEN merges, so close them here.
      local issue
      for issue in $(gh pr view "$n" -R "$REPO" --json closingIssuesReferences --jq '.closingIssuesReferences[].number'); do
        write gh issue close "$issue" -R "$REPO" --reason completed --comment "Done in #$n (fast lane)." || log "could not close #$issue"
        write gh issue edit "$issue" -R "$REPO" --remove-label in-progress || true
      done
      write gh pr edit "$n" -R "$REPO" --add-label "$MERGED_LABEL" || log "could not add $MERGED_LABEL label"
      comment_once "$n" "Fast lane: merged ($lines lines, $files files, $green checks green)."
      ;;
  esac
  rm -rf "$tmp"
}

main() {
  local sha="" prs=()
  while (( $# )); do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --sha) sha="${2:?--sha needs a value}"; shift ;;
      -h|--help) sed -n '2,30p' "$0"; return 0 ;;
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
  (( ${#prs[@]} )) || { echo "fast-lane: no matching open $LABEL PRs" >&2; return 0; }
  local n pass
  for n in "${prs[@]}"; do evaluate "$n"; done
  # A merge made with GITHUB_TOKEN triggers no workflows, so PRs that went
  # green while it was settling would never be looked at again. After any
  # merge, sweep every open fast-lane PR, until a pass merges nothing.
  for (( pass = 0; MERGED_ANY && pass < 5; pass++ )); do
    MERGED_ANY=0
    while read -r n; do [[ -n "$n" ]] && evaluate "$n"; done < <(
      gh pr list -R "$REPO" --state open --base "$BASE_BRANCH" --label "$LABEL" \
        --limit 100 --json number --jq '.[].number' | sort -n)
  done
  # GITHUB_TOKEN merges fire no workflows; workflow_dispatch is the exception.
  if (( DISPATCH_BASE_CI )); then
    write gh workflow run "$CI_FILE" -R "$REPO" --ref "$BASE_BRANCH" || log "could not dispatch CI on $BASE_BRANCH"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
