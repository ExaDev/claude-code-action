#!/usr/bin/env bash
# Tests for the Auto-merge job of .github/workflows/dependabot.yml. The job has no checkout, so its steps' run: scripts are taken out of the workflow and run in a directory that is not a git repository, against a stub gh that resolves the repository the way gh does (--repo or -R, then GH_REPO, then the git remote of the working directory) and fails as gh does when none is found. The job's and the steps' conditions and the job's permissions are checked as written.
#
# Usage: bash scripts/dependabot-workflow.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

workflow="${repo_root}/.github/workflows/dependabot.yml"

# The stub and the steps must not find an outer repository through a variable a hook exported.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# Every line of the named job, from its key line up to the next job.
job_lines() {
  awk -v job="$1" '
    $0 == "  " job ":" { in_job = 1; print; next }
    in_job && /^  [^ #]/ { exit }
    in_job { print }
  ' "$workflow"
}

# Every line of the step with the given name in the given job, from its name line up to the next step.
workflow_step_lines() {
  job_lines "$1" | awk -v name="$2" '
    $0 == "      - name: " name { in_step = 1; print; next }
    in_step && /^      - / { exit }
    in_step { print }
  '
}

# The step's run: script as the runner would execute it, whether written inline or as a block.
workflow_step_script() {
  workflow_step_lines "$1" "$2" | awk '
    index($0, "        run: ") == 1 && $0 != "        run: |" { print substr($0, 14); exit }
    $0 == "        run: |" { in_run = 1; next }
    in_run {
      if ($0 != "" && substr($0, 1, 10) != "          ") { exit }
      print substr($0, 11)
    }
  '
}

# The `if:` at the given indent in the lines on stdin, inline or as a block, its lines joined by single spaces; nothing when there is none.
condition_at() {
  awk -v indent="$1" '
    BEGIN { prefix = indent "if: "; deeper = indent "  " }
    index($0, prefix) == 1 && $0 != prefix "|" { print substr($0, length(prefix) + 1); exit }
    $0 == prefix "|" { in_block = 1; next }
    in_block {
      if (index($0, deeper) != 1) { exit }
      line = $0
      sub(/^ +/, "", line)
      joined = joined (joined == "" ? "" : " ") line
    }
    END { if (joined != "") { print joined } }
  '
}

# The job's own if:.
job_condition() {
  job_lines "$1" | condition_at "    "
}

# The step's own if:.
workflow_step_condition() {
  workflow_step_lines "$1" "$2" | condition_at "        "
}

# A gh that records each call in $STUB_LOG, resolves the repository as gh does, answers `pr view --json autoMergeRequest` from $STUB_AUTO_MERGE (a JSON value, null when unset), and applies --jq with jq.
stub_bin="${work_dir}/stub-bin"
mkdir -p "$stub_bin"
cat > "${stub_bin}/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$STUB_LOG"
repo="${GH_REPO:-}"
jq_filter=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
  --repo | -R) repo="${args[i + 1]}" ;;
  --repo=*) repo="${args[i]#--repo=}" ;;
  --jq | -q) jq_filter="${args[i + 1]}" ;;
  esac
done
if [ -z "$repo" ] && ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "failed to run git: fatal: not a git repository (or any of the parent directories): .git" >&2
  exit 1
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  body="{\"autoMergeRequest\":${STUB_AUTO_MERGE:-null}}"
  if [ -n "$jq_filter" ]; then
    jq -r "$jq_filter" <<< "$body"
  else
    printf '%s\n' "$body"
  fi
fi
STUB
chmod +x "${stub_bin}/gh"

no_checkout="${work_dir}/no-checkout"
mkdir -p "$no_checkout"
if git -C "$no_checkout" rev-parse --git-dir > /dev/null 2>&1; then
  echo "the scratch directory ${no_checkout} is inside a git repository, so a missing --repo would go unnoticed" >&2
  exit 1
fi

stub_log="${work_dir}/gh-calls"

# Runs a script in the directory with no checkout, with the environment the job gives it, and prints its exit status; its output is in $work_dir/stdout.
run_without_checkout() {
  local script="$1"
  shift
  : > "$stub_log"
  local status=0
  (cd "$no_checkout" && env -i PATH="${stub_bin}:${PATH}" STUB_LOG="$stub_log" GITHUB_REPOSITORY="ExaDev/claude-code-action" GH_TOKEN="test-token" PR="146" "$@" bash "$script") > "${work_dir}/stdout" 2>&1 || status=$?
  echo "$status"
}

enable_script="${work_dir}/enable.sh"
withdraw_script="${work_dir}/withdraw.sh"
workflow_step_script auto-merge "Enable auto-merge" > "$enable_script"
workflow_step_script auto-merge "Withdraw auto-merge" > "$withdraw_script"
for script in "$enable_script" "$withdraw_script"; do
  if [ ! -s "$script" ]; then
    echo "no run: script in ${script}" >&2
    exit 1
  fi
done

# The job's shape, as written.
permissions="$(job_lines auto-merge | awk '$0 == "    permissions:" { in_block = 1; next } in_block && /^      [a-z-]+: / { sub(/^ +/, ""); print; next } in_block { exit }' | paste -sd ' ' -)"
expect_equal "the Auto-merge job can enable and disable auto-merge" "contents: write pull-requests: write" "$permissions"
expect_equal "Auto-merge is not checked out, so its steps cannot rely on a git remote" "" "$(job_lines auto-merge | grep 'uses: actions/checkout' || true)"
expect_equal "the Auto-merge job runs on every classified Dependabot run, whatever the review and the auto-merge flags say" "always() && needs.metadata.result == 'success'" "$(job_condition auto-merge)"
expect_equal "auto-merge is enabled only when the review cleared the revision and the bump is enabled and eligible" "needs.review.result == 'success' && needs.metadata.outputs.automerge-enabled == 'true' && needs.metadata.outputs.automerge-eligible == 'true'" "$(workflow_step_condition auto-merge "Enable auto-merge")"
expect_equal "Withdraw auto-merge has no condition of its own, so nothing can gate it apart from its script" "" "$(workflow_step_condition auto-merge "Withdraw auto-merge")"

# Enable auto-merge
expect_equal "Enable auto-merge succeeds with no checkout" "0" "$(run_without_checkout "$enable_script")"
expect_equal "Enable auto-merge names the repository and merges with a merge commit" "pr merge 146 --repo ExaDev/claude-code-action --auto --merge" "$(cat "$stub_log")"

# Withdraw auto-merge, for a pull request an earlier run left with auto-merge on. Each case is the review result, then the automerge-enabled and automerge-eligible outputs of metadata, as the step's environment receives them.
armed='{"mergeMethod":"MERGE"}'
withdraw_call="pr merge 146 --repo ExaDev/claude-code-action --disable-auto"

# Runs the withdraw step for one case with auto-merge on, and prints its exit status and its last gh call.
withdraw_case() {
  local status
  status="$(run_without_checkout "$withdraw_script" STUB_AUTO_MERGE="$armed" REVIEW_RESULT="$1" AUTOMERGE_ENABLED="$2" AUTOMERGE_ELIGIBLE="$3")"
  echo "${status} $(tail -n 1 "$stub_log")"
}

expect_equal "a revision the review did not clear withdraws auto-merge" "0 ${withdraw_call}" "$(withdraw_case failure true true)"
expect_equal "a revision the review was skipped for withdraws auto-merge" "0 ${withdraw_call}" "$(withdraw_case skipped true true)"
expect_equal "a bump no longer eligible withdraws auto-merge though the review cleared it" "0 ${withdraw_call}" "$(withdraw_case success true false)"
expect_equal "auto-merge switched off withdraws auto-merge though the review cleared it" "0 ${withdraw_call}" "$(withdraw_case success false true)"
expect_equal "auto-merge switched off on an ineligible bump withdraws auto-merge" "0 ${withdraw_call}" "$(withdraw_case success false false)"
expect_equal "auto-merge switched off on a revision the review did not clear withdraws auto-merge" "0 ${withdraw_call}" "$(withdraw_case failure false false)"
expect_equal "a cleared, enabled and eligible revision keeps its auto-merge and calls gh not at all" "0 " "$(withdraw_case success true true)"
expect_equal "Withdraw auto-merge succeeds with no checkout when auto-merge is off" "0" "$(run_without_checkout "$withdraw_script" REVIEW_RESULT=failure AUTOMERGE_ENABLED=false AUTOMERGE_ELIGIBLE=false)"
expect_equal "Withdraw auto-merge makes no write when auto-merge is off" "" "$(grep -- '--disable-auto' "$stub_log" || true)"

# The stub tells a missing repository apart, so the cases above could have failed.
sed 's/ --repo "${GITHUB_REPOSITORY}"//g' "$enable_script" > "${work_dir}/enable-without-repo.sh"
expect_equal "a gh pr merge with no repository fails outside a checkout" "1" "$(run_without_checkout "${work_dir}/enable-without-repo.sh")"
expect_contains "the failure is gh's own" "not a git repository" "$(cat "${work_dir}/stdout")"
expect_equal "GH_REPO names the repository as --repo does" "0" "$(run_without_checkout "${work_dir}/enable-without-repo.sh" GH_REPO="ExaDev/claude-code-action")"

finish
