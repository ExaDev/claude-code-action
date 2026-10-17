#!/usr/bin/env bash
# Tests for the scripts that read an upstream execution file, and for the action.yml steps that decide from them whether a run stopped at its turn limit. The steps' own run: scripts are taken out of action.yml and run against the fixtures in scripts/test-fixtures, so what is tested is what the action runs. Needs bash, jq and awk, which every GitHub-hosted runner has.
#
# Usage: bash scripts/execution-scripts.test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixtures="${repo_root}/scripts/test-fixtures"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

failures=0
passes=0

pass() {
  passes=$((passes + 1))
  echo "ok - $1"
}

fail() {
  failures=$((failures + 1))
  echo "not ok - $1"
}

expect_equal() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name (expected '${expected}', got '${actual}')"
  fi
}

# The body of the run: block of the step with the given id, unindented, as the runner would execute it.
step_script() {
  awk -v id="$1" '
    $0 == "      id: " id { in_step = 1; next }
    in_step && /^    - / { exit }
    in_step && $0 == "      run: |" { in_run = 1; next }
    in_run {
      if ($0 != "" && substr($0, 1, 8) != "        ") { exit }
      print substr($0, 9)
    }
  ' "${repo_root}/action.yml"
}

# The value written for a field in a GitHub output file, in either the name=value or the name<<DELIMITER form.
output_value() {
  local file="$1" field="$2"
  awk -v field="$field" '
    delimiter != "" { if ($0 == delimiter) { exit } print; next }
    index($0, field "<<") == 1 { delimiter = substr($0, length(field) + 3); next }
    index($0, field "=") == 1 { print substr($0, length(field) + 2); exit }
  ' "$file"
}

# Runs a step's script with the given environment assignments; prints its exit status, with the output file at $work_dir/output.
run_step() {
  local id="$1"
  shift
  local script="${work_dir}/${id}.sh"
  step_script "$id" > "$script"
  if [ ! -s "$script" ]; then
    echo "no run: script for step ${id}" >&2
    exit 1
  fi
  : > "${work_dir}/output"
  local status=0
  env -i PATH="$PATH" GITHUB_OUTPUT="${work_dir}/output" ACTION_PATH="$repo_root" "$@" bash "$script" > "${work_dir}/stdout" 2>&1 || status=$?
  echo "$status"
}

result_subtype() {
  bash "${repo_root}/scripts/execution-result.sh" "$1" | jq -r '.subtype // empty'
}

session_id() {
  bash "${repo_root}/scripts/turn-limited-session-id.sh" "$1"
}

printf 'not json' > "${work_dir}/invalid.json"

# execution-result.sh
expect_equal "execution-result.sh reads a finished run's subtype" "success" "$(result_subtype "${fixtures}/success.json")"
expect_equal "execution-result.sh reads a turn-limited run's subtype" "error_max_turns" "$(result_subtype "${fixtures}/max-turns.json")"
expect_equal "execution-result.sh prints nothing for invalid JSON" "" "$(result_subtype "${work_dir}/invalid.json")"
expect_equal "execution-result.sh prints nothing when there is no result message" "" "$(result_subtype "${fixtures}/no-result.json")"
expect_equal "execution-result.sh prints nothing for a missing file" "" "$(result_subtype "${work_dir}/missing.json")"

# turn-limited-session-id.sh
expect_equal "a turn-limited run gives its session id" "session-max-turns" "$(session_id "${fixtures}/max-turns.json")"
expect_equal "a finished run gives no session id" "" "$(session_id "${fixtures}/success.json")"
expect_equal "a finished run whose prompt talks about hitting the limit gives no session id" "" "$(session_id "${fixtures}/success-mentions-limit.json")"
expect_equal "a run that failed some other way gives no session id" "" "$(session_id "${fixtures}/during-execution.json")"
expect_equal "a turn-limited run with no init message gives no session id" "" "$(session_id "${fixtures}/max-turns-no-session.json")"
expect_equal "invalid JSON gives no session id" "" "$(session_id "${work_dir}/invalid.json")"
expect_equal "no result message gives no session id" "" "$(session_id "${fixtures}/no-result.json")"

# Check whether attempt N hit its turn limit
status="$(run_step turn_limit_2 EXECUTION_FILE="${fixtures}/max-turns.json")"
expect_equal "the turn-limit check succeeds on a turn-limited attempt" "0" "$status"
expect_equal "the turn-limit check marks a turn-limited attempt" "true" "$(output_value "${work_dir}/output" hit_limit)"
expect_equal "the turn-limit check hands on the session id" "session-max-turns" "$(output_value "${work_dir}/output" session_id)"
expect_equal "the turn-limit check hands on the execution file" "${fixtures}/max-turns.json" "$(output_value "${work_dir}/output" execution_file)"
status="$(run_step turn_limit_2 EXECUTION_FILE="${fixtures}/during-execution.json")"
expect_equal "the turn-limit check succeeds on an attempt that failed some other way" "0" "$status"
expect_equal "the turn-limit check leaves an attempt that failed some other way unmarked" "" "$(output_value "${work_dir}/output" hit_limit)"

# The credential chain stops at a turn-limited attempt, and stays stopped after a success.
for n in 1 2 3 4; do
  next=$((n + 1))
  condition="$(awk -v id="attempt_${next}" '$0 == "      id: " id { getline; print; exit }' "${repo_root}/action.yml")"
  expected="      if: steps.credentials.outputs.cred_${next}_token != '' && steps.attempt_${n}.outcome == 'failure' && steps.attempt_${n}_retry.outcome != 'success' && steps.turn_limit_${n}.outputs.hit_limit != 'true'"
  expect_equal "attempt ${next} runs only after attempt ${n} failed without reaching its turn limit" "$expected" "$condition"
done

# Resolve Claude Code result
status="$(run_step claude OUTCOME_1=success CONCLUSION_1=success SESSION_ID_1=session-success EXECUTION_FILE_1="${fixtures}/success.json" CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CREDENTIAL_COUNT=2)"
expect_equal "Resolve succeeds on a successful attempt" "0" "$status"
expect_equal "Resolve hands on the successful attempt's session" "session-success" "$(output_value "${work_dir}/output" session_id)"
expect_equal "Resolve reports the successful attempt's conclusion" "success" "$(output_value "${work_dir}/output" conclusion)"

status="$(run_step claude OUTCOME_1=failure OUTCOME_2=failure EXECUTION_FILE_2="${fixtures}/max-turns.json" HIT_LIMIT_2=true HIT_LIMIT_SESSION_ID_2=session-max-turns HIT_LIMIT_EXECUTION_FILE_2="${fixtures}/max-turns.json" CRED_TYPE_2=key CRED_TOKEN_2=token-two CREDENTIAL_COUNT=3)"
expect_equal "Resolve still fails when an attempt stopped at its turn limit" "1" "$status"
expect_equal "Resolve hands on the turn-limited attempt's session" "session-max-turns" "$(output_value "${work_dir}/output" session_id)"
expect_equal "Resolve hands on the turn-limited attempt's execution file" "${fixtures}/max-turns.json" "$(output_value "${work_dir}/output" execution_file)"
expect_equal "Resolve reports a turn-limited run as a failure" "failure" "$(output_value "${work_dir}/output" conclusion)"
expect_equal "Resolve hands on the turn-limited attempt's credential type" "key" "$(output_value "${work_dir}/output" winning_cred_type)"
expect_equal "Resolve hands on the turn-limited attempt's credential" "token-two" "$(output_value "${work_dir}/output" winning_cred_token)"

status="$(run_step claude OUTCOME_1=failure EXECUTION_FILE_1="${fixtures}/during-execution.json" CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CREDENTIAL_COUNT=1)"
expect_equal "Resolve fails when every attempt failed" "1" "$status"
expect_equal "Resolve hands on no session when no attempt succeeded or stopped at its turn limit" "" "$(output_value "${work_dir}/output" session_id)"

# Detect turn-limit hit
status="$(run_step detect-turn-limit SESSION_ID=session-max-turns EXEC_FILE="${fixtures}/max-turns.json")"
expect_equal "detection succeeds on a turn-limited run" "0" "$status"
expect_equal "detection reports a turn-limited run" "true" "$(output_value "${work_dir}/output" hit_limit)"
run_step detect-turn-limit SESSION_ID=session-mentions-limit EXEC_FILE="${fixtures}/success-mentions-limit.json" > /dev/null
expect_equal "detection ignores a finished run whose transcript mentions limits" "false" "$(output_value "${work_dir}/output" hit_limit)"
run_step detect-turn-limit SESSION_ID=session-success EXEC_FILE="${fixtures}/success.json" > /dev/null
expect_equal "detection ignores a finished run" "false" "$(output_value "${work_dir}/output" hit_limit)"

# Resolve fails on a turn-limited run, so every step that acts on it must run after a failed step, but not after a cancellation.
step_condition() {
  awk -v id="$1" '$0 == "      id: " id { getline; print; exit }' "${repo_root}/action.yml"
}
for id in detect-turn-limit wrap-up wrap-up-summary escalate; do
  case "$(step_condition "$id")" in
  "      if: \${{ !cancelled() && "*) pass "${id} runs after a failed Resolve unless the run was cancelled" ;;
  *) fail "${id} runs after a failed Resolve unless the run was cancelled" ;;
  esac
done

echo "${passes} passed, ${failures} failed"
[ "$failures" -eq 0 ]
