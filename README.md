# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Claude Code Action

Composite action for Claude Code GitHub integration across `ExaDev/*` repos with bundled org-wide prompts.

## Quick Start

### 1. Add Trigger Workflows

Run these commands in your repo:

```bash
# Interactive @claude commands (issues, comments, reviews)
curl -L -o .github/workflows/claude-interactive.yml \
  https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-interactive.yml

# Automatic PR reviews
curl -L -o .github/workflows/claude-review.yml \
  https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-review.yml
```

### 2. Configure Secret

Add `CLAUDE_CODE_OAUTH_TOKEN` to your repo (Settings → Secrets and variables → Actions).

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

1. Consumer repo uses `uses: ExaDev/claude-code-action@main`
2. Action composes prompts: org-wide (bundled) + repo-specific (if present)
3. Calls `anthropics/claude-code-action@v1` with composed prompt
4. No cross-repo access, no GitHub App, no runtime file fetching

### Action Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `mode` | `interactive` or `review` | `interactive` |
| `pr_number` | PR number (required for review mode) | `''` |
| `prompt_dir` | Override prompt directory | `interactive` / `review` |
| `claude_args` | Override claude args | Auto-generated based on mode |
| `claude_code_oauth_token` | Claude Code OAuth token | Required |
| `github_token` | GitHub token | Uses `github.token` |

### Modes

**`interactive`** (default):
- Prompt dir: `interactive`
- Tools: GitHub API, `gh` commands, issue management

**`review`**:
- Prompt dir: `review`
- Tools: GitHub API, `gh` commands, `Read`, `Grep`, `Glob`, `git` commands
- `PR_NUMBER` available for cleanup of stale reviews

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

## Prompt Layering

Prompts are concatenated in order (later extends earlier):

1. Org-wide shared prompts (bundled in action)
2. Org-wide mode-specific prompts (bundled in action)
3. Repo-specific shared prompts (`.github/prompts/shared/*.md`)
4. Repo-specific mode-specific prompts (`.github/prompts/{interactive|review}/*.md`)

Prompt files should be numbered: org-wide `01-09`, repo-specific `10+`.

Available environment variables in prompts:
- `$REPO` — Full repo name (e.g., `ExaDev/my-project`)
- `$REPO_OWNER` — Org name (e.g., `ExaDev`)
- `$REPO_NAME` — Repo name (e.g., `my-project`)
- `$PR_NUMBER` — Pull request number (review mode only)

## Secrets Required

| Secret | Scope | Description |
|--------|-------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Org or repo-level | Claude Code OAuth token |

## Self-Improvement Capability

The review workflow for this repository includes self-improvement capability. When reviewing changes to `ExaDev/claude-code-action`, the agent can:

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
2. Push to ExaDev/claude-code-action
3. In your test repo, reference the branch:
   ```yaml
   uses: ExaDev/claude-code-action@your-branch-name
   ```
4. Trigger the workflow and verify behavior

### Prompt File Conventions

- Number files: `01-09` for org-wide, `10+` for repo-specific
- Files are concatenated in alphabetical order within each directory
- Use `envsubst` variables (`$REPO`, `$REPO_OWNER`, `$REPO_NAME`, `$PR_NUMBER`) for dynamic content
- Keep prompts focused and composable - each file should address one concern
