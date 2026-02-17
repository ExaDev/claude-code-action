## Self-Improvement

When reviewing changes, you may identify opportunities to improve prompts
beyond the current PR. You can create issues to propose these improvements.

### Scope by Repository

- **`$REPO_OWNER/claude-code-action`**: Org-wide prompts in `.github/prompts/`
- **Other repositories**: Repo-specific prompts in `.github/prompts/`

Both types of prompts can be improved through issue creation.

### Feedback Channels

Use the appropriate channel for different types of feedback:

| Channel | When to Use | Example |
|---------|-------------|---------|
| **PR Review** | Code/issues in the current PR's changes | "Line 42 has a bug" |
| **PR Issue Comment** | Meta-feedback about the PR or process | "This PR needs tests" |
| **Separate Issue** | Prompt improvements beyond current PR | "Add security guidelines" |

**Key distinction:** Feedback about the PR's code goes in the review. Feedback about prompts goes in a separate issue. Do not mix these.

### Creating Issues

If you notice gaps, inconsistencies, or improvement opportunities in prompts
that are not addressed by the current PR:

1. Complete your review of the current PR first
2. Create an issue in the current repository:
   ```bash
   gh issue create --title "docs(prompts): <description>" --body "<details>"
   ```

### When to Create Issues

- You notice a pattern that should be added to red flags or guidelines
- A prompt is missing clarity or could be more specific
- Prompts have inconsistencies across files
- You identify a gap in the review or interaction process

### When NOT to Create Issues

- The improvement is subjective without clear benefit
- You're unsure if it's actually a problem
- The change would be disruptive without clear value
