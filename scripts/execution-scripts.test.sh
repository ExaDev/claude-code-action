#!/usr/bin/env bash
# Tests for the scripts that read and manage an upstream execution file, and for the action.yml steps built on them: the credential chain's stop decision, Resolve Claude Code result and turn-limit detection. The steps' own run: scripts are taken out of action.yml and run against the fixtures in scripts/test-fixtures, and the expression-built lines that wire them together (conditions, environment entries, arguments) are checked as written, so what is tested is what the action runs. Needs bash, jq and awk, which every GitHub-hosted runner has.
#
# Usage: bash scripts/execution-scripts.test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${repo_root}/action.yml"
fixtures="${repo_root}/scripts/test-fixtures"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
runner_temp="${work_dir}/runner-temp"
shared="${runner_temp}/claude-execution-output.json"

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

expect_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (no '${needle}' in '${haystack}')"
  fi
}

# Every line of the step with the given id, from its id line up to the next step.
step_lines() {
  awk -v id="$1" '
    $0 == "      id: " id { in_step = 1; print; next }
    in_step && /^    - / { exit }
    in_step { print }
  ' "$action"
}

# The body of the run: block of the step with the given id, unindented, as the runner would execute it.
step_script() {
  step_lines "$1" | awk '
    $0 == "      run: |" { in_run = 1; next }
    in_run {
      if ($0 != "" && substr($0, 1, 8) != "        ") { exit }
      print substr($0, 9)
    }
  '
}

# The value of a step's own `key: value` line (its condition, or an entry of its with: or env: block).
step_value() {
  step_lines "$1" | awk -v key="$2" '
    index($0, "      " key ": ") == 1 { print substr($0, length(key) + 9); exit }
    index($0, "        " key ": ") == 1 { print substr($0, length(key) + 11); exit }
  '
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

reset_runner_temp() {
  rm -rf "$runner_temp"
  mkdir -p "$runner_temp"
}

# Runs a step's script with the given environment assignments and prints its exit status; its output file is $work_dir/output and its log $work_dir/stdout.
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
  env -i PATH="$PATH" GITHUB_OUTPUT="${work_dir}/output" ACTION_PATH="$repo_root" RUNNER_TEMP="$runner_temp" "$@" bash "$script" > "${work_dir}/stdout" 2>&1 || status=$?
  echo "$status"
}

result_subtype() {
  bash "${repo_root}/scripts/execution-result.sh" "$1" | jq -r '.subtype // empty'
}

stop_lines() {
  bash "${repo_root}/scripts/attempt-stop.sh" "$1" | paste -sd ' ' -
}

printf 'not json' > "${work_dir}/invalid.json"

# execution-result.sh
expect_equal "execution-result.sh reads a finished run's subtype" "success" "$(result_subtype "${fixtures}/success.json")"
expect_equal "execution-result.sh reads a turn-limited run's subtype" "error_max_turns" "$(result_subtype "${fixtures}/max-turns.json")"
expect_equal "execution-result.sh prints nothing for invalid JSON" "" "$(result_subtype "${work_dir}/invalid.json")"
expect_equal "execution-result.sh prints nothing when there is no result message" "" "$(result_subtype "${fixtures}/no-result.json")"
expect_equal "execution-result.sh prints nothing for a missing file" "" "$(result_subtype "${work_dir}/missing.json")"

# attempt-stop.sh
expect_equal "a turn-limited run stops the chain with its result's session id" "stop_reason=turn_limit session_id=33333333-3333-4333-8333-333333333333" "$(stop_lines "${fixtures}/max-turns.json")"
expect_equal "a turn-limited run with no init message takes the result's session id" "stop_reason=turn_limit session_id=44444444-4444-4444-8444-444444444444" "$(stop_lines "${fixtures}/max-turns-no-init.json")"
expect_equal "the final result's session id wins over the init message's" "stop_reason=turn_limit session_id=dddddddd-dddd-4ddd-8ddd-dddddddddddd" "$(stop_lines "${fixtures}/max-turns-ids-differ.json")"
expect_equal "a turn-limited run whose result has no session id falls back to the init message" "stop_reason=turn_limit session_id=55555555-5555-4555-8555-555555555555" "$(stop_lines "${fixtures}/max-turns-init-only.json")"
expect_equal "a turn-limited run with no session id still stops the chain" "stop_reason=turn_limit" "$(stop_lines "${fixtures}/max-turns-no-session.json")"
expect_equal "a session id that is not a UUID is never printed" "stop_reason=turn_limit" "$(stop_lines "${fixtures}/max-turns-bad-session.json")"
expect_equal "a run out of budget stops the chain without a wrap-up" "stop_reason=ran_and_failed" "$(stop_lines "${fixtures}/max-budget.json")"
expect_equal "a run out of structured-output retries stops the chain without a wrap-up" "stop_reason=ran_and_failed" "$(stop_lines "${fixtures}/max-structured-output-retries.json")"
expect_equal "a failed attempt whose result reports success stops the chain without a wrap-up" "stop_reason=ran_and_failed" "$(stop_lines "${fixtures}/success.json")"
expect_equal "a finished run whose prompt talks about hitting the limit is not a turn-limit hit" "stop_reason=ran_and_failed" "$(stop_lines "${fixtures}/success-mentions-limit.json")"
expect_equal "a rejected credential falls through" "" "$(stop_lines "${fixtures}/api-error.json")"
expect_equal "a rate-limited attempt falls through" "" "$(stop_lines "${fixtures}/rate-limited.json")"
expect_equal "an execution error falls through" "" "$(stop_lines "${fixtures}/during-execution.json")"
expect_equal "no result message falls through" "" "$(stop_lines "${fixtures}/no-result.json")"
expect_equal "invalid JSON falls through" "" "$(stop_lines "${work_dir}/invalid.json")"
expect_equal "a missing file falls through" "" "$(stop_lines "${work_dir}/missing.json")"

# execution-file.sh
reset_runner_temp
cp "${fixtures}/success.json" "$shared"
RUNNER_TEMP="$runner_temp" bash "${repo_root}/scripts/execution-file.sh" clear
expect_equal "clear removes the shared execution file" "absent" "$([ -e "$shared" ] && echo present || echo absent)"
cp "${fixtures}/max-turns.json" "$shared"
kept="$(RUNNER_TEMP="$runner_temp" bash "${repo_root}/scripts/execution-file.sh" keep 3R)"
expect_equal "keep prints the slot's own path" "${runner_temp}/claude-execution-output-attempt-3R.json" "$kept"
expect_equal "keep moves the shared file there" "error_max_turns absent" "$(result_subtype "$kept") $([ -e "$shared" ] && echo present || echo absent)"
expect_equal "keep prints nothing when there is no file" "" "$(RUNNER_TEMP="$runner_temp" bash "${repo_root}/scripts/execution-file.sh" keep 4)"
status=0
RUNNER_TEMP="$runner_temp" bash "${repo_root}/scripts/execution-file.sh" keep 6 2> /dev/null || status=$?
expect_equal "keep refuses a slot outside 1 to 5" "1" "$status"

# Clear the execution file before the first attempt
reset_runner_temp
cp "${fixtures}/success.json" "$shared"
run_step clear-execution-file > /dev/null
expect_equal "the first attempt starts with no execution file" "absent" "$([ -e "$shared" ] && echo present || echo absent)"

expect_equal "the execution file is always cleared, whatever happened before" "" "$(step_value clear-execution-file if)"
clear_line="$(grep -nxF "      id: clear-execution-file" "$action" | cut -d: -f1)"
attempt_line="$(grep -nxF "      id: attempt_1" "$action" | cut -d: -f1)"
expect_equal "the execution file is cleared before attempt 1 runs" "true" "$([ -n "$clear_line" ] && [ -n "$attempt_line" ] && [ "$clear_line" -lt "$attempt_line" ] && echo true || echo false)"

# Rate-limit retry gates keep the attempt's own file before its retry overwrites the shared one.
reset_runner_temp
cp "${fixtures}/rate-limited.json" "$shared"
run_step retry_gate_2 EXECUTION_FILE="$shared" WAIT_SECONDS=0 > /dev/null
expect_equal "a retried attempt's execution file is kept as its own" "should_retry=true kept" "should_retry=$(output_value "${work_dir}/output" should_retry) $([ -f "${runner_temp}/claude-execution-output-attempt-2.json" ] && echo kept || echo missing)"

# Check whether attempt N should stop the credential chain
reset_runner_temp
cp "${fixtures}/max-turns.json" "$shared"
status="$(run_step chain_stop_2 SLOT=2R)"
expect_equal "the chain-stop check succeeds on a turn-limited attempt" "0" "$status"
expect_equal "the chain-stop check stops the chain for a turn-limited attempt" "turn_limit" "$(output_value "${work_dir}/output" stop_reason)"
expect_equal "the chain-stop check hands on the session id" "33333333-3333-4333-8333-333333333333" "$(output_value "${work_dir}/output" session_id)"
expect_equal "the chain-stop check hands on the slot's kept execution file" "${runner_temp}/claude-execution-output-attempt-2R.json" "$(output_value "${work_dir}/output" execution_file)"
reset_runner_temp
cp "${fixtures}/max-budget.json" "$shared"
run_step chain_stop_2 SLOT=2 > /dev/null
expect_equal "the chain-stop check stops the chain for a run out of budget" "ran_and_failed" "$(output_value "${work_dir}/output" stop_reason)"
reset_runner_temp
cp "${fixtures}/api-error.json" "$shared"
status="$(run_step chain_stop_2 SLOT=2)"
expect_equal "the chain-stop check succeeds on a rejected credential" "0" "$status"
expect_equal "the chain-stop check lets a rejected credential fall through" "" "$(output_value "${work_dir}/output" stop_reason)"
expect_equal "the chain-stop check still keeps a rejected credential's file aside" "absent" "$([ -e "$shared" ] && echo present || echo absent)"

# The expression-built wiring of every slot.
for n in 1 2 3 4 5; do
  expect_equal "chain_stop_${n} runs when attempt ${n} and any retry of it failed" "steps.attempt_${n}.outcome == 'failure' && steps.attempt_${n}_retry.outcome != 'success'" "$(step_value "chain_stop_${n}" if)"
  expect_equal "chain_stop_${n} falls through rather than skipping the chain when it fails" "true" "$(step_value "chain_stop_${n}" continue-on-error)"
  expect_equal "chain_stop_${n} reads slot ${n}'s latest run" "\${{ steps.attempt_${n}_retry.outcome == 'failure' && '${n}R' || '${n}' }}" "$(step_value "chain_stop_${n}" SLOT)"
  expect_equal "retry_gate_${n} reads attempt ${n}'s execution file" "\${{ steps.attempt_${n}.outputs.execution_file }}" "$(step_value "retry_gate_${n}" EXECUTION_FILE)"
  expect_equal "retry_gate_${n} keeps attempt ${n}'s file as slot ${n}'s own before retrying" "1" "$(step_script "retry_gate_${n}" | grep -cxF "  bash \"\${ACTION_PATH}/scripts/execution-file.sh\" keep ${n} > /dev/null")"
  expect_equal "attempt ${n}'s retry runs only when its rate-limit gate says so" "steps.retry_gate_${n}.outputs.should_retry == 'true'" "$(step_value "attempt_${n}_retry" if)"
  for field in REASON SESSION_ID EXECUTION_FILE; do
    output_name="$(tr '[:upper:]' '[:lower:]' <<<"$field")"
    [ "$field" = "REASON" ] && output_name="stop_reason"
    expect_equal "Resolve reads slot ${n}'s ${output_name} from chain_stop_${n}" "\${{ steps.chain_stop_${n}.outputs.${output_name} }}" "$(step_value claude "STOP_${field}_${n}")"
  done
done
for n in 1 2 3 4; do
  next=$((n + 1))
  expect_equal "attempt ${next} runs only after attempt ${n} failed without stopping the chain" "steps.credentials.outputs.cred_${next}_token != '' && steps.attempt_${n}.outcome == 'failure' && steps.attempt_${n}_retry.outcome != 'success' && steps.chain_stop_${n}.outputs.stop_reason == ''" "$(step_value "attempt_${next}" if)"
done

# Resolve Claude Code result
reset_runner_temp
status="$(run_step claude OUTCOME_1=success CONCLUSION_1=success SESSION_ID_1=11111111-1111-4111-8111-111111111111 EXECUTION_FILE_1="${fixtures}/success.json" CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CREDENTIAL_COUNT=2)"
expect_equal "Resolve succeeds on a successful attempt" "0" "$status"
expect_equal "Resolve hands on the successful attempt's session" "11111111-1111-4111-8111-111111111111" "$(output_value "${work_dir}/output" session_id)"
expect_equal "Resolve reports the successful attempt's conclusion" "success" "$(output_value "${work_dir}/output" conclusion)"

reset_runner_temp
cp "${fixtures}/api-error.json" "${runner_temp}/claude-execution-output-attempt-1.json"
cp "${fixtures}/max-turns.json" "${runner_temp}/claude-execution-output-attempt-2.json"
status="$(run_step claude OUTCOME_1=failure OUTCOME_2=failure STOP_REASON_2=turn_limit STOP_SESSION_ID_2=33333333-3333-4333-8333-333333333333 STOP_EXECUTION_FILE_2="${runner_temp}/claude-execution-output-attempt-2.json" CRED_TYPE_2=key CRED_TOKEN_2=token-two CREDENTIAL_COUNT=3)"
expect_equal "Resolve still fails when an attempt stopped at its turn limit" "1" "$status"
expect_equal "Resolve hands on the turn-limited attempt's session" "33333333-3333-4333-8333-333333333333" "$(output_value "${work_dir}/output" session_id)"
expect_equal "Resolve hands on the turn-limited attempt's execution file" "${runner_temp}/claude-execution-output-attempt-2.json" "$(output_value "${work_dir}/output" execution_file)"
expect_equal "Resolve reports a turn-limited run as a failure" "failure" "$(output_value "${work_dir}/output" conclusion)"
expect_equal "Resolve hands on the turn-limited attempt's credential type" "key" "$(output_value "${work_dir}/output" winning_cred_type)"
expect_equal "Resolve hands on the turn-limited attempt's credential" "token-two" "$(output_value "${work_dir}/output" winning_cred_token)"
expect_contains "Resolve diagnoses an earlier rejected credential from its own kept file before stopping" "Run Claude Code (attempt 1) failed: subtype=success, is_error=true, api_error_status=403" "$(cat "${work_dir}/stdout")"
expect_contains "Resolve says the turn limit stopped the chain" "Run Claude Code (attempt 2) stopped at its turn limit" "$(cat "${work_dir}/stdout")"

reset_runner_temp
cp "${fixtures}/max-budget.json" "${runner_temp}/claude-execution-output-attempt-1.json"
status="$(run_step claude OUTCOME_1=failure STOP_REASON_1=ran_and_failed STOP_EXECUTION_FILE_1="${runner_temp}/claude-execution-output-attempt-1.json" CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CREDENTIAL_COUNT=2)"
expect_equal "Resolve fails when an attempt ran and failed" "1" "$status"
expect_equal "Resolve hands on no session for a run that is not wrapped up" "" "$(output_value "${work_dir}/output" session_id)"
expect_contains "Resolve says why the chain stopped" "stop reason ran_and_failed" "$(cat "${work_dir}/stdout")"

reset_runner_temp
status="$(run_step claude OUTCOME_1=failure EXECUTION_FILE_1="${fixtures}/during-execution.json" CRED_TYPE_1=oauth CRED_TOKEN_1=token-one CREDENTIAL_COUNT=1)"
expect_equal "Resolve fails when every attempt failed" "1" "$status"
expect_equal "Resolve hands on no session when no attempt succeeded or stopped the chain" "" "$(output_value "${work_dir}/output" session_id)"

# Detect turn-limit hit
run_step detect-turn-limit SESSION_ID=33333333-3333-4333-8333-333333333333 EXEC_FILE="${fixtures}/max-turns.json" > /dev/null
expect_equal "detection reports a turn-limited run" "true" "$(output_value "${work_dir}/output" hit_limit)"
run_step detect-turn-limit SESSION_ID=66666666-6666-4666-8666-666666666666 EXEC_FILE="${fixtures}/max-budget.json" > /dev/null
expect_equal "detection does not wrap up a run out of budget" "false" "$(output_value "${work_dir}/output" hit_limit)"
run_step detect-turn-limit SESSION_ID=22222222-2222-4222-8222-222222222222 EXEC_FILE="${fixtures}/success-mentions-limit.json" > /dev/null
expect_equal "detection ignores a finished run whose transcript mentions limits" "false" "$(output_value "${work_dir}/output" hit_limit)"
run_step detect-turn-limit SESSION_ID=11111111-1111-4111-8111-111111111111 EXEC_FILE="${fixtures}/success.json" > /dev/null
expect_equal "detection ignores a finished run" "false" "$(output_value "${work_dir}/output" hit_limit)"

# The wrap-up and the steps around it.
for id in detect-turn-limit wrap-up wrap-up-summary escalate; do
  case "$(step_value "$id" if)" in
  "\${{ !cancelled() && "*) pass "${id} runs after a failed Resolve unless the run was cancelled" ;;
  *) fail "${id} runs after a failed Resolve unless the run was cancelled" ;;
  esac
done
case "$(step_value wrap-up claude_args)" in
"\"--resume \${{ steps.claude.outputs.session_id }} "*) pass "the wrap-up resumes the session Resolve handed on" ;;
*) fail "the wrap-up resumes the session Resolve handed on" ;;
esac
for id in wrap-up escalate apply-fixes structured-summary; do
  for input in use_bedrock use_vertex use_foundry anthropic_federation_rule_id anthropic_organization_id anthropic_service_account_id anthropic_workspace_id anthropic_oidc_audience; do
    expect_equal "${id} passes ${input} through" "\${{ inputs.${input} }}" "$(step_value "$id" "$input")"
  done
done

echo "${passes} passed, ${failures} failed"
[ "$failures" -eq 0 ]
