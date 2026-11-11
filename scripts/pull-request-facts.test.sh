#!/usr/bin/env bash
# Tests for the pull request facts "Compose prompt" tells the reviewer (the "Resolve pull request facts" step and scripts/pull-request-facts.sh), and for the shape of the review examples' gate.
#
# Usage: bash scripts/pull-request-facts.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# A gh that prints the pull request JSON in $FAKE_PULL, or fails when it is unset, and records that it was called.
bin="${work_dir}/bin"
mkdir -p "$bin"
cat > "${bin}/gh" << 'STUB'
#!/usr/bin/env bash
echo called >> "${FAKE_GH_CALLS:?}"
[ -n "${FAKE_PULL:-}" ] || exit 1
printf '%s' "$FAKE_PULL"
STUB
chmod +x "${bin}/gh"
calls="${work_dir}/gh-calls"
: > "$calls"
pull='{"head": {"sha": "1111111111111111111111111111111111111111"}, "base": {"ref": "release-1.x"}}'

run_facts() {
  reset_runner_temp
  : > "$calls"
  run_step pr-facts PATH="${bin}:${PATH}" FAKE_GH_CALLS="$calls" REPOSITORY=ExaDev/claude-code-action PR_NUMBER= EVENT_HEAD_SHA= EVENT_BASE_REF= "$@"
}

# A pull_request event already carries both facts, so no API call is made.
expect_equal "a pull_request event's facts are passed through" "0" "$(run_facts PR_NUMBER=7 EVENT_HEAD_SHA=abc EVENT_BASE_REF=main)"
expect_equal "the event's head sha is the output" "abc" "$(output_value "${work_dir}/output" head_sha)"
expect_equal "the event's base branch is the output" "main" "$(output_value "${work_dir}/output" base_ref)"
expect_equal "an event that carries the facts costs no API call" "0" "$(wc -l < "$calls" | tr -d ' ')"

# A dispatch carries neither, so they come from the pull request pr_number names.
expect_equal "a dispatch resolves the facts from the API" "0" "$(run_facts PR_NUMBER=7 FAKE_PULL="$pull")"
expect_equal "the dispatched pull request's head sha is the output" "1111111111111111111111111111111111111111" "$(output_value "${work_dir}/output" head_sha)"
expect_equal "the dispatched pull request's base branch is the output" "release-1.x" "$(output_value "${work_dir}/output" base_ref)"
expect_equal "a failed lookup fails the step" "1" "$(run_facts PR_NUMBER=7)"
incomplete_status="$(run_facts PR_NUMBER=7 FAKE_PULL='{"head": {"sha": "abc"}}')"
expect_equal "a pull request with no base branch fails the step" "failed" "$([ "$incomplete_status" != "0" ] && echo failed || echo passed)"

# No pull request in scope (an issue event) has nothing to report and asks the API for nothing.
expect_equal "a run with no pull request succeeds" "0" "$(run_facts GITHUB_EVENT_NAME=issues)"
expect_equal "a run with no pull request reports no head sha" "" "$(output_value "${work_dir}/output" head_sha)"
expect_equal "a run with no pull request makes no API call" "0" "$(wc -l < "$calls" | tr -d ' ')"

# The compose step reads the facts from the resolving step and not from the event.
expect_equal "Compose prompt takes its base branch from the resolved facts" '${{ steps.pr-facts.outputs.base_ref }}' "$(step_value prompt BASE_REF)"
expect_equal "Compose prompt takes its head commit from the resolved facts" '${{ steps.pr-facts.outputs.head_sha }}' "$(step_value prompt HEAD_SHA)"

# Every review example's gate: a substitution inside a here-string hides a failed command from set -e and the ERR trap, so none may appear.
masked=""
for example in "${repo_root}"/examples/*.yml "${repo_root}"/examples/direct/*.yml; do
  if grep -nE '<<<? *"?\$\(' "$example" > /dev/null; then
    masked="${masked} ${example##*/}"
  fi
done
expect_equal "no example reads a command substitution through a here-string" "" "$masked"

finish
