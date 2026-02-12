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

## Architecture

Two-checkout pattern: the reusable workflow checks out both the caller's repo and this shared prompts repo, then composes prompts by layering org-wide and repo-specific files.

### Workflow Types

- **claude-base.yml**: Reusable workflow (`workflow_call`) - never triggers directly, always called by trigger workflows
- **claude-interactive.yml**: Trigger workflow for @claude mentions in issues/comments/reviews
- **claude-review.yml**: Trigger workflow for automatic PR reviews

## Configuration

### Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `mode` | `interactive` or `review` | `interactive` |
| `pr_number` | PR number (required for review mode) | `''` |
| `prompt_dir` | Override prompt directory | `interactive` / `review` |
| `claude_args` | Override claude args | Auto-generated based on mode |

### Modes

**`interactive`** (default):
- Prompt dir: `interactive`
- Tools: GitHub API, `gh` commands, issue management
- No `PR_NUMBER` in prompt context

**`review`**:
- Prompt dir: `review`
- Tools: GitHub API, `gh` commands, `Read`, `Grep`, `Glob`, `git` commands
- `PR_NUMBER` available for cleanup of stale reviews

Mode determines prompt directory and allowed tools automatically. Use `claude_args` to override defaults.

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

`compose-prompt.sh` concatenates prompts in order (later extends earlier):

1. `.claude-shared/.github/prompts/shared/*.md` (org-wide shared)
2. `.claude-shared/.github/prompts/{interactive|review}/*.md` (org-wide mode-specific)
3. `.github/prompts/shared/*.md` (repo-specific shared)
4. `.github/prompts/{interactive|review}/*.md` (repo-specific mode-specific)

Prompt files should be numbered: org-wide `01-09`, repo-specific `10+`.

Available environment variables in prompts:
- `$REPO` — Full repo name (e.g., `adpeak/adpeak-infrastructure`)
- `$REPO_OWNER` — Org name (e.g., `adpeak`)
- `$REPO_NAME` — Repo name (e.g., `adpeak-infrastructure`)
- `$PR_NUMBER` — Pull request number (review mode only)

## Prerequisites

### GitHub App (Required for Cross-Repo Access)

The workflow uses a GitHub App to fetch shared prompts from this repository. Set up once at the org level:

1. **Create a GitHub App** (Settings → Developer settings → GitHub Apps → New GitHub App):
   - Name: `adpeak-ops-bot` (or your preferred name)
   - Homepage URL: Any valid URL
   - Webhook: Uncheck "Active"
   - Repository permissions:
     - **Contents**: Read-only
     - **Pull requests**: Read and write
     - **Issues**: Read and write
   - Where can this GitHub App be installed?: Any account

2. **Generate a Private Key** after creating the app (scroll down to "Private keys" section)

3. **Install the App** on your organization:
   - Go to your app settings → "Install App"
   - Install on the organization
   - Grant access to all repositories (or at minimum: this repo + any consuming repos)

4. **Configure Org-Level Secrets**:
   - Go to Organization → Settings → Secrets and variables → Actions
   - Add `APP_ID`: The numeric App ID (found on your app's settings page)
   - Add `APP_PRIVATE_KEY`: The entire contents of the private key .pem file

### Secrets Required

| Secret | Scope | Description |
|--------|-------|-------------|
| `APP_ID` | Org-level | GitHub App ID for cross-repo access |
| `APP_PRIVATE_KEY` | Org-level | GitHub App private key (.pem content) |
| `CLAUDE_CODE_OAUTH_TOKEN` | Org or repo-level | Claude Code OAuth token |

### Repo Visibility

This repo can remain **private** - the GitHub App token provides the necessary access. No additional Actions access settings are required.
