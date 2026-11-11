#!/usr/bin/env bash
# Prints the facts of a pull request that "Compose prompt" tells the reviewer, as `name=value` lines for $GITHUB_OUTPUT, from the pull request's JSON as the REST API returns it.
#
# Usage: pull-request-facts.sh <pull-request-json-file>
# Output: `head_sha=<sha>` and `base_ref=<branch>`. Exits non-zero, printing nothing, when the file lacks either.
set -euo pipefail

[ "$#" -eq 1 ] || {
  echo "usage: pull-request-facts.sh <pull-request-json-file>" >&2
  exit 2
}

jq -r '"head_sha=\(.head.sha // error("no head.sha"))", "base_ref=\(.base.ref // error("no base.ref"))"' "$1"
