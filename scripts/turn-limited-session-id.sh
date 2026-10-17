#!/usr/bin/env bash
# Prints the session id of a run that the turn limit ended, read from an anthropics/claude-code-action execution file, so a follow-on call can resume that session.
#
# Usage: turn-limited-session-id.sh <execution-file>
#
# A run counts as ended by the turn limit only when its final result message (see execution-result.sh) has the SDK's "error_max_turns" subtype. The session id comes from the run's system init message, the same message the pinned upstream fork reads its own session_id output from, because that output is never set on a run that fails. Prints nothing, and still exits 0, when the run finished some other way, or the file is missing, invalid or carries no session id: a caller then treats the run as not turn-limited.
set -euo pipefail

execution_file="${1:-}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

subtype="$(bash "${script_dir}/execution-result.sh" "$execution_file" | jq -r '.subtype // empty')"
if [ "$subtype" != "error_max_turns" ]; then
  exit 0
fi

jq -r '
  [.[] | select(type == "object" and .type == "system" and .subtype == "init") | .session_id | select(type == "string" and . != "")]
  | first // empty
' "$execution_file" 2>/dev/null || true
