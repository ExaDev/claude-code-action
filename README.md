# Claude Code Shared Workflows

Central repository for Claude Code GitHub Actions integration across `adpeak/*` repos.

## Quick Start

### 1. Add Trigger Workflows

Run these commands in your repo:

```bash
# Interactive @claude commands (issues, comments, reviews)
curl -L -o .github/workflows/claude-interactive.yml \
  https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-interactive.yml

# Automatic PR reviews
curl -L -o .github/workflows/claude-review.yml \
  https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-review.yml
```

### 2. Configure Secrets

Add `CLAUDE_CODE_OAUTH_TOKEN` to your repo (Settings → Secrets and variables → Actions).

### 3. (Optional) Add Repo-Specific Prompts

Create `.github/prompts/shared/` or `.github/prompts/<dir>/` in your repo. Files are layered:

1. Org-wide prompts from this repo (numbered `01-`, `02-`, etc.)
2. Your repo's prompts (numbered `10-`, `11-`, etc.)

Example `.github/prompts/shared/10-context.md`:
```markdown
This is the Foo service repository. It handles authentication and user management.
Key files: src/auth/, src/users/
```

## Configuration

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `mode` | `interactive` or `review` | `interactive` |
| `pr_number` | PR number (required for code-review) | `''` |
| `prompt_dir` | Override prompt directory | `interactive` / `review` |
| `claude_args` | Override claude args | Auto-generated based on mode |

### Modes

**`interactive`** (default):
- Prompt dir: `claude`
- Tools: GitHub API, `gh` commands, issue management
- No `PR_NUMBER` in prompt context

**`review`**:
- Prompt dir: `review`
- Tools: GitHub API, `gh` commands, `Read`, `Grep`, `Glob`, `git` commands
- `PR_NUMBER` available for cleanup of stale reviews

## Structure

```
.github/
  workflows/
    claude-base.yml              # Reusable workflow (workflow_call)
    claude-interactive.yml       # Interactive trigger (curl this)
    claude-review.yml            # PR review trigger (curl this)
  scripts/
    compose-prompt.sh            # Prompt composition script
  prompts/
    shared/
      01-base.md                 # Generic context prompt
      02-guidelines.md           # PR review flow, suggestion blocks, labels
      03-comment-hygiene.md      # Stale comment cleanup, context awareness
    interactive/
      .gitkeep                   # Interactive mode uses shared prompts only
    review/
      01-command.md              # Auto-review instructions
```

## Prompt Layering

The `compose-prompt.sh` script concatenates prompts in order:

1. `.claude-shared/.github/prompts/shared/*.md` (org-wide)
2. `.claude-shared/.github/prompts/interactive/*.md` or `review/*.md` (org-wide mode-specific)
3. `.github/prompts/shared/*.md` (repo-specific)
4. `.github/prompts/interactive/*.md` or `review/*.md` (repo-specific mode-specific)

Available environment variables in prompts:
- `$REPO` — Full repo name (e.g., `adpeak/adpeak-infrastructure`)
- `$REPO_OWNER` — Org name (e.g., `adpeak`)
- `$REPO_NAME` — Repo name (e.g., `adpeak-infrastructure`)
- `$PR_NUMBER` — Pull request number (review mode only)

## Prerequisites

- **Repo visibility**: This repo must be accessible to consuming repos
  - For same-org usage: Set to internal or configure Actions access in org settings
  - For cross-org usage: Make public or use PAT-based checkout

- **Secrets**: Each consuming repo needs `CLAUDE_CODE_OAUTH_TOKEN`
  - Can be configured at org level (recommended) or repo level
