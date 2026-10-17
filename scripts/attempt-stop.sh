#!/usr/bin/env bash
# Says whether a failed credential attempt should stop the credential fallback chain, from the anthropics/claude-code-action execution file the attempt wrote, as GitHub output lines.
#
# Usage: attempt-stop.sh <execution-file>
#
# Meant for an attempt whose step failed. A failure where Claude Code ran with that credential would only be repeated, side effects and all, by the next credential, so it stops the chain:
#   stop_reason=turn_limit   the final result's subtype is "error_max_turns": the run stopped at its turn limit, and the turn-limit wrap-up can resume it.
#   stop_reason=ran_and_failed   the subtype is "error_max_budget_usd" or "error_max_structured_output_retries", or the result reports "success" without is_error, which a failed step means the pinned fork rejected afterwards (more turns than --max-turns allowed, or no structured output for --json-schema).
# A turn_limit line is followed by session_id=<id> when the run's session id is a UUID, read from the final result message and otherwise from the system init message; an id of any other shape is never printed, because it is written to GITHUB_OUTPUT and interpolated into --resume. Prints nothing, and still exits 0, for every other failure ("error_during_execution", a "success" result with is_error:true, which is how a rejected credential or an API error reports, no result message, or a missing or invalid file): the next credential is then tried as before.
set -euo pipefail

execution_file="${1:-}"
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
  echo "stop_reason=ran_and_failed"
  ;;
success)
  if [ "$is_error" = "false" ]; then
    echo "stop_reason=ran_and_failed"
  fi
  ;;
esac
