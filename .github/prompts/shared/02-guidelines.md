Submit PR reviews using the pending review flow so all comments arrive as one review:

1. `mcp__github__create_pending_pull_request_review` — start a pending review
2. `mcp__github__get_pull_request_diff` — read the diff to identify lines
3. `mcp__github__add_comment_to_pending_review` — add each inline comment
4. `mcp__github__submit_pending_pull_request_review` — submit with a verdict

Submit with **APPROVE**, **REQUEST_CHANGES**, or **COMMENT**. Pick one:

- **APPROVE** — good to merge, even with minor suggestions
- **REQUEST_CHANGES** — issues that must be fixed before merge
- **COMMENT** — observations without a verdict

For concrete fixes, include a suggestion block:

```suggestion
corrected or improved code here
```

Before suggesting a fix, verify the correct replacement by checking the codebase.
Do not guess — a wrong suggestion is worse than a comment describing the problem.

Every suggestion must contain complete, valid code. Never submit an empty or
placeholder suggestion — use a regular comment instead.

When the same issue repeats across files, explain the pattern once in the first
comment. Still provide a suggestion block on each occurrence so the author can
click "Apply" on all of them. Keep subsequent comments brief.

After submitting a review, check the PR title and description with
`gh pr view $PR_NUMBER`. Fix what needs fixing:

- **Title**: If it's vague, generic, or doesn't reflect the actual changes,
  update it with `gh pr edit $PR_NUMBER --title "concise title"`. Keep it under
  70 characters. Don't change titles that are already clear and accurate.
- **Description**: Update ONLY if it's missing or incomplete. Skip if it already
  has a clear summary of changes.

When updating, add only what's missing. Use headings only when organizing
multiple distinct sections — a single paragraph needs no `## Summary` heading
since the marker block already provides context.

```bash
gh pr edit $PR_NUMBER --body "$(cat <<'EOF'
<!-- claude:start -->
<only add information not already present in the description>
<!-- claude:end -->
EOF
)"
```

The markers `<!-- claude:start -->` / `<!-- claude:end -->` identify your
section. Preserve everything outside the markers. If no marker block exists,
append yours at the end. Do NOT repeat information already in the PR body.
