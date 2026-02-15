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

Composite action that bundles org-wide prompts and layers repo-specific prompts on top.

### How It Works

1. Consumer repo uses `uses: YOUR_ORG/claude-code-action@main`
2. Action composes prompts: org-wide (bundled) + repo-specific (if present)
3. Calls `anthropics/claude-code-action@v1` with composed prompt
4. No cross-repo access, no GitHub App, no runtime file fetching

### Action Inputs

| Input                       | Description                                      | Default                      |
| --------------------------- | ------------------------------------------------ | ---------------------------- |
| `mode`                      | `interactive` or `review`                        | `interactive`                |
| `pr_number`                 | PR number (required for review mode)             | `''`                         |
| `prompt_dir`                | Override prompt directory                        | `interactive` / `review`     |
| `claude_args`               | Override claude args                             | Auto-generated based on mode |
| `claude_code_oauth_token`   | Claude Code OAuth token                          | Required*                    |
| `anthropic_api_key`         | Anthropic API key (alternative to OAuth)         | -                            |
| `github_token`              | GitHub token                                     | Uses `github.token`          |

#### Progress & Comments

| Input                | Description                                    | Default  |
| -------------------- | ---------------------------------------------- | -------- |
| `track_progress`     | Enable progress tracking with checkboxes       | `false`  |
| `include_fix_links`  | Include 'Fix this' links in PR feedback        | `true`   |
| `use_sticky_comment` | Use single sticky comment for PR feedback      | `false`  |

#### Triggers

| Input             | Description                                    | Default   |
| ----------------- | ---------------------------------------------- | --------- |
| `trigger_phrase`  | Custom trigger phrase                          | `@claude` |
| `assignee_trigger`| Assignee that triggers on issue assignment     | -         |
| `label_trigger`   | Label that triggers when applied to issue      | -         |

#### Branch & Permissions

| Input                  | Description                                    | Default    |
| ---------------------- | ---------------------------------------------- | ---------- |
| `branch_prefix`        | Prefix for Claude branches                     | `claude/`  |
| `additional_permissions`| Extra permissions (e.g., `actions: read`)     | -          |
| `allowed_bots`         | Comma-separated allowed bot usernames          | -          |

#### Commit Signing

| Input               | Description                                    | Default     |
| ------------------- | ---------------------------------------------- | ----------- |
| `use_commit_signing`| Enable commit signing via GitHub API           | `false`     |
| `ssh_signing_key`   | SSH private key for signing commits            | -           |
| `bot_id`            | GitHub user ID for git operations              | `41898282`  |
| `bot_name`          | GitHub username for git operations             | `claude[bot]` |

#### Settings & Plugins

| Input                | Description                                    | Default |
| -------------------- | ---------------------------------------------- | ------- |
| `settings`           | Claude Code settings (JSON or file path)       | -       |
| `plugins`            | Newline-separated plugins to install           | -       |
| `plugin_marketplaces`| Newline-separated marketplace Git URLs         | -       |

#### Cloud Providers

| Input         | Description                                    | Default |
| ------------- | ---------------------------------------------- | ------- |
| `use_bedrock` | Use Amazon Bedrock with OIDC                   | `false` |
| `use_vertex`  | Use Google Vertex AI with OIDC                 | `false` |

*Either `claude_code_oauth_token` or `anthropic_api_key` is required.

### Modes

**`interactive`** (default):

- Prompt dir: `interactive`
- Tools: GitHub API (PR read ops), `gh pr comment/view/edit`, `gh label`, `gh issue comment/view`, inline comments
- Max turns: 50

**`review`**:

- Prompt dir: `review`
- Tools: GitHub API (PR read ops), `gh pr comment/view/edit`, `gh label`, `Read`, `Grep`, `Glob`, `git diff/log/blame`, `gh issue/pr create`, inline comments
- Max turns: 50
- `PR_NUMBER` available for cleanup of stale reviews

### Action Outputs

| Output            | Description                           |
| ----------------- | ------------------------------------- |
| `execution_file`  | Path to Claude Code execution output  |
| `structured_output`| JSON output when using `--json-schema`|

## Structure

```
action.yml                        # Composite action definition
.github/
  workflows/
    claude-interactive.yml        # Trigger workflow (curl this)
    claude-review.yml             # PR review trigger (curl this)
  prompts/
    shared/
      01-base.md                  # Generic context prompt
      02-guidelines.md            # PR review flow, suggestion blocks, labels
      03-comment-hygiene.md       # Stale comment cleanup, context awareness
    interactive/
      01-conduct.md               # Behavioral standards for @claude interactions
    review/
      01-command.md               # Auto-review instructions
      02-red-flags.md             # Common patterns to watch for in diffs
      03-self-improvement.md      # Meta-improvement capability (issue creation)
```

## Solutions & Examples

### Automatic PR Review with Progress Tracking

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

For visual progress tracking, add `track_progress: true` in your workflow.

### Security-Focused Reviews

Create `.github/prompts/review/10-security.md` in your repo:

```markdown
Perform a security-focused review focusing on:
- OWASP Top 10 vulnerabilities
- Hardcoded secrets or credentials
- Input validation and sanitization
- Authentication/authorization issues

Rate severity as: CRITICAL, HIGH, MEDIUM, LOW, or NONE.
```

### Path-Specific Reviews

Only review when critical files change by adding `paths` filter:

```yaml
on:
  pull_request:
    types: [opened, synchronize]
    paths:
      - "src/auth/**"
      - "src/api/**"
```

### External Contributor Reviews

```yaml
jobs:
  external-review:
    if: github.event.pull_request.author_association == 'FIRST_TIME_CONTRIBUTOR'
    uses: YOUR_ORG/claude-code-action/.github/workflows/claude-review.yml@main
```

### Structured Outputs

Get validated JSON results for automation:

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

## Prompt Layering

Prompts are concatenated in order (later extends earlier):

1. Org-wide shared prompts (bundled in action)
2. Org-wide mode-specific prompts (bundled in action)
3. Repo-specific shared prompts (`.github/prompts/shared/*.md`)
4. Repo-specific mode-specific prompts (`.github/prompts/{interactive|review}/*.md`)

Prompt files should be numbered: org-wide `01-09`, repo-specific `10+`.

Available environment variables in prompts:

- `$REPO` — Full repo name (e.g., `YOUR_ORG/my-project`)
- `$REPO_OWNER` — Org name (e.g., `YOUR_ORG`)
- `$REPO_NAME` — Repo name (e.g., `my-project`)
- `$PR_NUMBER` — Pull request number (review mode only)
- `$BOT_NAME` — Bot username for git operations (e.g., `claude[bot]`)

## Secrets Required

| Secret                    | Scope             | Description             |
| ------------------------- | ----------------- | ----------------------- |
| `CLAUDE_CODE_OAUTH_TOKEN` | Org or repo-level | Claude Code OAuth token |

## Self-Improvement Capability

The review workflow for this repository includes self-improvement capability. When reviewing changes to this repo, the agent can:

- Create issues to propose prompt improvements
- Identify gaps, inconsistencies, or enhancement opportunities
- Suggest improvements beyond the scope of the current PR

This creates a feedback loop where the agent can iterate on its own configuration without direct file modification (it creates issues, not PRs directly). Human review is still required before any changes are merged.

## Development Notes

### Symlink Architecture

`CLAUDE.md` and `AGENTS.md` are symlinks to `README.md`. The same content serves:

- Humans browsing the repo on GitHub
- Claude Code sessions (via CLAUDE.md)
- Other AI agents (via AGENTS.md)

When modifying this repo, edit `README.md` directly.

### Testing Changes

To test action changes without merging to main:

1. Create a branch with your changes
2. Push to the action repo
3. In your test repo, reference the branch:
   ```yaml
   uses: YOUR_ORG/claude-code-action@your-branch-name
   ```
4. Trigger the workflow and verify behavior

### Prompt File Conventions

- Number files: `01-09` for org-wide, `10+` for repo-specific
- Files are concatenated in alphabetical order within each directory
- Use `envsubst` variables (`$REPO`, `$REPO_OWNER`, `$REPO_NAME`, `$PR_NUMBER`) for dynamic content
- Keep prompts focused and composable - each file should address one concern
