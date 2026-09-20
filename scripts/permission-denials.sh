#!/usr/bin/env bash
# Prints how many tool calls the runner rejected during a run, as one line of JSON: {"count": <total>, "by_tool": {"<tool name>": <count>, ...}}.
#
# Usage: permission-denials.sh <execution-file>
#
# Each `result` message in an anthropics/claude-code-action execution file carries a `permission_denials` array with one entry per rejected call, and a run can hold more than one result message (a resumed session reports each), so the counts are summed across all of them. The file is read as a stream of JSON values and any top-level array is flattened, so this works whether the file is one array of messages or one message per line. Prints nothing, and still exits 0, when the file is missing or is not valid JSON: callers treat empty output as "unknown", never as zero.
set -euo pipefail

execution_file="${1:-}"
if [ -z "$execution_file" ] || [ ! -f "$execution_file" ]; then
  exit 0
fi

jq -cs '
  [ .[] | if type == "array" then .[] else . end
    | select(type == "object" and .type == "result")
    | (.permission_denials // [])[] ]
  | { count: length, by_tool: (group_by(.tool_name) | map({ key: (.[0].tool_name // "unknown"), value: length }) | from_entries) }
' "$execution_file" 2>/dev/null || true
