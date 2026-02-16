You are performing an automated upstream sync for a composite GitHub Action
that wraps `anthropics/claude-code-action@v1`.

Ignore any shared prompt instructions about PR reviews, pending reviews, comment
hygiene, or cleanup steps — those do not apply to this task.

## Your task

Compare our wrapper action against the upstream action and update our files
to reflect any new, changed, or removed inputs/outputs.

## Files to read

1. `./action.yml` — our composite wrapper action
2. `./README.md` — our documentation
3. `/tmp/upstream/action.yml` — upstream action definition
4. `/tmp/upstream/README.md` — upstream documentation
5. `/tmp/upstream/release.json` — latest upstream release info
6. `/tmp/upstream/commits.json` — recent upstream commits

## What to compare

- **Inputs**: Every input in upstream's `action.yml` that we pass through
  (i.e., appears in our `with:` block under "Run Claude Code"). Check for:
  - New upstream inputs not yet in our `action.yml` → add them
  - Removed upstream inputs still in our `action.yml` → remove them
  - Changed descriptions or defaults → update ours to match
- **Outputs**: Every output in upstream's `action.yml`. Check for:
  - New outputs → add pass-through in our `outputs:` section
  - Removed outputs → remove from ours
- **README.md tables**: The "Action Inputs" and "Action Outputs" tables
  must match what's in our `action.yml` after updates.

## Rules

- Preserve our existing code style, comments, and section organisation.
- Preserve dual-org compatibility: never hardcode org names — use
  `YOUR_ORG` in README examples and `$REPO_OWNER` in prompt files.
- Do NOT touch any files in `prompts/` — those are org-specific.
- Do NOT touch `.github/workflows/claude-interactive.yml` or
  `.github/workflows/claude-review.yml` — those are consumer-facing.
- Do NOT modify `.github/workflows/upstream-sync.yml` (this workflow).
- Maintain the grouping comments in `action.yml` (e.g., `# Progress tracking`,
  `# Triggers`, `# Branch settings`, etc.).
- For new inputs: place them in a logical group, matching upstream's order
  where possible. Add them to the `with:` block in the "Run Claude Code" step.
- Keep our custom inputs (`mode`, `prompt_dir`, `pr_number`) that don't exist
  upstream — these are part of our wrapper's API.

## After making changes

If you made any meaningful changes:

1. Ensure the `upstream-sync` label exists (idempotent):
   `gh label create upstream-sync --description "Automated upstream sync" --color "0E8A16" --force`
2. Determine today's date in YYYYMMDD format using `date +%Y%m%d`.
3. Create a new branch: `claude/upstream-sync-<YYYYMMDD>`
4. Stage and commit changes with message:
   `chore: sync with upstream anthropics/claude-code-action`
5. Push the branch:
   `git push origin claude/upstream-sync-<YYYYMMDD>`
6. Create a PR with:

   ```bash
   gh pr create \
     --title "chore: sync with upstream anthropics/claude-code-action" \
     --body "Automated sync of inputs, outputs, and documentation with upstream anthropics/claude-code-action.

   ## Changes

   <summarise what changed>

   ## Upstream reference

   <include latest release tag and date from release.json>

   ---
   *Created automatically by the upstream-sync workflow.*" \
     --label "upstream-sync"
   ```

If there are NO meaningful changes (our action already reflects upstream),
do nothing — no branch, no commit, no PR. Just state that everything is
in sync.

## Reporting tool use issues

If any tool call is denied due to permission restrictions, report every
occurrence clearly in your final output. For each denied call, state:

- The tool name and the command you tried to run
- Why you needed it
- How you worked around it (or that you could not)

This information helps maintainers keep the `--allowedTools` list up to
date. Do not silently skip denied operations.
