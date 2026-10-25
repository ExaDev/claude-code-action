#!/usr/bin/env bash
# Builds the issue description a triage run leaves behind, without the model ever writing the description itself.
#
# Usage: triage-issue-body.sh summary <execution-file>
#
# Usage: triage-issue-body.sh merge <summary-file> < current-body
#
# `summary` prints the text between the last <triage-summary> and </triage-summary> tags in the run's final result message, trimmed of surrounding whitespace. It prints nothing, and still exits 0, when the execution file is missing or unreadable, holds no result message, or the result carries no complete pair of tags: every caller treats empty output as "no summary this run".
#
# `merge` reads the issue's current description on stdin and prints it with the triage section set to the summary file's text. The section is wrapped in <!-- claude-triage:start --> and <!-- claude-triage:end --> markers: an existing section is replaced in place so a re-triage never duplicates it, and otherwise the section is appended after a blank line. Everything outside the markers is passed through byte for byte, and no trailing newline is added.
#
# The model must not write the description itself: the text it reads back through a tool result can be a compressed copy of the real one (Headroom, see docs/headroom.md), and a description written back from that copy loses its words for good. The description is therefore read from GitHub by the caller, in the runner, and merged here.
set -euo pipefail

case "${1:-}" in
  summary)
    execution_file="${2:-}"
    if [ -z "$execution_file" ] || [ ! -f "$execution_file" ]; then
      exit 0
    fi
    jq -r '
      (if type == "array" then ([.[] | select(type == "object" and .type == "result")] | last) else null end) as $result
      | ($result.result // "")
      | ([match("(?s)<triage-summary>(.*?)</triage-summary>"; "g")] | last | .captures[0].string) // empty
      | gsub("^\\s+|\\s+$"; "")
      | select(. != "")
    ' "$execution_file" 2>/dev/null || true
    ;;
  merge)
    summary_file="${2:-}"
    if [ -z "$summary_file" ] || [ ! -f "$summary_file" ]; then
      echo "usage: triage-issue-body.sh merge <summary-file> < current-body" >&2
      exit 2
    fi
    jq -j -n \
      --rawfile body /dev/stdin \
      --rawfile summary "$summary_file" '
      ($summary | gsub("^\\s+|\\s+$"; "")) as $text
      | ("<!-- claude-triage:start -->\n" + $text + "\n<!-- claude-triage:end -->") as $block
      | if ($body | test("(?s)<!-- claude-triage:start -->.*?<!-- claude-triage:end -->")) then $body | sub("(?s)<!-- claude-triage:start -->.*?<!-- claude-triage:end -->"; $block)
        elif ($body | test("^\\s*$")) then $block
        else ($body | sub("\\s+$"; "")) + "\n\n" + $block
        end
    '
    ;;
  *)
    echo "usage: triage-issue-body.sh summary <execution-file> | merge <summary-file>" >&2
    exit 2
    ;;
esac
