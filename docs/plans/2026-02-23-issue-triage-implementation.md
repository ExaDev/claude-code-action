# Issue Triage Mode Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `triage` mode to the composite action that auto-triages new GitHub issues with type, labels, blockers, and parent.

**Architecture:** New mode in existing `action.yml` following the `interactive`/`review` pattern — triage-specific prompts in `prompts/triage/`, triage-specific `allowedTools`, and a new workflow template.

**Tech Stack:** GitHub Actions composite action (YAML + shell), GitHub REST API (`gh` CLI), `envsubst` for prompt variable substitution.

---

## Tasks

### Task 1: Add triage prompt — `01-task.md`

**Files:**

- Create: `.github/prompts/triage/01-task.md`

**Step 1: Create the prompt file**

```markdown
Triage issue #${ISSUE_NUMBER} in ${REPO}.

Read the issue title and body, then apply the appropriate metadata:

1. **Issue type** — set the type that best matches the issue content
2. **Labels** — add labels that categorise the issue (area, priority, kind)
3. **Parent issue** — if this issue is clearly a sub-task of an existing open
   issue, add it as a sub-issue
4. **Blockers** — if this issue explicitly references being blocked by another
   issue, note the relationship

Do not create branches, write code, or modify files. Your only job is to
classify and organise this issue.
```

**Step 2: Run lint**

Run: `npm run lint`
Expected: PASS (markdown files are linted by eslint)

**Step 3: Commit**

```bash
git add .github/prompts/triage/01-task.md
git commit -m "feat(triage): add core triage task prompt"
```

---

### Task 2: Add triage prompt — `02-discovery.md`

**Files:**

- Create: `.github/prompts/triage/02-discovery.md`

**Step 1: Create the prompt file**

````markdown
## Discovering available metadata

Before applying any metadata, discover what is available in the repository.

### Issue types

List the organisation's issue types:

```sh
gh api /orgs/${REPO_OWNER}/issue-types --jq '.[].name'
```

If the endpoint returns 404 (org has no issue types configured), skip type
assignment entirely.

### Labels

List the repository's labels:

```sh
gh label list --repo ${REPO} --limit 100 --json name,description --jq '.[] | "\(.name): \(.description)"'
```

### Open issues (for parent/blocker candidates)

Search for potentially related open issues:

```sh
gh issue list --repo ${REPO} --state open --limit 50 --json number,title,labels --jq '.[] | "#\(.number) \(.title)"'
```

### Applying metadata

**Set issue type** (use the exact type name from the discovery step):

```sh
gh api -X PATCH /repos/${REPO}/issues/${ISSUE_NUMBER} -f type='<type name>'
```

**Add labels** (only labels that already exist in the repo):

```sh
gh issue edit ${ISSUE_NUMBER} --repo ${REPO} --add-label "label1,label2"
```

**Set parent issue** (make this issue a sub-issue of a parent):

```sh
# First get the issue ID (not number) of the new issue
ISSUE_ID=$(gh api /repos/${REPO}/issues/${ISSUE_NUMBER} --jq '.id')
# Then add as sub-issue to the parent
gh api -X POST /repos/${REPO}/issues/<parent_number>/sub_issues -f sub_issue_id="$ISSUE_ID"
```

**Update issue body** (when `update_issue_body` is enabled):

After triaging, read the current issue body and append a triage summary inside
marker comments so it can be updated on re-triage:

```sh
gh issue view ${ISSUE_NUMBER} --repo ${REPO} --json body --jq '.body'
```

Then update with the triage section appended (or replaced if markers exist):

```sh
gh issue edit ${ISSUE_NUMBER} --repo ${REPO} --body "<updated body>"
```

Use markers `<!-- claude-triage:start -->` / `<!-- claude-triage:end -->` to
identify the triage section. Preserve everything outside the markers. If no
marker block exists, append yours at the end.
````

**Step 2: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 3: Commit**

```bash
git add .github/prompts/triage/02-discovery.md
git commit -m "feat(triage): add API discovery prompt"
```

---

### Task 3: Add triage prompt — `03-guidelines.md`

**Files:**

- Create: `.github/prompts/triage/03-guidelines.md`

**Step 1: Create the prompt file**

```markdown
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

**Re-triage:**

- When re-triaging (triggered by a label), check what metadata is already set.
- Do not remove existing type or labels unless they are clearly wrong.
- Update the triage summary in the issue body if `update_issue_body` is enabled.

**Error handling:**

- If a tool call fails (e.g. issue types endpoint returns 404, sub-issues API
  is unavailable), skip that step and continue with the rest.
- Do not post a comment explaining failures unless every step failed.
```

**Step 2: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 3: Commit**

```bash
git add .github/prompts/triage/03-guidelines.md
git commit -m "feat(triage): add triage quality guidelines prompt"
```

---

### Task 4: Add new inputs to `action.yml`

**Files:**

- Modify: `action.yml:8-16` (inputs section)

**Step 1: Add `issue_number`, `triage_label`, and `update_issue_body` inputs**

After the existing `pr_number` input (line 13-16), add:

```yaml
issue_number:
  description: "Issue number (required for triage mode)"
  required: false
  default: ""
triage_label:
  description: "Label that triggers re-triage when applied to an issue"
  required: false
  default: "needs-triage"
update_issue_body:
  description: "Append triage summary to the issue description"
  required: false
  default: "true"
```

**Step 2: Update mode input description**

Change line 10 from:

```yaml
description: "Mode: interactive or review"
```

to:

```yaml
description: "Mode: interactive, review, or triage"
```

**Step 3: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 4: Commit**

```bash
git add action.yml
git commit -m "feat(triage): add issue_number, triage_label, and update_issue_body inputs"
```

---

### Task 5: Add triage mode to prompt composition and tool access

**Files:**

- Modify: `action.yml:176-243` (compose prompts step)

**Step 1: Add `ISSUE_NUMBER` and `UPDATE_ISSUE_BODY` to the env block**

In the `env:` section of the compose step (lines 179-186), add:

```yaml
ISSUE_NUMBER: ${{ inputs.issue_number }}
UPDATE_ISSUE_BODY: ${{ inputs.update_issue_body }}
```

**Step 2: Add `triage` to the mode routing**

In the `run:` script, change the directory determination (lines 188-195) from:

```bash
        if [ -n "$PROMPT_DIR" ]; then
          DIR="$PROMPT_DIR"
        elif [ "$MODE" = "review" ]; then
          DIR="review"
        else
          DIR="interactive"
        fi
```

to:

```bash
        if [ -n "$PROMPT_DIR" ]; then
          DIR="$PROMPT_DIR"
        elif [ "$MODE" = "review" ]; then
          DIR="review"
        elif [ "$MODE" = "triage" ]; then
          DIR="triage"
        else
          DIR="interactive"
        fi
```

**Step 3: Add `ISSUE_NUMBER` and `UPDATE_ISSUE_BODY` to envsubst calls**

Update all four `envsubst` calls (lines 203, 209, 216, 224) to include the new variables. Change:

```bash
envsubst '$REPO $REPO_OWNER $REPO_NAME $PR_NUMBER $BOT_NAME'
```

to:

```bash
envsubst '$REPO $REPO_OWNER $REPO_NAME $PR_NUMBER $ISSUE_NUMBER $UPDATE_ISSUE_BODY $BOT_NAME'
```

**Step 4: Add triage tool set**

In the tool determination section (lines 237-241), change:

```bash
        if [ "$MODE" = "review" ]; then
          TOOLS="$COMMON_TOOLS,Read,Grep,Glob,WebFetch,Bash(git diff:*),Bash(git log:*),Bash(git blame:*),Bash(gh issue create:*),Bash(gh pr create:*)"
        else
          TOOLS="$COMMON_TOOLS,Bash(gh issue comment:*),Bash(gh issue view:*)"
        fi
```

to:

```bash
        if [ "$MODE" = "review" ]; then
          TOOLS="$COMMON_TOOLS,Read,Grep,Glob,WebFetch,Bash(git diff:*),Bash(git log:*),Bash(git blame:*),Bash(gh issue create:*),Bash(gh pr create:*)"
        elif [ "$MODE" = "triage" ]; then
          TOOLS="Bash(gh api:*),Bash(gh issue edit:*),Bash(gh issue view:*),Bash(gh issue list:*),Bash(gh issue comment:*),Bash(gh label list:*),mcp__github__get_issue,mcp__github__list_issues"
        else
          TOOLS="$COMMON_TOOLS,Bash(gh issue comment:*),Bash(gh issue view:*)"
        fi
```

Note: triage mode does **not** include `$COMMON_TOOLS` (PR-related tools) since it operates on issues only.

**Step 5: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 6: Commit**

```bash
git add action.yml
git commit -m "feat(triage): add triage mode to prompt composition and tool access"
```

---

### Task 6: Create workflow template

**Files:**

- Create: `.github/workflows/claude-triage.yml`

**Step 1: Create the workflow file**

```yaml
name: Claude Issue Triage

on:
  issues:
    types: [opened, labeled]

permissions:
  contents: read
  issues: write
  id-token: write

jobs:
  claude-triage:
    # Run on new issues, or when 'needs-triage' label is applied
    if: >
      (github.event.action == 'opened' &&
       github.event.issue.user.type != 'Bot') ||
      (github.event.action == 'labeled' &&
       github.event.label.name == 'needs-triage')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: ./
        with:
          mode: triage
          issue_number: ${{ github.event.issue.number }}
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          # Optional: Change the re-triage label
          # triage_label: "needs-triage"
          # Optional: Disable issue body updates
          # update_issue_body: false
```

**Step 2: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 3: Commit**

```bash
git add .github/workflows/claude-triage.yml
git commit -m "feat(triage): add triage workflow template"
```

---

### Task 7: Update README documentation

**Files:**

- Modify: `README.md`

**Step 1: Update the Modes section**

After the existing `review` mode description (around line 86), add the triage mode:

```markdown
**`triage`** — automatic issue triage on creation or re-label:

- Tools: `gh api`, `gh issue edit/view/list/comment`, `gh label list`
- `ISSUE_NUMBER` env var available for API calls
- `UPDATE_ISSUE_BODY` controls whether triage summary is appended to the issue
```

**Step 2: Update the Variables table**

Add to the variables table (around line 108):

```markdown
| `$ISSUE_NUMBER` | `7` (triage mode only) |
| `$UPDATE_ISSUE_BODY` | `true` (triage mode only) |
```

**Step 3: Update the mode input description in the inputs table**

Change:

```markdown
| `mode` | `interactive` or `review` | `interactive` |
```

to:

```markdown
| `mode` | `interactive`, `review`, or `triage` | `interactive` |
```

**Step 4: Add new inputs to the inputs table**

After the `pr_number` row, add:

```markdown
| `issue_number` | Issue number (required for triage mode) | `''` |
| `triage_label` | Label that triggers re-triage when applied | `needs-triage` |
| `update_issue_body` | Append triage summary to issue description | `true` |
```

**Step 5: Add triage example to Examples section**

After the "Automatic PR Review" example (around line 183), add:

````markdown
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
````

**Step 6: Update Quick Start curl commands**

In both the ExaDev and adpeak `<details>` blocks, add a third curl command for the triage workflow.

ExaDev:

```bash
curl -sL "https://raw.githubusercontent.com/ExaDev/claude-code-action/main/.github/workflows/claude-triage.yml" \
  | sed "s|uses: \./|uses: ExaDev/claude-code-action@main|" \
  > .github/workflows/claude-triage.yml
```

adpeak:

```bash
curl -sL "https://raw.githubusercontent.com/adpeak/claude-code-action/main/.github/workflows/claude-triage.yml" \
  | sed "s|uses: \./|uses: adpeak/claude-code-action@main|" \
  > .github/workflows/claude-triage.yml
```

**Step 7: Update the prompt composition docs**

In the "Prompt Composition" section, update the mode-specific line:

```markdown
2. Org-wide mode-specific (`prompts/{review|interactive|triage}/*.md`)
```

and:

```markdown
4. Consumer repo mode-specific (`.github/prompts/{review|interactive|triage}/*.md`, if present)
```

**Step 8: Run lint**

Run: `npm run lint`
Expected: PASS

**Step 9: Commit**

```bash
git add README.md
git commit -m "docs: add triage mode documentation"
```

---

### Task 8: Final verification

**Step 1: Run full lint**

Run: `npm run lint`
Expected: PASS — all files pass eslint

**Step 2: Verify all new files exist**

```bash
ls -la .github/prompts/triage/
ls -la .github/workflows/claude-triage.yml
```

Expected: Three prompt files (`01-task.md`, `02-discovery.md`, `03-guidelines.md`) and one workflow file.

**Step 3: Verify action.yml has all three modes**

```bash
grep -c 'triage' action.yml
```

Expected: Multiple matches (input descriptions, mode routing, tool set).

**Step 4: Verify README mentions triage**

```bash
grep -c 'triage' README.md
```

Expected: Multiple matches across modes, inputs, examples, and curl commands.
