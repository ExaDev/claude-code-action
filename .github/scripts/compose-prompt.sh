#!/usr/bin/env bash
# Concatenates prompt files with environment variable substitution.
#
# Layering order (later layers override/extend earlier):
# 1. Org-wide shared prompts (from SHARED_BASE)
# 2. Org-wide prompt_dir prompts (from SHARED_BASE)
# 3. Caller repo shared prompts (from current directory)
# 4. Caller repo prompt_dir prompts (from current directory)
#
# Usage: compose-prompt.sh <prompt-dir> [shared-base]
#   e.g. compose-prompt.sh code-review
#        compose-prompt.sh claude /path/to/shared
#
# Outputs the composed prompt to stdout.

set -euo pipefail

PROMPT_DIR="${1:?Usage: compose-prompt.sh <prompt-dir> [<shared-base>]}"
SHARED_BASE="${2:-.}"

PROMPT=""

# Org-wide prompts from shared base
for f in "$SHARED_BASE"/.github/prompts/shared/*.md "$SHARED_BASE"/.github/prompts/"$PROMPT_DIR"/*.md; do
  [ -f "$f" ] || continue
  PROMPT="${PROMPT}$(envsubst '$REPO $REPO_OWNER $REPO_NAME $PR_NUMBER' < "$f")"$'\n'
done

# Caller repo prompts (layered on top) - only if SHARED_BASE is different from current dir
if [ "$SHARED_BASE" != "." ]; then
  for f in .github/prompts/shared/*.md .github/prompts/"$PROMPT_DIR"/*.md; do
    [ -f "$f" ] || continue
    PROMPT="${PROMPT}$(envsubst '$REPO $REPO_OWNER $REPO_NAME $PR_NUMBER' < "$f")"$'\n'
  done
fi

printf '%s' "$PROMPT"
