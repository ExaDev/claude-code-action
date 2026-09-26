# Adopting the action

Full setup steps for a consuming repository, including the background on why this wraps the upstream action and the copy-paste prompt for handing setup to an agent. The README's Adopting section links here for everything beyond the quick start.

## Why this exists rather than per-repository workflows

This wraps Anthropic's own [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) (MIT licensed). Every consuming repository could call that directly, but then each one would carry its own copy of the review instructions, its own tool allowlist, and its own idea of what "review a pull request" means. Those copies drift, and improving the review prompt would mean editing every repository.

Instead, a consuming repository gets a workflow file of roughly ten lines, and this repository holds the prompts, the tool allowlists, the per-mode permission scoping, and the pinned upstream version. Changing how review works everywhere is a change here.

The prompts also encode something worth knowing before you rely on them: plenty of real repositories are inherited, sparsely documented, and inconsistent between directories, with no written-down conventions. The prompts are written for that rather than assuming a greenfield project, and review mode is required to distinguish a finding that rests on the project's own documented policy from one that rests on a general convention for the stack. See [Documented policy versus stack default](review-conventions.md#documented-policy-versus-stack-default).

## Adopting it in a repository

**1. Make a Claude credential available.** Set one of these as an organisation secret (Settings → Secrets and variables → Actions), so every repository inherits it, or as a repository secret for a single repository:

- `ANTHROPIC_API_KEY` — an Anthropic API key.
- `CLAUDE_CODE_OAUTH_TOKEN` — a Claude Code OAuth token, if the organisation bills through a Claude subscription rather than API credit.

Either works. Set one; the run fails with an explicit error if neither is present. The examples below use `ANTHROPIC_API_KEY`, so change the secret name if you use the OAuth token instead. A second (or third, or more) credential of either kind can be added later, to fall through to if the first fails — see [Credential fallback](credentials.md#credential-fallback) — but is not needed to get started.

**2. Copy the workflows you want** from [`examples/`](../examples/) into the repository's own `.github/workflows/`. There are two forms:

| Copy this                                                               | To                                         | Gives you             |
| ----------------------------------------------------------------------- | ------------------------------------------ | --------------------- |
| [`examples/claude-review.yml`](../examples/claude-review.yml)           | `.github/workflows/claude-review.yml`      | Pull request review   |
| [`examples/claude-triage.yml`](../examples/claude-triage.yml)           | `.github/workflows/claude-triage.yml`      | Issue triage          |
| [`examples/claude-interactive.yml`](../examples/claude-interactive.yml) | `.github/workflows/claude-interactive.yml` | `@claude` in comments |

These call this repository's reusable workflows. They are the shorter, recommended form: the per-mode least-privilege `permissions:` are held in the reusable workflow, so an adopting repository does not have to reason about token scopes unless its own default workflow permissions fall short of what a mode needs — see step 3 below for when and how to add a `permissions:` block to the caller.

They are independent. Take one, two, or all three.

The event trigger lives in the caller, not here, because a reusable workflow is invoked by a job and the caller's own `on:` block decides when. That is also where you would narrow things: add a `paths:` filter to skip review on documentation-only changes, or a `branches:` filter to review only pull requests targeting `main`.

**Direct (composite-action-step) alternative.** [`examples/direct/`](../examples/direct/) holds the same three modes as ordinary workflows that call `ExaDev/claude-code-action@v1` directly as a step (with their own `actions/checkout` and `permissions:` block). Use the direct form when you need OIDC-based auth (Bedrock/Vertex/Foundry/Anthropic federation), which needs `id-token: write` reaching the composite action call itself — none of the three reusable workflows this repository ships declare that scope in their own hardcoded `permissions:` block, so no amount of caller-side permission-granting can pass it through (see step 3); or **review running as the Claude Code GitHub App (`claude[bot]`)** rather than `github-actions[bot]`, for the same reason. That App identity is the only one that can resolve the bot's own stale review threads (`resolve_stale_threads`) and submit formal reviews via moderation — the reusable form's `github-actions[bot]` token is forbidden from both. The review direct example handles this for you (it declares `id-token: write`, omits `github_token`, and requires the Claude Code App installed plus a `CLAUDE_CODE_OAUTH_TOKEN`); see its header comment for the scope trade-off. Otherwise prefer the reusable form above — it is shorter, and a caller-side `permissions:` block (step 3) covers everything else a mode might need beyond the repository default.

**`generic` mode has no reusable-workflow form at all** — only [`examples/direct/claude-generic.yml`](../examples/direct/claude-generic.yml). The three reusable workflows above exist to centralise event-trigger gating logic (label/mention/author-association checks for pull-request and issue events); `generic` mode has no event-trigger semantics of its own — it's called imperatively from inside a job you already have (a release pipeline, a scheduled report, any scripted task) — so a passthrough reusable workflow would add nothing. See [`prompt_file`](calling-and-options.md#extended-options) below.

**3. Add a `permissions:` block to the caller job if this repository's own default workflow permissions fall short of what the mode needs.** A job that declares no `permissions:` block of its own gets this repository's (or organisation's) current default workflow permissions setting as its effective `GITHUB_TOKEN` scope. When that job then calls a reusable workflow, GitHub checks the reusable workflow's own requested `permissions:` against that effective scope _before dispatching any job at all_ — a reusable workflow's permissions can only be downgraded from what the caller provides, never elevated — and refuses to start the run when the request exceeds it: a generic, jobless `startup_failure` ("This run likely failed because of a workflow file issue"), with no further diagnostic text anywhere. `actionlint` does not catch this; it only shows up as `startup_failure` when the workflow actually runs, confirmed live and reproduced on a throwaway test PR against this very repository. Confirm your repository's default (Settings → Actions → General → Workflow permissions) covers at least `contents: read` plus whatever write scope the mode you're adopting needs (see the table above); if it doesn't, and tightening the repository-wide default isn't what you want, declare a `permissions:` block on the caller job itself, matching the called reusable workflow's own documented scope exactly (see [What each mode is allowed to do](modes-and-permissions.md#what-each-mode-is-allowed-to-do)) — a job calling a reusable workflow, in this repository or a different one, can perfectly well declare its own `permissions:`; nothing about crossing that boundary forbids it. What a caller-side grant cannot do is reach `id-token: write` through to the composite action call nested inside the reusable workflow: none of `review.yml`/`triage.yml`/`interactive.yml` declare that scope in their own hardcoded `permissions:` block, so there is nothing for a caller-side grant to flow into. Use the [direct form](../examples/direct/) instead for OIDC-based auth or App-identity review.

**4. That is it.** There is nothing else to install and no bot to add. Runs authenticate as the repository's own `GITHUB_TOKEN`, so comments appear from `github-actions[bot]`.

### Or, hand this to an agent

Steps 1–4 above, as a prompt for a coding agent (Claude Code or similar) to run inside the target repository. It fetches this repository's own README and examples from GitHub rather than assuming they're checked out locally, and stops to ask rather than guessing on the two things only a human can decide: whether a credential secret should be provisioned, and whether this repository's default workflow permissions are actually sufficient.

```text
Set up ExaDev/claude-code-action in this repository. It's currently private, so this needs a gh
CLI session with read access to it — if the commands below 404 or fail auth, stop and tell me
rather than guessing at what the README/examples would say. Its README and examples aren't
checked out here, so read them from GitHub first:

    gh api repos/ExaDev/claude-code-action/contents/README.md --jq '.content' | base64 -d
    gh api repos/ExaDev/claude-code-action/contents/examples --jq '.[].name'
    gh api repos/ExaDev/claude-code-action/contents/examples/<name> --jq '.content' | base64 -d

Then:

1. Check whether an ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN secret already exists,
   repository or organisation level (`gh secret list`, `gh api orgs/<this repository's own
   organisation>/actions/secrets`). If neither exists, stop and tell me — provisioning one is
   my call, not yours.
2. Work out which modes this repository actually wants: review (PR review), triage (issue
   triage), interactive (@claude in comments) — any combination, based on what I've asked
   for, not all three by default.
3. For each mode, copy the matching example to .github/workflows/claude-<mode>.yml,
   unmodified except: the secret name if it isn't literally ANTHROPIC_API_KEY, and any
   "Extended options" input from the README genuinely worth setting for this repository —
   don't add inputs speculatively, only ones with an actual reason.
4. Check this repository's actual default workflow permissions (Settings → Actions →
   General → Workflow permissions) and confirm they cover at least the token scopes the
   README's "What each mode is allowed to do" table lists for each mode you're adding —
   don't copy that list from memory, read the table itself, since it's the single source of
   truth this prompt would otherwise drift out of sync with. If the default falls short, add
   a permissions: block to that job matching the table's scopes exactly (see the README's
   step 3) — this is allowed and correct, not something GitHub rejects. Tell me either way:
   which repositories needed a permissions: block added and which didn't, since that's worth
   knowing even when nothing needs fixing.
5. Only if this repository has genuinely repo-specific instructions beyond its own
   CLAUDE.md/AGENTS.md/README.md, add .github/claude/shared.md and/or
   .github/claude/<mode>.md (additive only — see the README's "Adding repository-local
   instructions" section). Don't create these files with generic or empty content.
6. Commit the new workflow file(s) and open a pull request. Don't merge it.

Report back: which mode(s) you set up, whether a credential secret already existed, and
anything from step 4 that needs my attention before this can actually run.
```
