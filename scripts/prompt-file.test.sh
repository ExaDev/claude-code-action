#!/usr/bin/env bash
# Tests that a composed prompt larger than one environment variable may hold reaches every Claude Code attempt. The base action exposes each of a step's inputs to its process as an environment variable (and again inside the serialised ALL_INPUTS), and Linux refuses to start a process when any one environment string is longer than MAX_ARG_STRLEN, so the prompt must reach the attempts as a file path, never as its text. "Compose prompt" runs as written in action.yml with a prompt well over that limit, and the prompt input of every attempt and retry step is resolved against that step's real output the way the runner resolves it, then handed to a child process in the environment. Needs bash, awk and openssl, which every GitHub-hosted runner has.
#
# Usage: bash scripts/prompt-file.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

# MAX_ARG_STRLEN in Linux's include/uapi/linux/binfmts.h is 32 pages, fixed at 4 KiB pages by the kernel's exec path whatever the host's page size, so 128 KiB: the longest single argument or environment string a process can be started with.
max_arg_strlen=$((32 * 4096))
# A prompt over twice the limit, so neither a near miss nor an off-by-one in the limit's derivation lets the old route pass.
prompt_bytes=$((max_arg_strlen * 2 + max_arg_strlen / 4))

# Every Claude Code attempt and retry: the steps the credential fallback chain unrolls, found by id rather than listed, so a slot added later is covered too.
attempt_ids="$(awk '/^      id: attempt_[0-9]+(_retry)?$/ { print $2 }' "$action")"
attempt_count="$(printf '%s\n' "$attempt_ids" | grep -c . || true)"
if [ "$attempt_count" -gt 0 ]; then
  pass "action.yml has Claude Code attempt steps to check (${attempt_count})"
else
  fail "action.yml has Claude Code attempt steps to check"
fi

# The value the runner gives an input written as `${{ steps.prompt.outputs.<name> }}`, read from the prompt step's output file.
resolve_prompt_output() {
  local expression="$1" name
  name="$(printf '%s' "$expression" | sed -n 's/^\${{ steps\.prompt\.outputs\.\([a-z_]*\) }}$/\1/p')"
  if [ -z "$name" ]; then
    echo "not a prompt step output: ${expression}" >&2
    return 1
  fi
  output_value "${work_dir}/output" "$name"
}

# A prompt with a marker at each end, so a file read back can be checked for both ends and the step's output for neither.
marker="PROMPT-FILE-TEST-$(openssl rand -hex 8)"
big_prompt="${work_dir}/big-prompt.md"
{
  printf '%s start\n' "$marker"
  head -c "$prompt_bytes" /dev/zero | tr '\0' 'x'
  printf '\n%s end\n' "$marker"
} > "$big_prompt"

# Checks every attempt against the prompt step's last run, whose whole prompt is in the given file.
check_attempts() {
  local route="$1" expected="$2" id input expression value variable status
  for id in $attempt_ids; do
    expect_equal "${route}: ${id} passes the composed prompt as prompt_file" '${{ steps.prompt.outputs.file }}' "$(step_value "$id" prompt_file)"
    expect_equal "${route}: ${id} passes no prompt text" "" "$(step_value "$id" prompt)"
    # Whichever prompt input the step passes, resolved as the runner resolves it, so the checks below measure what the base action would really receive.
    input=prompt_file
    expression="$(step_value "$id" "$input")"
    if [ -z "$expression" ]; then
      input=prompt
      expression="$(step_value "$id" "$input")"
    fi
    value="$(resolve_prompt_output "$expression" || true)"
    if [ "${#value}" -lt "$max_arg_strlen" ]; then
      pass "${route}: ${id}'s prompt input fits in one environment variable"
    else
      fail "${route}: ${id}'s prompt input fits in one environment variable (${#value} bytes)"
    fi
    status=0
    # The base action's run step exports each input under its upper-cased name (PROMPT_FILE, PROMPT); on Linux a value over MAX_ARG_STRLEN stops the process from starting at all.
    variable="$(printf '%s' "$input" | tr '[:lower:]' '[:upper:]')"
    env -i PATH="$PATH" "${variable}=${value}" bash -c 'exit 0' 2> /dev/null || status=$?
    expect_equal "${route}: a process starts with ${id}'s prompt input in its environment" "0" "$status"
    if [ -f "$value" ] && cmp -s "$value" "$expected"; then
      pass "${route}: ${id}'s prompt file holds the whole composed prompt"
    else
      fail "${route}: ${id}'s prompt file holds the whole composed prompt"
    fi
  done
  if grep -q "$marker" "${work_dir}/output"; then
    fail "${route}: the prompt text stays out of the step's outputs"
  else
    pass "${route}: the prompt text stays out of the step's outputs"
  fi
}

# Generic mode's verbatim route: the caller's prompt_file becomes the whole prompt.
reset_runner_temp
status="$(run_step prompt MODE=generic PROMPT_FILE="$big_prompt")"
expect_equal "Compose prompt succeeds with a verbatim prompt over the limit" "0" "$status"
check_attempts verbatim "$big_prompt"

# The composed route: a review prompt the ledger context makes larger than the limit, as a large diff does.
reset_runner_temp
status="$(run_step prompt MODE=review REPOSITORY=example/repository EVENT_NAME=pull_request SEVERITY_RATINGS=emoji ALLOWED_REVIEW_STATES=COMMENT INCLUDE_SUGGESTIONS=true RESOLVE_STALE_THREADS=true FIX_PR_METADATA=true MARK_DRAFT_IF_UNREADY=false VERIFY_PRIOR_FINDINGS=true FIX_CI_FAILURES=false FIX_DIFF_FINDINGS=false ADD_REGRESSION_TESTS=false ALLOWED_TOOLS=Read LEDGER_CONTEXT="$big_prompt")"
expect_equal "Compose prompt succeeds with a composed prompt over the limit" "0" "$status"
composed="$(output_value "${work_dir}/output" file)"
if [ -f "$composed" ] && [ "$(wc -c < "$composed")" -gt "$prompt_bytes" ]; then
  pass "the composed prompt file holds more than the ledger context alone"
else
  fail "the composed prompt file holds more than the ledger context alone"
fi
check_attempts composed "$composed"

if grep -q 'steps\.prompt\.outputs\.text' "$action"; then
  fail "nothing in action.yml reads the prompt's text back out of a step output"
else
  pass "nothing in action.yml reads the prompt's text back out of a step output"
fi

finish
