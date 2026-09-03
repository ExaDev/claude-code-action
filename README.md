# Claude Code Action

> **Note**: `CLAUDE.md` and `AGENTS.md` are symlinks to this file. Edits here propagate to all three.

Composite action for Claude Code GitHub integration with bundled org-wide prompts.

## Quick Start

### 1. Add Trigger Workflows

Pick the block for your org and run it in your repo:

<details>
<summary><strong>ExaDev</strong></summary>

```bash
mkdir -p .github/workflows

curl -sL "https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-interactive.yml" \
  | sed "s|uses: \./|uses: ExaDev/claude-code-action@main|" \
  > .github/workflows/claude-interactive.yml

curl -sL "https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-review.yml" \
  | sed "s|uses: \./|uses: ExaDev/claude-code-action@main|" \
  > .github/workflows/claude-review.yml

curl -sL "https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-triage.yml" \
  | sed "s|uses: \./|uses: ExaDev/claude-code-action@main|" \
  > .github/workflows/claude-triage.yml
```

</details>

<details>
<summary><strong>adpeak</strong></summary>

```bash
mkdir -p .github/workflows

curl -sL "https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-interactive.yml" \
  | sed "s|uses: \./|uses: adpeak/claude-code-action@main|" \
  > .github/workflows/claude-interactive.yml

curl -sL "https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-review.yml" \
  | sed "s|uses: \./|uses: adpeak/claude-code-action@main|" \
  > .github/workflows/claude-review.yml

curl -sL "https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-triage.yml" \
  | sed "s|uses: \./|uses: adpeak/claude-code-action@main|" \
  > .github/workflows/claude-triage.yml
```

</details>

### 2. Configure Secret

Generate a Claude Code OAuth token:

```bash
claude setup-token
```

Add the resulting `CLAUDE_CODE_OAUTH_TOKEN` to your repo (Settings → Secrets and variables → Actions).

That's it. No GitHub App needed.

### 3. (Optional) Add Repo-Specific Prompts

Create `.github/prompts/shared/` or `.github/prompts/<dir>/` in your repo. Prompts are layered:

1. Org-wide prompts (bundled in this action)
2. Your repo's prompts (numbered `10-`, `11-`, etc.)

Example `.github/prompts/shared/10-context.md`:

```markdown
This is the Foo service repository. It handles authentication and user management.
Key files: src/auth/, src/users/
```

## Architecture

Composite action that wraps `anthropics/claude-code-action@v1` with org-wide prompts bundled in. No cross-repo access, no GitHub App, no runtime file fetching.

### Modes

**`interactive`** (default) — responds to `@claude` mentions in issues, PR comments, and reviews:

- Tools: GitHub API (PR read ops), `gh pr comment/view/edit`, `gh label`, `gh issue comment/view`

**`review`** — automatic PR review on open/synchronize:

- Tools: all interactive tools + `Read`, `Grep`, `Glob`, `git diff/log/blame`, `gh issue/pr create`
- `PR_NUMBER` env var available for stale review cleanup

**`triage`** — automatic issue triage on creation or re-label:

- Tools: `gh api`, `gh issue edit/view/list/comment`, `gh label list`
- `ISSUE_NUMBER` env var available for API calls
- `UPDATE_ISSUE_BODY` controls whether triage summary is appended to the issue

All modes: max 50 turns.

### Prompt Composition

`action.yml` step 1 concatenates prompts in this order:

1. Org-wide shared (`prompts/shared/*.md`) — base behavior, PR guidelines, comment hygiene
2. Org-wide mode-specific (`prompts/{review|interactive|triage}/*.md`)
3. Consumer repo shared (`.github/prompts/shared/*.md`, if present)
4. Consumer repo mode-specific (`.github/prompts/{review|interactive|triage}/*.md`, if present)

Files are concatenated alphabetically. Org-wide files use numbers `01-09`, repo-specific use `10+`.

Variables substituted via `envsubst` at runtime:

| Variable             | Example                   |
| -------------------- | ------------------------- |
| `$REPO`              | `YOUR_ORG/my-project`     |
| `$REPO_OWNER`        | `YOUR_ORG`                |
| `$REPO_NAME`         | `my-project`              |
| `$PR_NUMBER`         | `42` (review mode only)   |
| `$ISSUE_NUMBER`      | `7` (triage mode only)    |
| `$UPDATE_ISSUE_BODY` | `true` (triage mode only) |
| `$BOT_NAME`          | `claude[bot]`             |

### Credential Fallback

`claude_code_oauth_token` and `anthropic_api_key` each accept either a single value or several newline-separated values. Every value found across both inputs is flattened into one ordered chain — every OAuth token first (in the order given), then every API key — and tried in order: if an attempt fails, the next credential in the chain is tried; the moment one succeeds, no further credentials are attempted. This is for falling through to a backup account/subscription when one is rate-limited, over quota, or otherwise failing — not for load-balancing or round-robining across runs.

```yaml
claude_code_oauth_token: |
  ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN_PRIMARY }}
  ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN_BACKUP }}
```

A single plain value (the existing usage) keeps working unchanged. Up to 5 credentials total are supported (across both inputs combined) — the underlying mechanism is 5 statically unrolled attempt steps, since a composite action has no native loop construct; supplying more than 5 fails the run immediately with a clear error rather than silently trying only the first 5. If neither input is set at all (e.g. `use_bedrock`/`use_vertex`/`use_foundry`, or credentials supplied via an org/repo-level environment variable instead), behaviour is unchanged: a single attempt runs with no explicit credential passed through.

Fallback is aimed at failures that happen before Claude does anything on GitHub — an invalid/expired/rate-limited credential fails at auth time, before any branch, comment, or review is created. If a run instead fails _after_ already taking a GitHub-side action (e.g. mid-conversation, after already pushing a branch or posting a sticky comment), the next credential's attempt starts that action fresh rather than resuming it, which can leave duplicate or partial side effects (an extra branch, an extra comment) behind — worth knowing if you see that happen, since it isn't something this action tries to reconcile.

### Action Inputs

<details>
<summary>Full input reference</summary>

| Input                            | Description                                                                                                                              | Default                      |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| `mode`                           | `interactive`, `review`, or `triage`                                                                                                     | `interactive`                |
| `pr_number`                      | PR number (required for review mode)                                                                                                     | `''`                         |
| `issue_number`                   | Issue number (required for triage mode)                                                                                                  | `''`                         |
| `triage_label`                   | Label that triggers re-triage when applied                                                                                               | `needs-triage`               |
| `update_issue_body`              | Append triage summary to issue description                                                                                               | `true`                       |
| `prompt_dir`                     | Override prompt directory                                                                                                                | `interactive` / `review`     |
| `claude_args`                    | Override claude args                                                                                                                     | Auto-generated based on mode |
| `claude_code_oauth_token`        | Claude Code OAuth token. One value, or newline-separated for fallback — see [Credential Fallback](#credential-fallback)                  | Required\*                   |
| `anthropic_api_key`              | Anthropic API key (alternative to OAuth). One value, or newline-separated for fallback — see [Credential Fallback](#credential-fallback) | -                            |
| `github_token`                   | GitHub token                                                                                                                             | Uses `github.token`          |
| `track_progress`                 | Enable progress tracking with checkboxes                                                                                                 | `false`                      |
| `include_fix_links`              | Include 'Fix this' links in PR feedback                                                                                                  | `true`                       |
| `use_sticky_comment`             | Use single sticky comment for PR feedback                                                                                                | `false`                      |
| `trigger_phrase`                 | Custom trigger phrase                                                                                                                    | `@claude`                    |
| `assignee_trigger`               | Assignee that triggers on issue assignment                                                                                               | -                            |
| `label_trigger`                  | Label that triggers when applied to issue                                                                                                | `claude`                     |
| `base_branch`                    | Branch to use as base when creating new branches                                                                                         | Repository default           |
| `branch_prefix`                  | Prefix for Claude branches                                                                                                               | `claude/`                    |
| `branch_name_template`           | Template for branch naming (supports {{prefix}}, {{entityType}}, {{entityNumber}}, {{timestamp}}, {{sha}}, {{label}}, {{description}})   | Default format               |
| `additional_permissions`         | Extra permissions (e.g., `actions: read`)                                                                                                | -                            |
| `allowed_bots`                   | Comma-separated allowed bot usernames, or '\*' to allow all                                                                              | No bots allowed              |
| `allowed_non_write_users`        | Comma-separated usernames to allow without write permissions. WARNING: Use with extreme caution                                          | -                            |
| `include_comments_by_actor`      | Comma-separated list to INCLUDE in comments. Supports wildcards like '\*\[bot\]'                                                         | All actors included          |
| `exclude_comments_by_actor`      | Comma-separated list to EXCLUDE from comments. Supports wildcards like '\*\[bot\]'. Exclusion takes priority                             | None excluded                |
| `use_commit_signing`             | Enable commit signing via GitHub API                                                                                                     | `false`                      |
| `ssh_signing_key`                | SSH private key for signing commits                                                                                                      | -                            |
| `bot_id`                         | GitHub user ID for git operations                                                                                                        | `41898282`                   |
| `bot_name`                       | GitHub username for git operations                                                                                                       | `claude[bot]`                |
| `settings`                       | Claude Code settings (JSON or file path)                                                                                                 | -                            |
| `plugins`                        | Newline-separated plugins to install                                                                                                     | -                            |
| `plugin_marketplaces`            | Newline-separated marketplace Git URLs                                                                                                   | -                            |
| `use_bedrock`                    | Use Amazon Bedrock with OIDC                                                                                                             | `false`                      |
| `use_vertex`                     | Use Google Vertex AI with OIDC                                                                                                           | `false`                      |
| `use_foundry`                    | Use Microsoft Foundry with OIDC                                                                                                          | `false`                      |
| `path_to_claude_code_executable` | Optional path to custom Claude Code executable. WARNING: May cause issues if outdated                                                    | -                            |
| `path_to_bun_executable`         | Optional path to custom Bun executable. WARNING: May cause issues if incompatible                                                        | -                            |
| `display_report`                 | Whether to display the Claude Code Report in GitHub Step Summary. Set to 'false' to disable when using custom formatting solutions.      | `true`                       |
| `show_full_output`               | Show full JSON output. WARNING: May expose secrets in public logs                                                                        | `false`                      |

\*Either `claude_code_oauth_token` or `anthropic_api_key` is required (unless using `use_bedrock`/`use_vertex`/`use_foundry`, or an org/repo-level environment variable).

</details>

### Action Outputs

| Output              | Description                                                                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `execution_file`    | Path to Claude Code execution output                                                                                             |
| `branch_name`       | The branch created by Claude Code for this execution                                                                             |
| `github_token`      | The GitHub token used by the action (Claude App token if available). **Sensitive** — do not log or upload as an artifact.        |
| `structured_output` | JSON string containing all structured output fields when `--json-schema` is provided in `claude_args`. Use `fromJSON()` to parse |
| `session_id`        | Claude Code session ID that can be used with --resume                                                                            |

## Examples

### Automatic PR Review

```yaml
name: Claude Code Review
on:
  pull_request:
    types: [opened, synchronize]

jobs:
  review:
    uses: YOUR_ORG/claude-code-action/.github/workflows/claude-review.yml@main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Automatic Issue Triage

```yaml
name: Claude Issue Triage
on:
  issues:
    types: [opened, labeled]

jobs:
  triage:
    uses: YOUR_ORG/claude-code-action/.github/workflows/claude-triage.yml@main
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### Custom Triage Taxonomy

Add `.github/prompts/triage/10-taxonomy.md` in your repo:

```markdown
When triaging issues in this repository:

- Use `priority:critical` for security issues and data loss
- Use `priority:high` for broken features affecting users
- Use `priority:medium` for bugs with workarounds
- Use `priority:low` for cosmetic issues and minor improvements
- Always set type to "Bug" for issues describing broken behaviour
- Always set type to "Task" for issues requesting new features
```

### Security-Focused Reviews

Add `.github/prompts/review/10-security.md` in your repo:

```markdown
Perform a security-focused review focusing on:

- OWASP Top 10 vulnerabilities
- Hardcoded secrets or credentials
- Input validation and sanitization
- Authentication/authorization issues

Rate severity as: CRITICAL, HIGH, MEDIUM, LOW, or NONE.
```

### Path-Filtered Reviews

```yaml
on:
  pull_request:
    types: [opened, synchronize]
    paths:
      - "src/auth/**"
      - "src/api/**"
```

### Structured Outputs

```yaml
- uses: YOUR_ORG/claude-code-action@main
  with:
    mode: review
    claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
    claude_args: |
      --json-schema '{"type":"object","properties":{"approved":{"type":"boolean"},"summary":{"type":"string"}}}'

- name: Check result
  if: fromJSON(steps.claude.outputs.structured_output).approved == true
  run: echo "PR approved!"
```

## Self-Improvement

The review workflow includes a self-improvement capability. When reviewing changes to this repo, the agent can create issues to propose prompt improvements. It creates issues (not PRs), so human review is required before changes are merged.

## Development

### Org-Agnostic Design

This repo is pushed to both `ExaDev/claude-code-action` and `adpeak/claude-code-action` with identical commits. To maintain this:

- Workflow files use `uses: ./` (self-reference). Consumer repos substitute the correct org via `sed` when curling.
- Prompt files use `$REPO_OWNER` instead of hardcoding an org name.
- README examples use `YOUR_ORG` as a placeholder.

Push to both remotes:

```bash
git push origin main && git push adpeak main
```

### File Layout

`CLAUDE.md` and `AGENTS.md` are symlinks to `README.md`. Always edit `README.md` directly.

The critical parts of `action.yml` are:

- **Step 1** — Prompt composition shell script (concatenation + `envsubst`)
- **Step 2** — Tool access control (determines what each mode can do)
- **Step 3** — Upstream action call to `anthropics/claude-code-action@v1`

Changes to `action.yml` affect all consumer repos.

### Testing Changes

1. Create a branch and push
2. In a test repo, reference the branch: `uses: YOUR_ORG/claude-code-action@your-branch`
3. Trigger the workflow and verify

### Prompt Conventions

- Number files `01-09` for org-wide, `10+` for repo-specific
- Alphabetical concatenation within each directory
- Use `envsubst` variables for dynamic content — never hardcode org names
- One concern per file
