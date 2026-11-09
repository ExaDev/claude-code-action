#!/usr/bin/env bash
# Tests for review mode's ledger: scripts/review-ledger.sh, the schema it validates against, and the action.yml steps that read the ledger before a review and write it after. The steps run as written in action.yml, against a stub gh that serves fixture responses, so what is tested is what the action runs. Needs bash, jq, awk, git and openssl, which every GitHub-hosted runner has.
#
# Usage: bash scripts/review-ledger.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

ledger_script="${repo_root}/scripts/review-ledger.sh"
ledger_fixtures="${fixtures}/review-ledger"
ledger() {
  bash "$ledger_script" "$@"
}

# Exits with the status of a command, its output discarded, so a test can assert that a check fails.
status_of() {
  local status=0
  "$@" > /dev/null 2>&1 || status=$?
  echo "$status"
}

sha_a="$(printf 'a%.0s' {1..40})"
sha_b="$(printf 'b%.0s' {1..40})"
sha_c="$(printf 'c%.0s' {1..40})"

facts_for() {
  local head="$1"
  jq -n -c --arg head "$head" --arg base "$sha_b" '{pullRequest: 7, reviewedHead: $head, baseSha: $base, patchId: null, reviewedFiles: ["README.md", "docs/setup.md", "package.json"], scope: {kind: "full", since: null, reason: "first recorded round"}}'
}

# Stable ids
id_one="$(ledger id stale-reference 'README.md :: npm run old-build')"
expect_equal "an id is the same each time it is computed" "$id_one" "$(ledger id stale-reference 'README.md :: npm run old-build')"
expect_equal "an id is sixteen hex digits" "yes" "$([[ "$id_one" =~ ^[0-9a-f]{16}$ ]] && echo yes || echo no)"
if [ "$id_one" != "$(ledger id stale-reference 'docs/setup.md :: npm run old-build')" ] && [ "$id_one" != "$(ledger id other-class 'README.md :: npm run old-build')" ]; then
  pass "a different instance or class gets a different id"
else
  fail "a different instance or class gets a different id"
fi
expect_equal "a class key and instance cannot be confused with another split of the same text" "different" "$([ "$(ledger id stale reference)" != "$(ledger id stal ereference)" ] && echo different || echo same)"

# patch-id
printf 'diff --git a/x b/x\nindex 1..2 100644\n--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n' > "${work_dir}/one.diff"
printf 'diff --git a/x b/x\nindex 3..4 100644\n--- a/x\n+++ b/x\n@@ -10 +10 @@\n-a\n+b\n' > "${work_dir}/one-shifted.diff"
expect_equal "the patch id ignores where a hunk sits and the blob ids" "$(ledger patch-id < "${work_dir}/one.diff")" "$(ledger patch-id < "${work_dir}/one-shifted.diff")"
expect_equal "an empty diff has no patch id" "" "$(ledger patch-id < /dev/null)"

# update-block
expect_equal "update-block reads the last block of the final result, without its code fence" "stale-reference" "$(ledger update-block "${ledger_fixtures}/round-1.json" | jq -r '.findings[0].classKey')"
expect_equal "update-block prints nothing when the result has no block" "" "$(ledger update-block "${fixtures}/success.json")"
expect_equal "update-block prints nothing for a missing file" "" "$(ledger update-block "${work_dir}/missing.json")"
# A reviewer that put the block at the end of the review body it submitted and ended with a prose summary, as a real run did.
expect_equal "update-block reads a block the run wrote in a tool call when its final message has none" "2" "$(ledger update-block "${ledger_fixtures}/block-in-review-body.json" 2> /dev/null | jq '.findings | length')"
expect_contains "update-block says it read the block from an earlier message" "an earlier message of the run, not its final result message" "$(ledger update-block "${ledger_fixtures}/block-in-review-body.json" 2>&1 > /dev/null)"
expect_equal "update-block never reads a block from the prompt or a tool result" "" "$(jq 'map(select(.type != "assistant"))' "${ledger_fixtures}/block-in-review-body.json" > "${work_dir}/no-assistant.json" && ledger update-block "${work_dir}/no-assistant.json" 2> /dev/null)"
printf 'not json' > "${work_dir}/invalid-execution.json"
expect_equal "update-block fails on an execution file that is not JSON" "5" "$(status_of ledger update-block "${work_dir}/invalid-execution.json")"

# apply, round 1
ledger update-block "${ledger_fixtures}/round-1.json" > "${work_dir}/update-1.json"
facts_for "$sha_a" > "${work_dir}/facts-1.json"
ledger apply "${work_dir}/update-1.json" "${work_dir}/facts-1.json" > "${work_dir}/ledger-1.json"
expect_equal "round 1 records the head and round the runner supplied" "1 ${sha_a}" "$(jq -r '"\(.round) \(.reviewedHead)"' "${work_dir}/ledger-1.json")"
expect_equal "round 1 records both reported instances as open" "open open" "$(jq -r '[.findings[].status] | join(" ")' "${work_dir}/ledger-1.json")"
expect_equal "each finding's id is its class key and instance's id" "$(ledger id stale-reference 'README.md :: npm run old-build')" "$(jq -r '.findings[] | select(.path == "README.md") | .id' "${work_dir}/ledger-1.json")"
expect_equal "round 1 records the invariant the reviewer checked" "stale-reference review 1" "$(jq -r '.invariants[] | "\(.classKey) \(.source) \(.checkedRound)"' "${work_dir}/ledger-1.json")"
expect_equal "a ledger the action wrote passes its own check" "0" "$(status_of ledger check "${work_dir}/ledger-1.json")"

# render and extract: the round trip through a comment
ledger render "${work_dir}/ledger-1.json" > "${work_dir}/comment-1.md"
comments_with() {
  jq -n -c --rawfile body "$1" --arg type "$2" '[{id: 41, user: {type: "User"}, updated_at: "2026-01-01T00:00:00Z", body: "unrelated"}, {id: 42, user: {type: $type}, updated_at: "2026-01-02T00:00:00Z", body: $body}]'
}
comments_with "${work_dir}/comment-1.md" Bot | ledger extract > "${work_dir}/found-1.json"
expect_equal "a rendered ledger reads back exactly from a bot's comment" "true" "$(jq --slurpfile written "${work_dir}/ledger-1.json" '.ledger == $written[0]' "${work_dir}/found-1.json")"
expect_equal "extract reports which comment holds the ledger" "42" "$(jq -r '.commentId' "${work_dir}/found-1.json")"
expect_equal "a ledger in a comment by a user account is never read" "" "$(comments_with "${work_dir}/comment-1.md" User | ledger extract)"
expect_equal "no comment with a ledger reads as no ledger" "" "$(printf '[]' | ledger extract)"
# A comment that still carries the marker but whose data block was cut or edited is an error, never "no ledger".
sed '/^<!-- claude-review-ledger-data$/,$d' "${work_dir}/comment-1.md" > "${work_dir}/comment-no-data.md"
expect_equal "a marker comment with no data block fails extract" "1" "$(status_of ledger extract < <(comments_with "${work_dir}/comment-no-data.md" Bot))"
expect_contains "extract names the comment whose data block is missing" "no readable data block in the ledger comment 42" "$(comments_with "${work_dir}/comment-no-data.md" Bot | ledger extract 2>&1)"
sed 's/^{"version":1/{"version":1,,/' "${work_dir}/comment-1.md" > "${work_dir}/comment-bad-json.md"
expect_contains "a marker comment whose data is not JSON fails extract" "the data block of the ledger comment 42 is not valid JSON" "$(comments_with "${work_dir}/comment-bad-json.md" Bot | ledger extract 2>&1)"

# The data block cannot be closed early by text inside it.
jq '.findings[0].summary = "closes --> early and <!-- opens"' "${work_dir}/ledger-1.json" > "${work_dir}/ledger-arrow.json"
ledger render "${work_dir}/ledger-arrow.json" > "${work_dir}/comment-arrow.md"
expect_equal "a summary containing --> stays inside the hidden data block" "1" "$(grep -c -- '-->' "${work_dir}/comment-arrow.md" | awk '{ print $1 - 1 }')"
expect_equal "a summary containing --> reads back unchanged" "closes --> early and <!-- opens" "$(comments_with "${work_dir}/comment-arrow.md" Bot | ledger extract | jq -r '.ledger.findings[0].summary')"
if grep -q 'closes' <(sed -n '1,/claude-review-ledger-data/p' "${work_dir}/comment-arrow.md"); then
  fail "the visible part of the comment shows no text the reviewer wrote"
else
  pass "the visible part of the comment shows no text the reviewer wrote"
fi

# A ledger too large for one comment fails loudly instead of being cut.
jq --arg big "$(head -c 70000 /dev/zero | tr '\0' 'x')" '.findings[0].summary = $big' "${work_dir}/ledger-1.json" > "${work_dir}/ledger-big.json"
expect_equal "a ledger over the comment size limit is refused" "1" "$(status_of ledger render "${work_dir}/ledger-big.json")"

# check refuses a ledger edited into a state the action never wrote.
jq '.findings[0].id = "0000000000000000"' "${work_dir}/ledger-1.json" > "${work_dir}/tampered-id.json"
expect_equal "check refuses a finding whose id does not match its instance" "1" "$(status_of ledger check "${work_dir}/tampered-id.json")"
jq '.findings[0].instance = "somewhere else"' "${work_dir}/ledger-1.json" > "${work_dir}/tampered-instance.json"
expect_equal "check refuses an instance edited under an existing id" "1" "$(status_of ledger check "${work_dir}/tampered-instance.json")"
jq '.reviewedHead = "main"' "${work_dir}/ledger-1.json" > "${work_dir}/tampered-head.json"
expect_equal "check refuses a reviewed head that is not a commit id" "1" "$(status_of ledger check "${work_dir}/tampered-head.json")"
jq '.version = 2' "${work_dir}/ledger-1.json" > "${work_dir}/other-version.json"
expect_equal "check refuses a ledger of another version" "1" "$(status_of ledger check "${work_dir}/other-version.json")"
jq '.findings += [.findings[0]]' "${work_dir}/ledger-1.json" > "${work_dir}/duplicate.json"
expect_equal "check refuses a finding recorded twice" "1" "$(status_of ledger check "${work_dir}/duplicate.json")"

# The reviewer's update cannot set what the runner owns.
ledger update-block "${ledger_fixtures}/trusted-fields.json" > "${work_dir}/update-trusted.json"
expect_equal "an update that sets a head or an id is refused" "1" "$(status_of ledger apply "${work_dir}/update-trusted.json" "${work_dir}/facts-1.json" "${work_dir}/ledger-1.json")"
ledger update-block "${ledger_fixtures}/line-number-instance.json" > "${work_dir}/update-line.json"
expect_equal "an update naming an instance by its line number is refused" "1" "$(status_of ledger apply "${work_dir}/update-line.json" "${work_dir}/facts-1.json" "${work_dir}/ledger-1.json")"
jq -c '.statuses = [{id: "0123456789abcdef", status: "fixed", reason: "gone"}]' "${work_dir}/update-1.json" > "${work_dir}/update-unknown.json"
expect_equal "an update changing a finding the ledger does not hold is refused" "1" "$(status_of ledger apply "${work_dir}/update-unknown.json" "${work_dir}/facts-1.json" "${work_dir}/ledger-1.json")"

# apply, round 2: a finding that still stands keeps its id, a fixed one is marked fixed, nothing is counted twice.
ledger update-block "${ledger_fixtures}/round-2.json" > "${work_dir}/update-2.json"
facts_for "$sha_c" > "${work_dir}/facts-2.json"
ledger apply "${work_dir}/update-2.json" "${work_dir}/facts-2.json" "${work_dir}/ledger-1.json" > "${work_dir}/ledger-2.json"
expect_equal "round 2 follows round 1 and records the new head" "2 ${sha_c}" "$(jq -r '"\(.round) \(.reviewedHead)"' "${work_dir}/ledger-2.json")"
expect_equal "a re-reported instance adds no new finding" "2" "$(jq '.findings | length' "${work_dir}/ledger-2.json")"
expect_equal "a re-reported instance keeps its id and first round and is still open" "${id_one} 1 2 open" "$(jq -r '.findings[] | select(.path == "README.md") | "\(.id) \(.firstRound) \(.lastRound) \(.status)"' "${work_dir}/ledger-2.json")"
expect_equal "a finding marked fixed records the reason" "fixed docs/setup.md now names npm run build." "$(jq -r '.findings[] | select(.path == "docs/setup.md") | "\(.status) \(.statusReason)"' "${work_dir}/ledger-2.json")"
expect_equal "a re-declared invariant is recorded once, checked this round" "1 2" "$(jq -r '"\(.invariants | length) \(.invariants[0].checkedRound)"' "${work_dir}/ledger-2.json")"
expect_equal "the round 2 ledger passes its own check" "0" "$(status_of ledger check "${work_dir}/ledger-2.json")"

# context: what the reviewer is told
expect_contains "the first round's context says there is no earlier round" "This is round 1" "$(ledger context)"
context_2="$(ledger context "${work_dir}/ledger-1.json")"
expect_contains "a later round's context names the round" "This is round 2" "$context_2"
expect_contains "a later round's context lists each finding by id" "\`${id_one}\` \`stale-reference\` Should fix, open" "$context_2"
expect_contains "a later round's context lists the invariants checked" "grep \`old-build\` in \`README.md\`, \`docs\`" "$context_2"

# The steps in action.yml, against a stub gh.
stub_bin="${work_dir}/stub-bin"
stub_dir="${work_dir}/stub-gh"
mkdir -p "$stub_bin" "$stub_dir"
cat > "${stub_bin}/gh" <<'STUB'
#!/usr/bin/env bash
# A gh that serves `gh api` reads from files in $STUB_DIR named after the endpoint (slashes as underscores, ".diff" appended when a diff is asked for) and records each write in $STUB_DIR/writes.log with its payload in $STUB_DIR/write-<n>.json.
[ "$1" = "api" ] || exit 1
shift
method="GET" accept="" input="" endpoint=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -H) accept="$2"; shift 2 ;;
    --input) input="$2"; shift 2 ;;
    --paginate | --slurp) shift ;;
    *) endpoint="$1"; shift ;;
  esac
done
if [ "$method" != "GET" ]; then
  count="$(wc -l < "${STUB_DIR}/writes.log" 2> /dev/null || echo 0)"
  count=$((count + 1))
  echo "${method} ${endpoint}" >> "${STUB_DIR}/writes.log"
  cp "$input" "${STUB_DIR}/write-${count}.json"
  echo '{}'
  exit 0
fi
file="${STUB_DIR}/${endpoint//\//_}"
case "$accept" in *diff*) file="${file}.diff" ;; esac
[ -f "$file" ] || exit 1
cat "$file"
STUB
chmod +x "${stub_bin}/gh"

serve() {
  local endpoint="$1" source="$2"
  cp "$source" "${stub_dir}/${endpoint//\//_}"
}
reset_stub() {
  rm -rf "$stub_dir"
  mkdir -p "$stub_dir"
  jq -n -c --arg head "$1" --arg base "$sha_b" '{head: {sha: $head}, base: {sha: $base}}' > "${work_dir}/pull.json"
  serve repos/owner/repo/pulls/7 "${work_dir}/pull.json"
  jq -n -c '[[{filename: "README.md"}, {filename: "docs/setup.md"}], [{filename: "package.json", previous_filename: "package.old.json"}]]' > "${work_dir}/files.json"
  serve repos/owner/repo/pulls/7/files "${work_dir}/files.json"
  cp "${work_dir}/one.diff" "${stub_dir}/repos_owner_repo_pulls_7.diff"
  printf '[[]]' > "${work_dir}/no-comments.json"
  serve repos/owner/repo/issues/7/comments "${work_dir}/no-comments.json"
}
run_read() {
  reset_runner_temp
  run_step review-ledger GITHUB_STEP_SUMMARY="${work_dir}/read-summary.md" PATH="${stub_bin}:${PATH}" STUB_DIR="$stub_dir" GH_TOKEN=token REPOSITORY=owner/repo PR_NUMBER=7 WORK_ROOT="$runner_temp"
}
# Runs the write step on an execution file, with the outcome of Resolve Claude Code result (success unless given) and whether the run hit its turn limit.
run_write() {
  local execution_file="$1" outcome="${2:-success}" hit_limit="${3:-}"
  run_step review-ledger-write GITHUB_STEP_SUMMARY="${work_dir}/step-summary.md" PATH="${stub_bin}:${PATH}" STUB_DIR="$stub_dir" GH_TOKEN=token REPOSITORY=owner/repo PR_NUMBER=7 EXECUTION_FILE="$execution_file" \
    CLAUDE_OUTCOME="$outcome" HIT_TURN_LIMIT="$hit_limit" \
    WORK="$(output_value "${work_dir}/read-output" work_dir)" PREVIOUS="$(output_value "${work_dir}/read-output" previous)" \
    COMMENT_ID="$(output_value "${work_dir}/read-output" comment_id)" FACTS="$(output_value "${work_dir}/read-output" facts)"
}

expect_equal "the ledger is read only in review mode" "\${{ inputs.mode == 'review' }}" "$(step_value review-ledger if)"
expect_equal "the write step runs whenever the ledger was read, whatever the review's outcome, so it can say why" "\${{ inputs.mode == 'review' && !cancelled() && steps.review-ledger.outcome == 'success' && steps.review-ledger.outputs.available == 'true' }}" "$(step_value review-ledger-write if)"
expect_equal "the write step is told the review's outcome" "\${{ steps.claude.outcome }}" "$(step_value review-ledger-write CLAUDE_OUTCOME)"
expect_equal "the write step is told whether the review hit its turn limit" "\${{ steps.detect-turn-limit.outputs.hit_limit }}" "$(step_value review-ledger-write HIT_TURN_LIMIT)"
expect_equal "the ledger is written from the winning attempt's execution file" "\${{ steps.claude.outputs.execution_file }}" "$(step_value review-ledger-write EXECUTION_FILE)"
expect_equal "Compose prompt takes the ledger context the read step wrote" "\${{ steps.review-ledger.outputs.context }}" "$(step_value prompt LEDGER_CONTEXT)"

# Round 1: no ledger on the pull request yet.
reset_stub "$sha_a"
status="$(run_read)"
cp "${work_dir}/output" "${work_dir}/read-output"
expect_equal "the read step succeeds on a pull request with no ledger" "0" "$status"
expect_equal "with no ledger there is no previous ledger and no comment to update" " " "$(output_value "${work_dir}/read-output" previous) $(output_value "${work_dir}/read-output" comment_id)"
facts_file="$(output_value "${work_dir}/read-output" facts)"
expect_equal "the read step takes the head and base from GitHub" "${sha_a} ${sha_b}" "$(jq -r '"\(.reviewedHead) \(.baseSha)"' "$facts_file")"
expect_equal "the read step records the patch id of the pull request's diff" "$(ledger patch-id < "${work_dir}/one.diff")" "$(jq -r '.patchId' "$facts_file")"
expect_equal "the read step records every path the diff touched, renamed ones under both names" '["README.md","docs/setup.md","package.json","package.old.json"]' "$(jq -c '.reviewedFiles' "$facts_file")"
expect_contains "the read step's context starts round 1" "This is round 1" "$(cat "$(output_value "${work_dir}/read-output" context)")"

: > "${work_dir}/step-summary.md"
status="$(run_write "${ledger_fixtures}/round-1.json")"
expect_equal "the write step succeeds" "0" "$status"
expect_contains "the write step adds the round to the step summary" "Review ledger: round 1 recorded for head ${sha_a}" "$(cat "${work_dir}/step-summary.md")"
expect_equal "with no ledger comment the write step posts a new one" "POST repos/owner/repo/issues/7/comments" "$(cat "${stub_dir}/writes.log")"
jq -r '.body' "${stub_dir}/write-1.json" > "${work_dir}/posted-1.md"
expect_equal "the posted comment holds round 1 for the head GitHub reported" "1 ${sha_a}" "$(comments_with "${work_dir}/posted-1.md" Bot | ledger extract | jq -r '.ledger | "\(.round) \(.reviewedHead)"')"

# Round 2: the ledger from round 1 is on the pull request.
reset_stub "$sha_c"
comments_with "${work_dir}/posted-1.md" Bot | jq -c '[.]' > "${work_dir}/comments-1.json"
serve repos/owner/repo/issues/7/comments "${work_dir}/comments-1.json"
status="$(run_read)"
cp "${work_dir}/output" "${work_dir}/read-output"
expect_equal "the read step succeeds on a pull request with a ledger" "0" "$status"
expect_equal "the read step names the comment holding the ledger" "42" "$(output_value "${work_dir}/read-output" comment_id)"
expect_contains "the read step's context is round 2 with round 1's findings" "This is round 2" "$(cat "$(output_value "${work_dir}/read-output" context)")"
status="$(run_write "${ledger_fixtures}/round-2.json")"
expect_equal "the round 2 write step succeeds" "0" "$status"
expect_equal "with a ledger comment the write step edits it in place" "PATCH repos/owner/repo/issues/comments/42" "$(cat "${stub_dir}/writes.log")"
jq -r '.body' "${stub_dir}/write-1.json" > "${work_dir}/posted-2.md"
expect_equal "the edited comment holds round 2 with no finding counted twice" "2 ${sha_c} 2" "$(comments_with "${work_dir}/posted-2.md" Bot | ledger extract | jq -r '.ledger | "\(.round) \(.reviewedHead) \(.findings | length)"')"

# A run that ends without an update block fails and leaves the ledger alone.
reset_stub "$sha_c"
status="$(run_read)"
cp "${work_dir}/output" "${work_dir}/read-output"
status="$(run_write "${fixtures}/success.json")"
expect_equal "the write step fails when the review ended without an update block" "1" "$status"
expect_contains "the write step says why it failed" "wrote no <review-ledger-update> block in its final message or any other message of its own" "$(cat "${work_dir}/stdout")"
expect_equal "the write step writes nothing when the review ended without an update block" "absent" "$([ -e "${stub_dir}/writes.log" ] && echo present || echo absent)"

# The attempt that wrote the ledger is the one Resolve Claude Code result chose. A first attempt that failed (a usage limit) kept its own execution file aside, and the shared path holds the attempt that ran after it.
# Reads the ledger, places the attempts' execution files as the attempt steps leave them (the first attempt's kept aside when given, the last attempt's at the shared path), runs Resolve Claude Code result with the given outcomes, and runs the write step on the execution file it chose.
resolve_then_write_with_files() {
  local first="$1" shared="$2"
  shift 2
  reset_stub "$sha_a"
  run_read > /dev/null
  cp "${work_dir}/output" "${work_dir}/read-output"
  [ -z "$first" ] || cp "$first" "${runner_temp}/claude-execution-output-attempt-1.json"
  cp "$shared" "${runner_temp}/claude-execution-output.json"
  local shared_file="${runner_temp}/claude-execution-output.json"
  run_step claude "$@" EXECUTION_FILE_1="$shared_file" EXECUTION_FILE_2="$shared_file" SESSION_ID_1=44444444-4444-4444-8444-444444444444 SESSION_ID_2=11111111-1111-4111-8111-111111111111 \
    CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CRED_TYPE_2=key CRED_TOKEN_2=token-two CREDENTIAL_COUNT=2 > /dev/null
  cp "${work_dir}/output" "${work_dir}/resolve-output"
  run_write "$(output_value "${work_dir}/resolve-output" execution_file)"
}
status="$(resolve_then_write_with_files "${ledger_fixtures}/usage-limited.json" "${ledger_fixtures}/block-in-review-body.json" OUTCOME_1=failure OUTCOME_2=success CONCLUSION_2=success)"
expect_equal "after a failed first attempt the write step records the second attempt's review" "0 POST repos/owner/repo/issues/7/comments" "${status} $(cat "${stub_dir}/writes.log" 2> /dev/null)"
expect_equal "the ledger written after a failed first attempt holds the second attempt's findings" "2" "$(jq -r '.body' "${stub_dir}/write-1.json" | jq -R -s -c '[.]' | jq -c '[{id: 1, user: {type: "Bot"}, updated_at: "2026-01-01T00:00:00Z", body: .[0]}]' | ledger extract | jq '.ledger.findings | length')"
status="$(resolve_then_write_with_files "" "${ledger_fixtures}/round-1.json" OUTCOME_1=success CONCLUSION_1=success)"
expect_equal "when the first attempt succeeds the write step records its review" "0 POST repos/owner/repo/issues/7/comments" "${status} $(cat "${stub_dir}/writes.log" 2> /dev/null)"

# A review that never succeeded, or stopped at its turn limit, is not recorded, and the log says which.
reset_stub "$sha_a"
run_read > /dev/null
cp "${work_dir}/output" "${work_dir}/read-output"
status="$(run_write "${ledger_fixtures}/round-1.json" failure)"
expect_equal "the write step fails when no attempt succeeded" "1" "$status"
expect_contains "the write step says no attempt succeeded, and that a review posted before a failure is not recorded" "::error::No attempt of Run Claude Code succeeded (Resolve Claude Code result: failure)" "$(cat "${work_dir}/stdout")"
expect_equal "the write step writes nothing when no attempt succeeded" "absent" "$([ -e "${stub_dir}/writes.log" ] && echo present || echo absent)"
status="$(run_write "${ledger_fixtures}/round-1.json" failure true)"
expect_equal "the write step succeeds without writing when the review stopped at its turn limit" "0 absent" "${status} $([ -e "${stub_dir}/writes.log" ] && echo present || echo absent)"
expect_contains "the write step says the turn-limited review is not recorded" "::notice::The review stopped at its turn limit" "$(cat "${work_dir}/stdout")"

# A ledger comment edited into a state the action never wrote stops the run.
reset_stub "$sha_c"
ledger render "${work_dir}/tampered-instance.json" > "${work_dir}/comment-tampered.md"
comments_with "${work_dir}/comment-tampered.md" Bot | jq -c '[.]' > "${work_dir}/comments-tampered.json"
serve repos/owner/repo/issues/7/comments "${work_dir}/comments-tampered.json"
status="$(run_read)"
expect_equal "the read step fails on a ledger whose ids do not match" "1" "$status"
expect_contains "the read step names the comment it refused" "::error::The review ledger in comment 42" "$(cat "${work_dir}/stdout")"

# A GitHub read that fails after its retries leaves the ledger unavailable for the round, not the review failed, and never reads as "no ledger".
for unread in "repos_owner_repo_pulls_7:the pull request" "repos_owner_repo_pulls_7_files:changed files" "repos_owner_repo_issues_7_comments:the pull request's comments"; do
  reset_stub "$sha_c"
  serve repos/owner/repo/issues/7/comments "${work_dir}/comments-1.json"
  rm "${stub_dir}/${unread%%:*}"
  : > "${work_dir}/read-summary.md"
  status="$(run_read)"
  expect_equal "the read step succeeds when GitHub does not return ${unread#*:}" "0" "$status"
  expect_equal "the ledger is unavailable when GitHub does not return ${unread#*:}" "false" "$(output_value "${work_dir}/output" available)"
  expect_contains "the read step warns when GitHub does not return ${unread#*:}" "::warning::The review ledger of pull request #7 is unavailable for this round" "$(cat "${work_dir}/stdout")"
  expect_contains "the step summary says the ledger was unavailable when GitHub does not return ${unread#*:}" "Review ledger unavailable for this round: GitHub did not return" "$(cat "${work_dir}/read-summary.md")"
  context_unavailable="$(cat "$(output_value "${work_dir}/output" context)")"
  expect_contains "the reviewer is told the ledger could not be read when GitHub does not return ${unread#*:}" "The review ledger could not be read this round" "$context_unavailable"
  expect_equal "an unreadable ledger is never presented as a first round when GitHub does not return ${unread#*:}" "absent" "$([[ "$context_unavailable" == *"This is round 1"* ]] && echo present || echo absent)"
done
reset_stub "$sha_c"
run_read > /dev/null
expect_equal "the ledger is available when every read succeeds" "true" "$(output_value "${work_dir}/output" available)"

# A ledger comment whose data block cannot be read stops the run instead of starting the record again.
reset_stub "$sha_c"
comments_with "${work_dir}/comment-no-data.md" Bot | jq -c '[.]' > "${work_dir}/comments-no-data.json"
serve repos/owner/repo/issues/7/comments "${work_dir}/comments-no-data.json"
status="$(run_read)"
expect_equal "the read step fails on a ledger comment whose data block cannot be read" "1" "$status"
expect_contains "the read step says the marker comment's data could not be read" "::error::A comment on pull request #7 carries the review ledger marker but its data could not be read" "$(cat "${work_dir}/stdout")"

# Compose prompt places the ledger context in the review prompt.
printf '# Review ledger\n\nThis is round 9.\n' > "${work_dir}/context.md"
reset_runner_temp
status="$(run_step prompt MODE=review STACK_FRAGMENTS= STACK_NAMES= REPOSITORY=owner/repo EVENT_NAME=pull_request EVENT_ACTION=synchronize ENTITY_NUMBER=7 BASE_REF=main HEAD_SHA="$sha_a" \
  SEVERITY_RATINGS=optional ALLOWED_REVIEW_STATES=comment INCLUDE_SUGGESTIONS=true RESOLVE_STALE_THREADS=true FIX_PR_METADATA=true MARK_DRAFT_IF_UNREADY=false VERIFY_PRIOR_FINDINGS=true \
  FIX_CI_FAILURES=false FIX_DIFF_FINDINGS=false ADD_REGRESSION_TESTS=false PROMPT_DIR= PROMPT_FILE= TRIAGE_LABEL= UPDATE_ISSUE_BODY=false ALLOWED_TOOLS=Read DISALLOWED_TOOLS=Write \
  CLAUDE_ARGS_OVERRIDE= EXTRA_CLAUDE_ARGS= LEDGER_CONTEXT="${work_dir}/context.md")"
expect_equal "Compose prompt succeeds with a ledger context" "0" "$status"
expect_contains "the composed review prompt carries the ledger context" "This is round 9." "$(output_value "${work_dir}/output" text)"

# The review prompt
review_prompt="$(cat "${repo_root}/prompts/review/base.md")"
expect_contains "the review prompt asks for the update block" "<review-ledger-update>" "$review_prompt"
expect_contains "the review prompt forbids line numbers in an instance" "never by a line number" "$review_prompt"

finish
