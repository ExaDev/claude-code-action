#!/usr/bin/env bash
# Says whether a failed credential attempt should stop the credential fallback chain, from the anthropics/claude-code-action execution file the attempt wrote, as GitHub output lines.
#
# Usage: attempt-stop.sh <execution-file> [<conclusion>]
#
# Meant for an attempt whose step failed. <conclusion> is the fork's own conclusion output for that attempt, which the fork sets only when its Claude Code run returned, so it is "success" when the run returned cleanly and the step failed afterwards, and empty when the fork threw first. A failure where Claude Code ran with that credential would only be repeated, side effects and all, by the next credential, so it stops the chain:
#   stop_reason=turn_limit            the final result's subtype is "error_max_turns": the run stopped at its turn limit, and the turn-limit wrap-up can resume it.
#   stop_reason=run_limit             the subtype is "error_max_budget_usd" or "error_max_structured_output_retries": the run used up its budget or its structured-output retries.
#   stop_reason=post_step_failed      the result reports "success" without is_error and <conclusion> is "success": Claude Code finished, and a later step of the fork failed (its "Post buffered inline comments" step runs under always() with no continue-on-error and exits 1 on any error, a failed GitHub API call for one).
#   stop_reason=result_not_accepted   the result reports "success" without is_error and <conclusion> is empty: the fork threw after the result arrived, which it does when the run took more turns than --max-turns allowed or returned no structured output for --json-schema, and in its catch around the SDK message loop, which would also catch the SDK's iterator failing to close after the result (that last case is not confirmed to happen).
# A turn_limit line is followed by session_id=<id> when the run's session id is a UUID, read from the final result message and otherwise from the system init message; an id of any other shape is never printed, because it is written to GITHUB_OUTPUT and interpolated into --resume. Prints nothing, and still exits 0, for every other failure ("error_during_execution", a "success" result with is_error:true, which is how a rejected credential or an API error reports, no result message, or a missing or invalid file): the next credential is then tried as before.
set -euo pipefail

execution_file="${1:-}"
conclusion="${2:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
result="$(bash "${script_dir}/execution-result.sh" "$execution_file")"
if [ -z "$result" ]; then
  exit 0
fi

subtype="$(jq -r '.subtype // empty' <<<"$result")"
is_error="$(jq -r '.is_error // false' <<<"$result")"
case "$subtype" in
error_max_turns)
  echo "stop_reason=turn_limit"
  session_id="$(jq -r '
    def id: select(type == "string" and . != "");
    ([.[] | select(type == "object" and .type == "result")] | last | .session_id | id)
    // ([.[] | select(type == "object" and .type == "system" and .subtype == "init")] | first | .session_id | id)
    // empty
  ' "$execution_file" 2>/dev/null || true)"
  if [[ "$session_id" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    echo "session_id=${session_id}"
  fi
  ;;
error_max_budget_usd | error_max_structured_output_retries)
  echo "stop_reason=run_limit"
  ;;
success)
  if [ "$is_error" = "false" ]; then
    if [ "$conclusion" = "success" ]; then
      echo "stop_reason=post_step_failed"
    else
      echo "stop_reason=result_not_accepted"
    fi
  fi
  ;;
esac
