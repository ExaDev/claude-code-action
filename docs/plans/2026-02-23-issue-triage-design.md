# Issue Triage Mode Design

## Summary

Add a `triage` mode to the existing composite action that automatically triages newly created (or re-labelled) GitHub issues. Claude reads the issue, discovers available metadata via the GitHub API, and applies the appropriate issue type, labels, blocking/blocker relationships, and parent issue.

## Trigger

- `issues: [opened]` — triage every new issue automatically.
- `issues: [labeled]` — re-triage when a configurable label is applied (default: `needs-triage`).
- Skip bot-created issues unless `allowed_bots` is set.

## Architecture

Implemented as a third mode (`triage`) in the existing `action.yml`, following the same pattern as `interactive` and `review`:

1. **Prompt composition** (Step 1): Assembles `prompts/triage/*.md` with `envsubst` variable substitution.
2. **Tool restriction** (Step 1): Generates a triage-specific `allowedTools` list.
3. **Upstream call** (Step 2): Passes composed prompt + tools to `anthropics/claude-code-action@v1`.

## Tool Access

Triage mode is restricted to GitHub API operations:

- `gh api` — sub-issues API, issue types API, and other REST calls
- `gh issue edit` — set labels, type, assignees
- `gh issue view` — read the triggering issue
- `gh issue list` — find candidate parent/blocker issues
- `gh issue comment` — optionally comment on the issue
- `gh label list` — discover available labels
- `mcp__github__get_issue`, `mcp__github__list_issues` — MCP equivalents

**Not allowed:** `Read`, `Grep`, `Glob`, `Write`, `Edit`, `WebFetch`, `git *`, `gh pr *`.

## Prompts

### Org-wide (`prompts/triage/`)

| File               | Purpose                                                                                         |
| ------------------ | ----------------------------------------------------------------------------------------------- |
| `01-task.md`       | Core triage instruction: read issue, discover metadata, apply type/labels/relationships         |
| `02-discovery.md`  | API discovery: how to call issue types, labels, sub-issues, and issue list endpoints            |
| `03-guidelines.md` | Quality: only set type if confident, only use existing labels, only link clearly related issues |

### Consumer override

Consumer repos can add `.github/prompts/triage/10-taxonomy.md` (or similar) to constrain or guide triage decisions.

### Variables

Existing: `$REPO`, `$REPO_OWNER`, `$REPO_NAME`, `$BOT_NAME`.
New: `$ISSUE_NUMBER` — substituted from the workflow event context.

## New Action Inputs

| Input               | Description                                      | Default        |
| ------------------- | ------------------------------------------------ | -------------- |
| `issue_number`      | Issue number (required for triage mode)          | `''`           |
| `triage_label`      | Label that triggers re-triage on `labeled` event | `needs-triage` |
| `update_issue_body` | Append triage summary to issue description       | `true`         |

## Workflow Template

New file: `.github/workflows/claude-triage.yml`

```yaml
name: Claude Issue Triage
on:
  issues:
    types: [opened, labeled]

jobs:
  triage:
    if: >-
      (github.event.action == 'opened') ||
      (github.event.action == 'labeled' && github.event.label.name == 'needs-triage')
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
      id-token: write
    steps:
      - uses: ./
        with:
          mode: triage
          issue_number: ${{ github.event.issue.number }}
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Consumer repos substitute `uses: ./` with `uses: ExaDev/claude-code-action@main` (or `adpeak/`).

## API Endpoints Used

### Issue Types (org-level)

- `GET /orgs/{org}/issue-types` — list available types

### Issues

- `PATCH /repos/{owner}/{repo}/issues/{issue_number}` — update type, labels
- `GET /repos/{owner}/{repo}/issues` — list open issues for parent/blocker candidates

### Sub-Issues

- `POST /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` — add sub-issue to parent
- `GET /repos/{owner}/{repo}/issues/{issue_number}/sub_issues` — list sub-issues
- `GET /repos/{owner}/{repo}/issues/{issue_number}/parent` — get parent issue

## Files Changed

| File                                      | Change                                                                                                   |
| ----------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `action.yml`                              | Add `issue_number`, `triage_label`, `update_issue_body` inputs; add triage branch to mode case in Step 1 |
| `.github/workflows/claude-triage.yml`     | New workflow template                                                                                    |
| `.github/prompts/triage/01-task.md`       | New: core triage prompt                                                                                  |
| `.github/prompts/triage/02-discovery.md`  | New: API discovery instructions                                                                          |
| `.github/prompts/triage/03-guidelines.md` | New: triage quality guidelines                                                                           |
| `README.md`                               | Document triage mode, new inputs, workflow template, examples                                            |
