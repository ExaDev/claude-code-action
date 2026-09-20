#!/usr/bin/env bash
# Prints the final `result` message from an anthropics/claude-code-action execution file as one line of JSON, reduced to the fields callers act on: subtype, is_error, api_error_status, result and errors.
#
# Usage: execution-result.sh <execution-file>
#
# The execution file upstream writes is a JSON array of every SDK message from the run (base-action/src/execution-file.ts serialises the whole `messages` array), not an object, so the final result has to be picked out of the array. Prints nothing, and still exits 0, when the file is missing, is not valid JSON, is not an array, or holds no result message: the run failed before Claude produced one, and every caller treats empty output as "unknown" rather than as an error.
set -euo pipefail

execution_file="${1:-}"
if [ -z "$execution_file" ] || [ ! -f "$execution_file" ]; then
  exit 0
fi

jq -c '
  if type == "array" then ([.[] | select(type == "object" and .type == "result")] | last) else null end
  | select(. != null)
  | {subtype, is_error, api_error_status, result, errors}
' "$execution_file" 2>/dev/null || true
