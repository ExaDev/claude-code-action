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

After submitting a review, do both of the following:

1. **Update the PR description** (the body of the PR itself, NOT a comment)
   with a concise summary of what the PR changes and why. Describe the actual
   modifications (new files, refactored logic, bug fixes), not the review
   status. You MUST use `gh pr edit` for this — do NOT use `gh pr comment`.
   Wrap your content in `<!-- claude:start -->` / `<!-- claude:end -->` markers.
   Preserve everything outside the markers. If no marker block exists, append
   yours at the end.

2. **Update PR labels** to reflect the outcome:
   - `gh pr edit {pr} --add-label "needs-changes"` after REQUEST_CHANGES
   - `gh pr edit {pr} --remove-label "needs-changes" --add-label "approved"` after APPROVE
   - Remove stale labels that no longer apply
   - Only manage labels that you have set — do not remove labels added by humans.
   - If a label does not exist, skip it — do not attempt to create labels.
