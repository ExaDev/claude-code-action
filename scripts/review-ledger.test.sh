#!/usr/bin/env bash
# Tests for review mode's ledger: scripts/review-ledger.sh, the schema it validates against, and the action.yml steps that read the ledger before a review and write it after. The steps run as written in action.yml, against a stub gh that serves fixture responses, so what is tested is what the action runs. Needs bash, jq, awk, git and openssl, which every GitHub-hosted runner has.
#
# Usage: bash scripts/review-ledger.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

ledger_script="${repo_root}/scripts/review-ledger.sh"
ledger_fixtures="${fixtures}/review-ledger"
# Runs the ledger script, passing its output through unchanged and recording what it printed on stderr, so the error-path check below can see every message the tests provoked whatever the caller does with stderr.
ledger() {
  local stderr_file status=0
  stderr_file="$(mktemp "${work_dir}/ledger-stderr.XXXXXX")"
  bash "$ledger_script" "$@" 2> "$stderr_file" || status=$?
  cat "$stderr_file" >> "$observed_output"
  cat "$stderr_file" >&2
  rm -f "$stderr_file"
  return "$status"
}

# Exits with the status of a command, its output discarded, so a test can assert that a check fails.
status_of() {
  local status=0
  "$@" > /dev/null 2>&1 || status=$?
  echo "$status"
}

# A repository for the pull request under review: a base commit, a first head that renames the old-build script without updating the documents that name it, and a second head that fixes one document and pushes the other's line further down. The repository's own invariants file is on the base commit; the first head tries to empty it.
fixture_repo="${work_dir}/repo"
mkdir -p "$fixture_repo"
# The hook's repository variables are dropped so these commands act on the fixture, never on a repository around the test.
fixture_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$fixture_repo" -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false "$@"
}
fixture_write() {
  mkdir -p "$(dirname "${fixture_repo}/$1")"
  printf '%s' "$2" > "${fixture_repo}/$1"
}
fixture_git init -q
fixture_write README.md $'# Example\n\nBuild it:\n\nnpm run old-build\n'
fixture_write docs/setup.md $'# Setup\n\nnpm run old-build\n'
fixture_write package.json $'{"scripts": {"old-build": "tsc"}}\n'
fixture_write src/index.js $'console.log("ready");\n'
fixture_write .github/claude/invariants.json '{"invariants": [{"classKey": "no-console-log", "statement": "Source code logs through the logger, never console.log.", "enumerator": {"type": "grep", "pattern": "console\\.log", "paths": ["src"]}}]}'
fixture_git add -A
fixture_git commit -q -m base
sha_b="$(fixture_git rev-parse HEAD)"
fixture_write package.json $'{"scripts": {"build": "tsc"}}\n'
fixture_write .github/claude/invariants.json '{"invariants": []}'
fixture_git commit -q -a -m "rename the build script"
sha_a="$(fixture_git rev-parse HEAD)"
fixture_write docs/setup.md $'# Setup\n\nnpm run build\n'
fixture_write README.md $'# Example\n\nFour new lines\nabove the command\nmove it down\nthe file.\n\nBuild it:\n\nnpm run old-build\n'
fixture_git commit -q -a -m "fix the setup document"
sha_c="$(fixture_git rev-parse HEAD)"
repository_invariants="$(fixture_git show "${sha_b}:.github/claude/invariants.json" | jq -c '.invariants')"

facts_for() {
  local head="$1"
  jq -n -c --arg head "$head" --arg base "$sha_b" --argjson repository "$repository_invariants" '{pullRequest: 7, reviewedHead: $head, baseSha: $base, patchId: null, reviewedFiles: ["README.md", "docs/setup.md", "package.json"], scope: {kind: "full", since: null, reason: "first recorded round"}, repositoryInvariants: $repository}'
}
in_fixture() {
  (cd "$fixture_repo" && "$@")
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
expect_equal "round 1 records the repository's invariant and the one the reviewer checked" "no-console-log repository 1, stale-reference review 1" "$(jq -r '[.invariants[] | "\(.classKey) \(.source) \(.checkedRound)"] | join(", ")' "${work_dir}/ledger-1.json")"
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
expect_equal "a re-declared invariant is recorded once, checked this round" "1 2" "$(jq -r '[.invariants[] | select(.source == "review")] | "\(length) \(.[0].checkedRound)"' "${work_dir}/ledger-2.json")"
expect_equal "the round 2 ledger passes its own check" "0" "$(status_of ledger check "${work_dir}/ledger-2.json")"

# Enumerators: what the action runs itself.
readme_id_round_1="$(in_fixture ledger prepare "$sha_a" "${work_dir}/facts-1.json" "${work_dir}/ledger-1.json" | jq -r '.invariants[] | select(.classKey == "stale-reference") | .instances[] | select(.path == "README.md") | "\(.id) \(.line)"')"
readme_id_round_2="$(in_fixture ledger prepare "$sha_c" "${work_dir}/facts-2.json" "${work_dir}/ledger-1.json" | jq -r '.invariants[] | select(.classKey == "stale-reference") | .instances[] | select(.path == "README.md") | "\(.id) \(.line)"')"
expect_equal "an enumerated instance's id is the finding's id for the same instance" "${id_one} 5" "$readme_id_round_1"
expect_equal "an enumerated instance keeps its id when lines above it move" "${id_one} 10" "$readme_id_round_2"
fixture_write duplicate.md $'npm run old-build\nother\n  npm run old-build\n'
fixture_git add duplicate.md
fixture_git commit -q -m "add a duplicate"
duplicate_head="$(fixture_git rev-parse HEAD)"
jq -n -c '[{classKey: "stale-reference", statement: "s", enumerator: {type: "grep", pattern: "old-build", paths: ["duplicate.md"]}, source: "review"}]' > "${work_dir}/duplicate-invariant.json"
jq -c --argjson invariants "$(cat "${work_dir}/duplicate-invariant.json")" '.repositoryInvariants = $invariants' "${work_dir}/facts-1.json" > "${work_dir}/facts-duplicate.json"
expect_equal "identical lines in one file get distinct keys, numbered in file order" '["duplicate.md :: npm run old-build","duplicate.md :: npm run old-build #2"]' "$(in_fixture ledger prepare "$duplicate_head" "${work_dir}/facts-duplicate.json" | jq -c '[.invariants[0].instances[].key]')"
jq -c '.repositoryInvariants[0].enumerator.pattern = "("' "${work_dir}/facts-duplicate.json" > "${work_dir}/facts-bad-pattern.json"
expect_equal "a pattern git grep rejects stops the run" "1" "$(status_of in_fixture ledger prepare "$sha_a" "${work_dir}/facts-bad-pattern.json")"
expect_equal "the repository's invariant is enumerated from the head's tree" '["src/index.js :: console.log(\"ready\");"]' "$(in_fixture ledger prepare "$sha_a" "${work_dir}/facts-1.json" | jq -c '[.invariants[] | select(.classKey == "no-console-log") | .instances[].key]')"

in_fixture ledger enumerate-ledger "$sha_a" "${work_dir}/ledger-1.json" > "${work_dir}/ledger-1-enumerated.json"
expect_equal "enumerate-ledger keeps round 1's findings open while their instances match" "open open" "$(jq -r '[.findings[].status] | join(" ")' "${work_dir}/ledger-1-enumerated.json")"
expect_equal "enumerate-ledger records each invariant's instances" "1 2" "$(jq -r '[.invariants[].instances | length] | join(" ")' "${work_dir}/ledger-1-enumerated.json")"
expect_equal "an enumerated ledger passes its own check" "0" "$(status_of ledger check "${work_dir}/ledger-1-enumerated.json")"
# A round 2 update that says nothing about docs/setup.md: the action finds its instance gone and marks it fixed itself.
jq -c '.statuses = []' "${work_dir}/update-2.json" > "${work_dir}/update-2-silent.json"
ledger apply "${work_dir}/update-2-silent.json" "${work_dir}/facts-2.json" "${work_dir}/ledger-1-enumerated.json" > "${work_dir}/applied-2-silent.json"
in_fixture ledger enumerate-ledger "$sha_c" "${work_dir}/applied-2-silent.json" > "${work_dir}/ledger-2-silent.json"
expect_equal "a grep-enumerated finding whose instance no longer matches is marked fixed by the action" "fixed" "$(jq -r '.findings[] | select(.path == "docs/setup.md") | .status' "${work_dir}/ledger-2-silent.json")"
# A round 2 update that calls the README finding fixed although its line is still there.
jq -c --arg id "$id_one" '.findings = [] | .statuses = [{id: $id, status: "fixed", reason: "claimed"}]' "${work_dir}/update-2.json" > "${work_dir}/update-2-false-fix.json"
ledger apply "${work_dir}/update-2-false-fix.json" "${work_dir}/facts-2.json" "${work_dir}/ledger-1-enumerated.json" > "${work_dir}/applied-2-false-fix.json"
in_fixture ledger enumerate-ledger "$sha_c" "${work_dir}/applied-2-false-fix.json" > "${work_dir}/ledger-2-false-fix.json"
expect_equal "a grep-enumerated finding called fixed while its instance still matches stays open" "open" "$(jq -r --arg id "$id_one" '.findings[] | select(.id == $id) | .status' "${work_dir}/ledger-2-false-fix.json")"
# A finding whose instance is not one of its enumerator's keys.
jq -c '.findings[0].instance = "README.md :: a line that is not there"' "${work_dir}/update-2.json" > "${work_dir}/update-2-unmatched.json"
ledger apply "${work_dir}/update-2-unmatched.json" "${work_dir}/facts-2.json" "${work_dir}/ledger-1-enumerated.json" > "${work_dir}/applied-2-unmatched.json"
expect_equal "a finding reported with an instance its grep enumerator does not find is refused" "1" "$(status_of in_fixture ledger enumerate-ledger "$sha_c" "${work_dir}/applied-2-unmatched.json")"

# context: what the reviewer is told
in_fixture ledger prepare "$sha_a" "${work_dir}/facts-1.json" > "${work_dir}/prepared-1.json"
expect_contains "the first round's context says there is no earlier round" "This is round 1" "$(ledger context "${work_dir}/prepared-1.json")"
expect_contains "the first round's context lists the repository's invariant with its instances" '"src/index.js :: console.log(\"ready\");" (src/index.js, line 1)' "$(ledger context "${work_dir}/prepared-1.json")"
in_fixture ledger prepare "$sha_c" "${work_dir}/facts-2.json" "${work_dir}/ledger-1-enumerated.json" > "${work_dir}/prepared-2.json"
context_2="$(ledger context "${work_dir}/prepared-2.json")"
expect_contains "a later round's context names the round" "This is round 2" "$context_2"
expect_contains "a later round's context lists each finding by id with the action's own check" "\`${id_one}\` \`stale-reference\` Should fix, open: \"README.md :: npm run old-build\". \"Names the old-build script, which this change removes.\" Its enumerator still matches this instance at this head." "$context_2"
expect_contains "a later round's context says when a finding's instance is gone" "no longer matches this instance at this head" "$context_2"
expect_contains "a later round's context lists the invariants with their instances at this head" "  - \"README.md :: npm run old-build\" (README.md, line 10)" "$context_2"

# The steps in action.yml, against a stub gh.
stub_bin="${work_dir}/stub-bin"
stub_dir="${work_dir}/stub-gh"
mkdir -p "$stub_bin" "$stub_dir"
cat > "${stub_bin}/gh" <<'STUB'
#!/usr/bin/env bash
# A gh that serves `gh api` reads from files in $STUB_DIR named after the endpoint (slashes as underscores, ".diff" appended when a diff is asked for) and records each write in $STUB_DIR/writes.log with its payload in $STUB_DIR/write-<n>.json; with $STUB_FAIL_WRITES set, every write fails instead.
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
  [ -z "${STUB_FAIL_WRITES:-}" ] || exit 1
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
  in_fixture run_step review-ledger GITHUB_STEP_SUMMARY="${work_dir}/read-summary.md" PATH="${stub_bin}:${PATH}" STUB_DIR="$stub_dir" GH_TOKEN=token REPOSITORY=owner/repo PR_NUMBER=7 WORK_ROOT="$runner_temp"
}
# Runs the write step on an execution file, with the outcome of Resolve Claude Code result (success unless given) and whether the run hit its turn limit.
run_write() {
  local execution_file="$1" outcome="${2:-success}" hit_limit="${3:-}"
  in_fixture run_step review-ledger-write STUB_FAIL_WRITES="${STUB_FAIL_WRITES:-}" GITHUB_STEP_SUMMARY="${work_dir}/step-summary.md" PATH="${stub_bin}:${PATH}" STUB_DIR="$stub_dir" GH_TOKEN=token REPOSITORY=owner/repo PR_NUMBER=7 EXECUTION_FILE="$execution_file" \
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
expect_equal "the read step takes the repository's invariants from the base commit, not the head that empties them" "no-console-log" "$(jq -r '[.repositoryInvariants[].classKey] | join(" ")' "$facts_file")"
expect_contains "the read step's context lists the repository invariant's instances at the head" "src/index.js :: console.log" "$(cat "$(output_value "${work_dir}/read-output" context)")"

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
expect_contains "the review prompt asks for invariants before the review" "### Invariants first, then enumerate" "$review_prompt"
expect_contains "the review prompt gives the action's key format for a grep instance" "\`<path> :: <matched line>\`" "$review_prompt"


# Error paths with no other test.
expect_contains "validate refuses a definition the schema does not have" "review-ledger: no schema definition named no-such-definition" "$(ledger validate no-such-definition "${work_dir}/ledger-1.json" 2>&1 || true)"
# A repository invariants file on the base commit that does not match the schema stops the read step. The fixture gains a base commit holding one and a head on top of it.
fixture_git checkout -q "$sha_b"
fixture_write .github/claude/invariants.json '{"invariants": [{"classKey": "Not Kebab Case", "statement": "s", "enumerator": {"type": "grep", "pattern": "x", "paths": []}}]}'
fixture_git commit -q -a -m "an invariants file that does not match the schema"
invalid_base="$(fixture_git rev-parse HEAD)"
fixture_write README.md $'# Example\n\nA head on the invalid base.\n'
fixture_git commit -q -a -m "a head on the invalid base"
invalid_head="$(fixture_git rev-parse HEAD)"
fixture_git checkout -q "$sha_c"
reset_stub "$invalid_head"
jq -c --arg base "$invalid_base" '.base.sha = $base' "${work_dir}/pull.json" > "${work_dir}/pull-invalid-base.json"
serve repos/owner/repo/pulls/7 "${work_dir}/pull-invalid-base.json"
status="$(run_read)"
expect_equal "the read step fails when the base commit's invariants file does not match the schema" "1" "$status"
expect_contains "the read step names the invariants file that does not match the schema" "::error::.github/claude/invariants.json on the base branch does not match the repositoryInvariants definition" "$(cat "${work_dir}/stdout")"
# Every subcommand that takes a fixed number of arguments refuses too many, naming its own usage; the subcommands are read from the script, so a new one is covered without an edit here.
too_many_arguments=(one two three four five six seven eight nine)
while IFS= read -r subcommand; do
  expect_contains "the ${subcommand} subcommand refuses too many arguments with its usage" "review-ledger: usage: review-ledger.sh ${subcommand} " "$(ledger "$subcommand" "${too_many_arguments[@]}" 2>&1 || true)"
done < <(grep -oE 'die "usage: review-ledger\.sh [a-z-]+ ' "$ledger_script" | awk '{ print $4 }' | sort -u)
expect_contains "an unknown subcommand is refused with the general usage" "review-ledger: usage: review-ledger.sh <subcommand>" "$(ledger no-such-subcommand 2>&1 || true)"
printf 'not json' > "${work_dir}/not-json.json"
expect_contains "check refuses a file that is not JSON" "review-ledger: not valid JSON: ${work_dir}/not-json.json" "$(ledger check "${work_dir}/not-json.json" 2>&1 || true)"
jq -c --arg id "$id_one" '.statuses = [{id: $id, status: "fixed", reason: "both"}]' "${work_dir}/update-1.json" > "${work_dir}/update-conflicting.json"
expect_contains "an update that reports a finding and changes its status at once is refused" "the update both reports and changes the status of: ${id_one}" "$(ledger apply "${work_dir}/update-conflicting.json" "${work_dir}/facts-1.json" "${work_dir}/ledger-1.json" 2>&1 || true)"

# The schema validator refuses what it does not implement rather than skipping it.
schema_check() {
  local schema="$1" stderr_file status=0
  stderr_file="$(mktemp "${work_dir}/schema-stderr.XXXXXX")"
  jq -n -r -L "${repo_root}/scripts" --argjson schema "$schema" 'include "json-schema"; 1 | schema_errors($schema; $schema; "$")' 2> "$stderr_file" > /dev/null || status=$?
  cat "$stderr_file" >> "$observed_output"
  cat "$stderr_file"
  [ "$status" -ne 0 ] || echo "exit 0"
}
expect_contains "the schema validator refuses a keyword it does not implement" 'json-schema: unsupported keyword(s) maximum at $' "$(schema_check '{"maximum": 3}')"
expect_contains "the schema validator refuses a \$ref to a definition that does not exist" 'json-schema: undefined $ref #/$defs/missing' "$(schema_check '{"$ref": "#/$defs/missing"}')"
expect_contains "the schema validator refuses a \$ref outside the local definitions" 'json-schema: unsupported $ref other.json' "$(schema_check '{"$ref": "other.json"}')"

# The read step without the diff, and the write step when the merge fails or GitHub refuses every write.
reset_stub "$sha_a"
rm "${stub_dir}/repos_owner_repo_pulls_7.diff"
status="$(run_read)"
expect_equal "the read step succeeds when GitHub does not return the diff" "0 null" "${status} $(jq -r '.patchId' "$(output_value "${work_dir}/output" facts)")"
expect_contains "the read step notes that the patch id is unknown when GitHub does not return the diff" "::notice::GitHub did not return the diff of pull request #7" "$(cat "${work_dir}/stdout")"
reset_stub "$sha_a"
run_read > /dev/null
cp "${work_dir}/output" "${work_dir}/read-output"
status="$(run_write "${ledger_fixtures}/trusted-fields.json")"
expect_equal "the write step fails when the reviewer's update cannot be merged, and writes nothing" "1 absent" "${status} $([ -e "${stub_dir}/writes.log" ] && echo present || echo absent)"
expect_contains "the write step passes on why the update could not be merged" "review-ledger: not a valid update" "$(cat "${work_dir}/stdout")"
status="$(STUB_FAIL_WRITES=1 run_write "${ledger_fixtures}/round-1.json")"
expect_equal "the write step fails when GitHub refuses every write" "1" "$status"
expect_contains "the write step says it could not write the ledger" "::error::Could not write the review ledger of pull request #7 after" "$(cat "${work_dir}/stdout")"

# Every error, warning and notice the ledger steps can emit, and every error the ledger script and the schema validator can raise, must be provoked by a test in this file: a new error path without one fails here. Each row is the message's opening literal text (up to its first variable), a tab, and the test that provokes it; the check below also confirms the text appeared in the output the tests provoked, and that the named test passed.
error_paths="$(cat << 'TABLE'
The review ledger of pull request #	the read step warns when GitHub does not return the pull request
GitHub did not return the diff of pull request #	the read step notes that the patch id is unknown when GitHub does not return the diff
A comment on pull request #	the read step says the marker comment's data could not be read
The review ledger in comment 	the read step names the comment it refused
The review stopped at its turn limit, so its partial review is not recorded in the review ledger of pull request #	the write step says the turn-limited review is not recorded
No attempt of Run Claude Code succeeded (Resolve Claude Code result: 	the write step says no attempt succeeded, and that a review posted before a failure is not recorded
The successful review (execution file 	the write step says why it failed
Could not write the review ledger of pull request #	the write step says it could not write the ledger
not valid JSON: 	check refuses a file that is not JSON
not a valid 	the write step passes on why the update could not be merged
usage: review-ledger.sh id <class-key> <instance>	the id subcommand refuses too many arguments with its usage
usage: review-ledger.sh check <ledger-file>	the check subcommand refuses too many arguments with its usage
usage: review-ledger.sh update-block <execution-file>	the update-block subcommand refuses too many arguments with its usage
usage: review-ledger.sh apply <update-file> <facts-file> [<previous-ledger-file>]	the apply subcommand refuses too many arguments with its usage
usage: review-ledger.sh context <prepared-file>	the context subcommand refuses too many arguments with its usage
usage: review-ledger.sh validate <definition> <file>	the validate subcommand refuses too many arguments with its usage
usage: review-ledger.sh prepare <commit> <facts-file> [<previous-ledger-file>]	the prepare subcommand refuses too many arguments with its usage
usage: review-ledger.sh enumerate-ledger <commit> <ledger-file>	the enumerate-ledger subcommand refuses too many arguments with its usage
no schema definition named 	validate refuses a definition the schema does not have
.github/claude/invariants.json on the base branch does not match the repositoryInvariants definition in the action's schemas/review-ledger.schema.json (see the log above).	the read step names the invariants file that does not match the schema
the grep enumerator of 	a pattern git grep rejects stops the run
findings reported this round name an instance their own grep enumerator does not find at 	a finding reported with an instance its grep enumerator does not find is refused
the ledger could not be enumerated (see the message above)	a finding reported with an instance its grep enumerator does not find is refused
usage: review-ledger.sh render <ledger-file>	the render subcommand refuses too many arguments with its usage
usage: review-ledger.sh <subcommand> [<argument>...], with the subcommands the header of this script lists	an unknown subcommand is refused with the general usage
no readable data block in the ledger comment 	extract names the comment whose data block is missing
the data block of the ledger comment 	a marker comment whose data is not JSON fails extract
the ledger comment could not be read (see the message above)	a marker comment with no data block fails extract
ids that do not match what they identify, so the ledger was not written by this action as it stands: 	check refuses a finding whose id does not match its instance
the update changes the status of findings the ledger does not hold: 	an update changing a finding the ledger does not hold is refused
the update both reports and changes the status of: 	an update that reports a finding and changes its status at once is refused
the update could not be applied (see the message above)	an update changing a finding the ledger does not hold is refused
the rendered ledger is 	a ledger over the comment size limit is refused
json-schema: undefined $ref 	the schema validator refuses a $ref to a definition that does not exist
json-schema: unsupported $ref 	the schema validator refuses a $ref outside the local definitions
json-schema: unsupported keyword(s) 	the schema validator refuses a keyword it does not implement
TABLE
)"
# Prints the opening literal text of every message the ledger steps and scripts can fail or warn with: an annotation in the ledger steps, a die in the ledger script, and a jq error() in the ledger script or the schema validator. Shell text ends at its first variable, jq text at its first interpolation.
error_messages() {
  for id in review-ledger review-ledger-write; do
    step_script "$id" | grep -oE '::(error|warning|notice)::[^$"]*' | sed -E 's/^::[a-z]+:://'
  done
  grep -oE 'die "[^$"]*' "$ledger_script" | sed 's/^die "//'
  cat "$ledger_script" "${repo_root}/scripts/json-schema.jq" | grep -oE 'error\("([^"\\]|\\[^(])*' | sed 's/^error("//'
}
error_messages > "${work_dir}/error-messages.txt"
while IFS= read -r message; do
  if [ -z "$message" ]; then
    fail "every error message starts with literal text, so it can be matched (one starts with a variable)"
    continue
  fi
  row="$(awk -F '\t' -v message="$message" '$1 == message { print $2; exit }' <<< "$error_paths")"
  if [ -z "$row" ]; then
    fail "the error path \"${message}\" is provoked by a test listed in the error-path table"
  elif ! grep -qF -- "$message" "$observed_output"; then
    fail "the error path \"${message}\" appeared in the output the tests provoked"
  elif ! grep -qxF -- "$row" "$passed_names"; then
    fail "the test \"${row}\" that provokes \"${message}\" passed"
  else
    pass "the error path \"${message}\" is provoked by \"${row}\""
  fi
done < "${work_dir}/error-messages.txt"
while IFS=$'\t' read -r message _; do
  grep -qxF -- "$message" "${work_dir}/error-messages.txt" || fail "the error-path table row \"${message}\" names a message the steps and scripts can still raise"
done <<< "$error_paths"
duplicates="$(sort "${work_dir}/error-messages.txt" | uniq -d)"
ambiguous="$(awk 'NR == FNR { all[NR] = $0; n = NR; next } { for (i = 1; i <= n; i++) if (all[i] != $0 && index(all[i], $0) == 1) print $0 }' "${work_dir}/error-messages.txt" "${work_dir}/error-messages.txt" | sort -u)"
expect_equal "no two error messages open with the same text, so each row names one path" "" "${duplicates}${ambiguous}"

finish
