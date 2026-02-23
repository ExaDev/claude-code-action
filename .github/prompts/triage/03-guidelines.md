## Triage quality guidelines

**Type assignment:**

- Only set a type if the issue clearly matches one of the available types.
- If the issue is ambiguous, leave the type unset rather than guessing.

**Label assignment:**

- Only use labels that already exist in the repository — never create new ones.
- Prefer fewer, accurate labels over many speculative ones.
- If the repo uses a structured label scheme (e.g. `area:`, `priority:`,
  `kind:`), follow it.

**Parent/sub-issue relationships:**

- Only set a parent if this issue is clearly a sub-task or component of the
  parent issue — not merely related by topic.
- Do not set parent relationships based on keyword overlap alone. The issue
  must logically be a piece of work that contributes to completing the parent.

**Blocker relationships:**

- Only note blockers when the issue text explicitly states a dependency
  (e.g. "blocked by #42", "depends on #42", "requires #42 first").
- Do not infer blockers from topical similarity.

**Issue body updates:**

The `update_issue_body` setting is currently: `$UPDATE_ISSUE_BODY`. Only update
the issue body if this value is `true`.

**Re-triage:**

- When re-triaging (triggered by the `$TRIAGE_LABEL` label), check what
  metadata is already set.
- Do not remove existing type or labels unless they are clearly wrong.

**Error handling:**

- If a tool call fails (e.g. issue types endpoint returns 404, sub-issues API
  is unavailable), skip that step and continue with the rest.
- Do not post a comment explaining failures unless every step failed.
