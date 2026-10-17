#!/usr/bin/env bash
# Manages the execution file the pinned anthropics/claude-code-action fork writes, which is the same path for every credential attempt in a job ($RUNNER_TEMP/claude-execution-output.json, fixed in the fork's base-action/src/execution-file.ts), so each attempt would otherwise overwrite the one before it, and an attempt that failed before writing its own would report the previous attempt's file as its own.
#
# Usage:
#   execution-file.sh clear         removes the shared file, before the first attempt.
#   execution-file.sh keep <slot>   moves the shared file aside as attempt <slot>'s own (a slot is 1 to 5, with R for that slot's retry) and prints the new path; prints nothing when there is no file to keep.
set -euo pipefail

shared="${RUNNER_TEMP:?RUNNER_TEMP must be set}/claude-execution-output.json"

case "${1:-}" in
clear)
  rm -f "$shared"
  ;;
keep)
  slot="${2:-}"
  if ! [[ "$slot" =~ ^[1-5]R?$ ]]; then
    echo "execution-file.sh keep: slot must be 1 to 5, optionally followed by R; got '${slot}'." >&2
    exit 1
  fi
  if [ -f "$shared" ]; then
    kept="${RUNNER_TEMP}/claude-execution-output-attempt-${slot}.json"
    mv "$shared" "$kept"
    echo "$kept"
  fi
  ;;
*)
  echo "usage: execution-file.sh clear | keep <slot>" >&2
  exit 1
  ;;
esac
