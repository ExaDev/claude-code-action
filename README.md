# Claude Code Action

Runs Claude Code in GitHub Actions, for three jobs:

| Mode            | What it does                                                                                                                                                                | When it runs                                                               |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| **review**      | Reviews a pull request and submits a formal review — inline comments plus a summary body, requesting changes on any real finding and approving when only minor nits remain. | A pull request is opened, pushed to, reopened, or marked ready for review. |
| **triage**      | Classifies a new issue (native issue type, labels, sub-issue/blocker relationships), hunts for duplicates, and says what information is missing.                            | An issue is opened, or re-labelled for re-triage.                          |
| **interactive** | Answers a question, or makes a change on a branch and opens a pull request for it.                                                                                          | Someone with write access mentions `@claude` in a comment or review.       |

## Why this exists rather than per-repository workflows

This wraps Anthropic's own [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) (MIT licensed). Every consuming repository could call that directly, but then each one would carry its own copy of the review instructions, its own tool allowlist, and its own idea of what "review a pull request" means. Those copies drift, and improving the review prompt would mean editing every repository.

Instead, a consuming repository gets a workflow file of roughly ten lines, and this repository holds the prompts, the tool allowlists, the per-mode permission scoping, and the pinned upstream version. Changing how review works everywhere is a change here.

The prompts also encode something worth knowing before you rely on them: plenty of real repositories are inherited, sparsely documented, and inconsistent between directories, with no written-down conventions. The prompts are written for that rather than assuming a greenfield project, and review mode is required to distinguish a finding that rests on the project's own documented policy from one that rests on a general convention for the stack. See [Documented policy versus stack default](#documented-policy-versus-stack-default).

## Adopting it in a repository

**1. Make a Claude credential available.** Set one of these as an organisation secret (Settings → Secrets and variables → Actions), so every repository inherits it, or as a repository secret for a single repository:

- `ANTHROPIC_API_KEY` — an Anthropic API key.
- `CLAUDE_CODE_OAUTH_TOKEN` — a Claude Code OAuth token, if the organisation bills through a Claude subscription rather than API credit.

Either works. Set one; the run fails with an explicit error if neither is present. The examples below use `ANTHROPIC_API_KEY`, so change the secret name if you use the OAuth token instead. A second (or third, or more) credential of either kind can be added later, to fall through to if the first fails — see [Credential fallback](#credential-fallback) — but is not needed to get started.

**2. Copy the workflows you want** from [`examples/`](examples/) into the repository's own `.github/workflows/`. There are two forms:

| Copy this                                                            | To                                         | Gives you             |
| -------------------------------------------------------------------- | ------------------------------------------ | --------------------- |
| [`examples/claude-review.yml`](examples/claude-review.yml)           | `.github/workflows/claude-review.yml`      | Pull request review   |
| [`examples/claude-triage.yml`](examples/claude-triage.yml)           | `.github/workflows/claude-triage.yml`      | Issue triage          |
| [`examples/claude-interactive.yml`](examples/claude-interactive.yml) | `.github/workflows/claude-interactive.yml` | `@claude` in comments |

These call this repository's reusable workflows. They are the shorter, recommended form: the per-mode least-privilege `permissions:` are held in the reusable workflow, so an adopting repository does not have to reason about token scopes unless its own default workflow permissions fall short of what a mode needs — see step 3 below for when and how to add a `permissions:` block to the caller.

They are independent. Take one, two, or all three.

The event trigger lives in the caller, not here, because a reusable workflow is invoked by a job and the caller's own `on:` block decides when. That is also where you would narrow things: add a `paths:` filter to skip review on documentation-only changes, or a `branches:` filter to review only pull requests targeting `main`.

**Direct (composite-action-step) alternative.** [`examples/direct/`](examples/direct/) holds the same three modes as ordinary workflows that call `ExaDev/claude-code-action@v1` directly as a step (with their own `actions/checkout` and `permissions:` block). Use the direct form when you need OIDC-based auth (Bedrock/Vertex/Foundry/Anthropic federation), which needs `id-token: write` reaching the composite action call itself — none of the three reusable workflows this repository ships declare that scope in their own hardcoded `permissions:` block, so no amount of caller-side permission-granting can pass it through (see step 3); or **review running as the Claude Code GitHub App (`claude[bot]`)** rather than `github-actions[bot]`, for the same reason. That App identity is the only one that can resolve the bot's own stale review threads (`resolve_stale_threads`) and submit formal reviews via moderation — the reusable form's `github-actions[bot]` token is forbidden from both. The review direct example handles this for you (it declares `id-token: write`, omits `github_token`, and requires the Claude Code App installed plus a `CLAUDE_CODE_OAUTH_TOKEN`); see its header comment for the scope trade-off. Otherwise prefer the reusable form above — it is shorter, and a caller-side `permissions:` block (step 3) covers everything else a mode might need beyond the repository default.

**3. Add a `permissions:` block to the caller job if this repository's own default workflow permissions fall short of what the mode needs.** A job that declares no `permissions:` block of its own gets this repository's (or organisation's) current default workflow permissions setting as its effective `GITHUB_TOKEN` scope. When that job then calls a reusable workflow, GitHub checks the reusable workflow's own requested `permissions:` against that effective scope _before dispatching any job at all_ — a reusable workflow's permissions can only be downgraded from what the caller provides, never elevated — and refuses to start the run when the request exceeds it: a generic, jobless `startup_failure` ("This run likely failed because of a workflow file issue"), with no further diagnostic text anywhere. `actionlint` does not catch this; it only shows up as `startup_failure` when the workflow actually runs, confirmed live and reproduced on a throwaway test PR against this very repository. Confirm your repository's default (Settings → Actions → General → Workflow permissions) covers at least `contents: read` plus whatever write scope the mode you're adopting needs (see the table above); if it doesn't, and tightening the repository-wide default isn't what you want, declare a `permissions:` block on the caller job itself, matching the called reusable workflow's own documented scope exactly (see [What each mode is allowed to do](#what-each-mode-is-allowed-to-do)) — a job calling a reusable workflow, in this repository or a different one, can perfectly well declare its own `permissions:`; nothing about crossing that boundary forbids it. What a caller-side grant cannot do is reach `id-token: write` through to the composite action call nested inside the reusable workflow: none of `review.yml`/`triage.yml`/`interactive.yml` declare that scope in their own hardcoded `permissions:` block, so there is nothing for a caller-side grant to flow into. Use the [direct form](examples/direct/) instead for OIDC-based auth or App-identity review.

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

## Credential fallback

`anthropic_api_key` and `claude_code_oauth_token` each accept a single value — the default, and everything above assumes this — or several newline-separated values, tried in order, falling through to the next one if an earlier attempt fails. Useful when a subscription runs out of quota, hits a rate limit, or is otherwise unavailable and a second account should pick up the same run rather than the whole workflow failing outright. Every value found across both inputs flattens into one ordered chain — every OAuth token first, in the order given, then every API key — and the moment one succeeds, nothing further is attempted; every later step (the turn-limit wrap-up, the automatic fix pass, the structured review summary) authenticates against that same successful account, never whichever came first.

```yaml
claude_code_oauth_token: |
  ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN_PRIMARY }}
  ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN_BACKUP }}
```

A composite action has no native loop construct, so this is implemented as five statically unrolled attempt steps in `action.yml` (`attempt_1` .. `attempt_5`) rather than a real loop — up to 5 credentials total, across both inputs combined, are supported; supplying more fails the run immediately with an explicit error rather than silently trying only the first 5. Supplying neither input at all (Bedrock/Vertex/Foundry, workload identity federation, or an org/repo-level environment variable instead) is unaffected: a single attempt runs with no explicit credential passed through, exactly as before this existed.

Two things worth knowing before relying on it:

- **Fallback is aimed at failures that happen before Claude does anything on GitHub.** An expired, revoked, or rate-limited credential fails at authentication, before any branch, comment, or review exists — the common case this is for. If a run instead fails mid-conversation, after already creating a branch (`branch_name_template`'s own default includes `{{timestamp}}`, so a fresh trigger gets a new branch name on every attempt) or posting a sticky comment (whose own lookup for "the comment to update" has a confirmed upstream bug when a custom `github_token` is supplied — [anthropics/claude-code-action#960](https://github.com/anthropics/claude-code-action/issues/960), which this action always does), the next credential's attempt starts fresh rather than resuming that state, and can leave a duplicate or orphaned branch or comment behind. This action does not try to reconcile that — worth checking for after any run that actually needed more than one attempt.
- **Do not enable `ACTIONS_STEP_DEBUG`/`ACTIONS_RUNNER_DEBUG` on a workflow using this.** Each parsed credential is masked (`::add-mask::`) the moment it is read, which keeps it out of every subsequent log line for the rest of the job — but the runner has a long-standing, still-open bug ([actions/runner#159](https://github.com/actions/runner/issues/159), [actions/runner#475](https://github.com/actions/runner/issues/475)) where step debug logging can print a value on the very same line that registers its own mask, before the mask takes effect. Normal logging never triggers this; debug logging specifically does.

## What each mode is allowed to do

Each mode is a separate reusable workflow with its own hardcoded `permissions:` block. That separation exists because a GitHub Actions `permissions:` block cannot branch on an input value, so scoping each mode to least privilege requires separate entry points.

| Mode        | Token scopes                                                                                                                                                           | Tools                                                                                                                                                                                                                                                                                                                                                                                             |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| review      | `contents: read`, `pull-requests: write`, `actions: read` (`contents: write` instead of `read` when [automatic fixes](#automatic-fixes) are enabled, direct form only) | Submit a formal review (inline comments plus a summary body); read the diff and the code. No file writes, no commits, no push, no merge — **unless** one of the opt-in automatic-fix inputs is on, which adds a separate follow-up call that can write files and commit, and one step that pushes that commit to the pull request's own branch. Still no merge, and never on a fork pull request. |
| triage      | `contents: read`, `issues: write`                                                                                                                                      | View, list, comment on, label, assign, and edit issues (including setting a native issue type, sub-issue, or blocker relationship, and — when `update_issue_body` is on — the issue's own body); read the code. No pull-request scope at all.                                                                                                                                                     |
| interactive | `contents: write`, `pull-requests: write`, `issues: write`                                                                                                             | Read and edit files, commit to a new branch, push it, open a pull request, comment. No merging, no closing, no releases, no secrets, no workflow edits.                                                                                                                                                                                                                                           |

`actions: read` on review is there solely so the optional `include_ci_logs` input can read failing workflow logs. Because a reusable workflow's permissions cannot be conditional, the scope is declared unconditionally even when the input is off. It is read-only and covers workflow run metadata and logs. If you want strictly the two scopes review actually uses, call the composite action directly with your own `permissions:` block instead of going through the reusable workflow.

Beyond token scopes, each mode passes a `--allowedTools` allowlist and a `--disallowedTools` denylist to Claude Code, so review genuinely cannot write a file even if it decided to try. That remains true of the review call itself in every configuration, including with an automatic-fix input on: `Write`, `Edit`, and `NotebookEdit` stay on its denylist, and the fix, if any, happens in a separate call with a separate allowlist after the review has already been submitted. The prompts state the same limits in prose, but the allowlist is the control.

**Review submits a formal review, not comments.** Review mode opens a pending GitHub review, adds each finding as an inline review comment on its line, and submits a decisive state: `CHANGES_REQUESTED` if it raised any Should-fix or Blocker, `APPROVED` when only Nits (or nothing) remain, and `COMMENT` only as a fallback (when the honest state is not in the allowed set, or the call is genuinely borderline). The `allowed_review_states` input (see [Review states](#review-states)) controls which of those states the bot may submit — the default allows all three, so a clean PR can be merged on the bot's review alone; drop `approve` where that is not wanted. The pending-review tools are served by the official `github/github-mcp-server`, which the upstream action runs as a Docker container on the runner when it sees an `mcp__github__*` tool in the allowlist, so the review job needs a runner with Docker available (`ubuntu-latest` has it). That server exposes its full toolset over MCP — issues, repositories, code, and more — and the upstream auto-provisions it without a server-side toolset restriction, so the `--allowedTools` list above is the sole boundary keeping every other tool out of reach. That is the same client-side-allowlist model every tool in every mode already relies on, but it is worth stating plainly here because the surface area behind this one server is larger than the narrow bundled comment server it replaced.

## Security notes

**Who can trigger a run.** By default only users with repository write access, because the underlying action checks write permission before doing anything. The `allowed_non_write_users` input widens that, and it is off by default in all three modes deliberately.

- For **triage**, you will probably want `allowed_non_write_users: "*"`, since the issues worth triaging are usually opened by people without write access. That is the setting in the triage example. It is defensible there because triage holds no code-write or pull-request scope: the worst case is a misleading label and a wrong comment.
- For **interactive**, leave it unset. That mode can edit code, commit, and push a branch, so allowing users without write access to invoke it hands them write access by proxy through text the model interprets. If you want Claude responding to outside reporters, use triage.

**Fork pull requests and the `GITHUB_TOKEN` downgrade.** GitHub automatically restricts the ambient `GITHUB_TOKEN` to read-only for any `pull_request`-triggered run originating from a fork, regardless of what `permissions:` a workflow declares — this is a platform-level protection, not something any input here controls. That's why review mode's own example (`examples/direct/claude-review.yml`) uses the direct form and deliberately leaves `github_token` unset: doing so makes the run authenticate as the Claude Code GitHub App (`claude[bot]`) instead, a separately-minted credential via OIDC that isn't subject to that downgrade. Reviewing a fork pull request through the reusable workflow's default `GITHUB_TOKEN` would appear to run successfully but silently fail to post — worth knowing if a repository that accepts fork pull requests seems to review nothing. Separately, GitHub's own "Require approval for first-time contributors" repository setting (on by default for public repositories) gates _any_ workflow run — including this one — from an unknown contributor's fork pull request until a maintainer approves it once in the Actions UI, on top of everything above.

**Untrusted text reaches the model.** Issue bodies, comments, pull request descriptions, and the contents of a pull request's own files are attacker-influenced input on a public repository or one accepting fork pull requests. The shared prompt tells Claude to treat all of it as data rather than instructions and to report injection attempts, but a prompt is mitigation, not a guarantee. The real controls are the per-mode token scopes and tool allowlists above: assume the prompt can be subverted and check that the blast radius is acceptable if it is.

One consequence is worth being explicit about: on a `pull_request` event the checkout includes the pull request's own changes, so a fork pull request can modify `.github/claude/review.md` (see below) or the repository's `CLAUDE.md` and thereby change the instructions used to review it. Review mode holds no write scope to repository _contents_ — it cannot edit files, commit, or push — but that no longer bounds the damage to a misleading review by default, because four on-by-default-or-opt-in inputs widen what a subverted review (or its own follow-up call) can do within the token's `pull-requests` scope. `include_suggestions` lets it emit a fenced `suggestion` block an author might one-click apply (not a permission escalation — the author's Apply is the write, the bot has none — but it removes the friction of reading and re-typing a prose fix, so a malicious "fix" gets less scrutiny). `fix_pr_metadata` grants the whole `mcp__github__update_pull_request` tool, not just a title/body-scoped slice of it — the tool itself also accepts `state` (it can close the pull request), `base`, `draft`, `maintainer_can_modify`, and `reviewers`, so a subverted review can call it with any of those, no `gh api:*` needed; only the prompt restricts its own use of the tool to title and body. `resolve_stale_threads` adds `gh api:*` to the review allowlist, so a subverted review gains the whole REST/GraphQL surface within that `pull-requests` scope (editing the PR's title, body, or labels; posting arbitrary comments; blanking or rewriting any review's body, not only the bot's own, since nothing at the API layer restricts the call to reviews the bot itself submitted — only the prompt's own filter-by-login step does) — a second, broader route to the same title/body write, and to more besides. `structured_review_summary`, though opt-in rather than on by default, grants the same `gh api:*` surface to its own follow-up call for the same reason (reading inline review comments has no narrower `gh pr view --json` field) — only the prompt restricts that call to reading. `include_ci_logs`, never previously listed here, belongs on this list too now that it does more than inform prose: it grants tools that fetch this pull request's own workflow logs, which are attacker-influenced on a fork pull request (a test name, an assertion message, or anything else the change causes CI to print lands in the model's context), and it is the input `fix_ci_failures` (below) reads to decide what to change. On its own it is still read-only and low-risk; paired with `fix_ci_failures` it is the input path into a write. On a repository that accepts untrusted fork pull requests, set `include_suggestions: false`, `fix_pr_metadata: false`, `resolve_stale_threads: false`, `verify_prior_findings: false`, and leave `structured_review_summary`, `fix_ci_failures`, `fix_diff_findings`, and `add_regression_tests` off (their defaults) until a human has reviewed the change, and do not treat a review of an untrusted pull request as a security control.

`fix_ci_failures` and `fix_diff_findings` are different in kind from everything above, and the difference is worth stating exactly. Everything above widens what a subverted review can do _within the token's `pull-requests` scope_ — write a comment, retitle, close. These two add a call that can write files and commit, and a job that holds `contents: write`. Three things bound that, and none of them is the prompt: **the review call itself is unchanged** (`Write`, `Edit`, and `NotebookEdit` stay on its denylist, so the call that reads untrusted diff content and the call that can write a file are different calls with different allowlists); **the push target is fixed in the action** (one refspec, this pull request's own head branch, computed in bash and unreachable from any prompt — the model has no `git push` tool at all, and the whole write is discarded with the runner if the publishing step does not push it); and **a fork pull request never reaches the fix call**, because the job's token cannot push to a fork regardless of `maintainer_can_modify`, so the pass is skipped before a call is even paid for. That last point is what makes this defensible at all: the untrusted-input scenario this section is about is precisely the scenario in which the write path is mechanically unreachable. What is _not_ bounded mechanically is the content of a fix on a same-repository pull request, and the `contents: write` the direct form's job must hold is broader than the one branch the action pushes to — **branch protection on the default branch is what stops that becoming a direct push**, exactly as it already is for interactive mode. `add_regression_tests` adds no new capability of its own, only more written lines alongside a fix already being made. Leave all three off (their default) unless every pull request in the repository comes from someone you would already give write access to — they are not something to enable estate-wide.

`verify_prior_findings` is a third kind of risk, different again from both clusters above. Every input discussed so far governs how much a subverted review can do _within GitHub's own API surface_ — writing a comment, retitling, closing, or (for `fix_ci_failures`/`fix_diff_findings`) committing to a fixed, bounded branch. `verify_prior_findings` grants `WebFetch` instead, which is not GitHub-scoped at all: it is arbitrary network egress to any host the model chooses to fetch, mediated by nothing this action's token permissions bound. The prompt restricts it to a URL the model reasoned its own way to (a package's own registry or documentation site) and forbids following any URL that appears in the diff, the pull request description, or a comment — exactly the kind of untrusted content a subverted review could otherwise use to redirect the fetch — but, as with every other prompt-only restriction in this list, that boundary is enforced by the prompt alone, not by anything technical. It is deliberately not domain-scoped: this action's stack fragments already span enough different package registries and documentation hosts that a maintained allowlist would either lag behind real usage or need constant upkeep, so set `verify_prior_findings: false` (see above) rather than relying on a narrower grant that does not exist.

**Branch protection matters.** Interactive mode holds `contents: write`. Its prompt forbids committing to the default branch, force-pushing, and rewriting history, but branch protection on the default branch is what actually enforces it. Turn it on.

**Cost and loops.** Interactive mode is gated on the trigger phrase in the reusable workflow's job condition rather than inside the action. This is load-bearing: supplying a prompt puts the underlying action into agent mode, which runs unconditionally and does not check the phrase itself. Without that condition every comment on every issue would start a paid run. The review example includes a `concurrency` block that cancels a superseded review when the author pushes again.

## Repository conventions come first

Before reviewing, Claude looks for the repository's own stated conventions, in this order, and treats the first one it finds as authoritative:

1. `CLAUDE.md` at the repository root
2. `AGENTS.md` at the repository root
3. `README.md` at the repository root

Whatever it finds overrides the general guidance in this action's prompts, including the stack fragments. It also reads configuration that encodes a convention mechanically, such as linter, formatter, and type-checker settings, because a rule enforced by a committed config file is policy rather than preference.

If none of the three exists, Claude falls back to stack conventions and is told to say so.

### Documented policy versus stack default

Review mode tags every substantive finding:

- **`[policy]`** — grounded in this repository's own documented conventions, a committed lint or formatter configuration, or an explicit contract in the code such as a type signature or schema.
- **`[stack-default]`** — grounded in general convention for the stack, and nothing this project has agreed to.

When no conventions document is found at all, the composed prompt says so explicitly and warns that almost everything will be `[stack-default]`, so that a stack default is never presented as though the project had signed up to it.

This distinction is the point rather than a nicety. Plenty of repositories haven't documented their conventions yet, and it's worth being able to see, in practice, which review comments reflect real project policy and which are the model's assumptions. A run producing nothing but `[stack-default]` findings is a signal that the repository would benefit from a `CLAUDE.md`.

### Severity labels and emoji ratings

Every finding also carries a text severity label — **Blocker**, **Should fix**, or **Nit** — independent of the policy/stack-default tagging above. Text labels are always present; they're not configurable.

On top of the text label, a finding can optionally carry an emoji for at-a-glance severity: 🔴 Blocker, 🟠 Should fix, 🟡 Nit. This is controlled by review mode's `severity_ratings` input (`always`, `optional`, or `never`; default `optional`):

- **`always`** — every finding gets the emoji.
- **`optional`** (the default) — the model decides per finding whether the emoji adds real scanning value, and leaves it off where the text label already makes severity obvious.
- **`never`** — no emoji ratings at all; text labels only.

Deliberately emoji rather than an external badge image (the kind rendered via a shields.io-style URL): no network dependency for something that renders in every comment, and no risk of a broken image if that external host is ever unreachable.

## Review states

The `allowed_review_states` input (review mode only) controls which GitHub review states the bot may submit — a comma-separated subset of `changes_requested`, `comment`, and `approve`:

- **`changes_requested,comment,approve`** (the default) — request changes on any Should-fix or Blocker, approve when only Nits remain (or the review is clean), and comment only as a fallback. An approval can satisfy a "required review" branch-protection rule, so this default means a clean PR can be merged on the bot's review alone — drop `approve` on any repository where you want a human to be the only one who can greenlight a merge.
- drop **`approve`** (e.g. `changes_requested,comment`) — the bot comments and requests changes but never approves; a human is always required for the merge decision.
- drop **`changes_requested`** (e.g. `comment,approve`) — comment-only reviews (plus approve on clean), for repositories that find an automated "request changes" too noisy or that don't want a bot able to block a merge.

`comment` is always available as the truthful fallback, so the bot never misrepresents its findings to fit the configured list: it never submits `APPROVED` for a review that raised a Should-fix or Blocker, and never submits `CHANGES_REQUESTED` for a review with only Nits or nothing. The review body and inline comments always reflect what it actually found, regardless of the state submitted.

## Automatic fixes

Three opt-in review-mode inputs — all off by default, and the largest widening of what review mode can do — turn a review into something that can also change the code: `fix_ci_failures` (acts on this pull request's failing CI; requires `include_ci_logs: true`, and the run fails at validation if you set one without the other rather than silently finding nothing to fix), `fix_diff_findings` (acts on the Blocker and Should-fix findings the review itself raised, at the same confidence bar a suggestion block already has to meet), and `add_regression_tests` (adds a test alongside each fix; requires at least one of the other two). After the review is submitted, a second call with its own separate allowlist — `Write`/`Edit` and narrow verification commands, but no `git push` — resumes the same session, applies the fixes it is confident about, and commits them; the action then pushes that one commit to the pull request's own branch from a separate, deterministic step with a fixed refspec no prompt can influence.

**They only take effect in the [direct form](examples/direct/claude-review-with-fixes.yml).** The reusable form's `permissions:` block is hardcoded to `contents: read` and cannot branch on an input, so a pre-flight check (`git push --dry-run`, using the same credential a real push would use) fails there before any Claude call is made and the whole pass is skipped for free — the same way `resolve_stale_threads` no-ops in the reusable form. The same pre-flight check also means a pull request from a fork never reaches the fix call at all: this job's token cannot push to a fork's branch regardless of `maintainer_can_modify`, so the skip is mechanical, not prompt-shaped.

**Two identities in one job.** The review itself still runs as `claude[bot]` via the direct form's OIDC-minted App token, exactly as it does today. The fix commit's push authenticates separately, governed by its own `push_token` input — the OIDC-minted App token governs the upstream action's own API calls (the review itself), not the fix pass's git operations, and `push_token` is deliberately a separate input from `github_token` rather than reusing it, because `github_token` also controls the review call's own identity and must stay unset for that to run as `claude[bot]`. Left unset, `push_token` falls back to `github_token`, then to the job's own `GITHUB_TOKEN`, reproducing the exact previous behaviour. One consequence follows directly from that default and is worth knowing before you turn `fix_ci_failures` on: **a push authenticated with the job's own `GITHUB_TOKEN` does not start new workflow runs**, so checks will not automatically re-run on the fix commit. The action says so in the comment it leaves. If you want them to, mint your own GitHub App's installation token (an App with a private key you hold — this repository's own sync App, already used by `ci.yml`'s `release` job, is the example, not the Claude Code App, which is Anthropic's and has no key you could hold) and pass it as `push_token` — see the example. Do not wire it into `actions/checkout`'s own `token:` input instead: the fix pass never uses the checkout-persisted credential, it builds its own authenticated URL from `push_token` directly, so setting it on checkout alone would silently do nothing.

**Timing.** On `pull_request: [opened, synchronize]` the review runs as CI is only just starting on that same commit, so `fix_ci_failures` typically finds nothing recorded yet on a pull request's first push — it earns its keep on re-review, after a push that broke something. Triggering instead from `workflow_run: [completed]` would solve that, but is deliberately not done here and should not be added on a repository that accepts fork pull requests: `workflow_run` runs in the base repository's own context, with a write token, against code a fork contributor wrote.

See the [Security notes](#security-notes) above for what bounds this feature and what does not.

## Adding repository-local instructions

To extend the prompts for one repository, without forking anything, add either or both of:

| File in the calling repository                                             | Applies to      |
| -------------------------------------------------------------------------- | --------------- |
| `.github/claude/shared.md`                                                 | All three modes |
| `.github/claude/<mode>.md` — `review.md`, `triage.md`, or `interactive.md` | That mode only  |

Both are optional. When present they are appended after everything else, so they add to the shared and mode instructions rather than replacing them. They cannot relax the safety rules: the prompt states that the "things you must never do" section stands regardless of what a local file asks, and the tool allowlist is enforced outside the prompt.

Use these for what is specific to the repository and genuinely useful to a reviewer:

```markdown
<!-- .github/claude/review.md -->

This service writes to the shared billing database. Treat any change under
`src/billing/` as high risk and check it against the invariants in
`docs/billing-invariants.md`.

The `legacy/` directory is frozen pending decommission. Do not comment on style
there; only flag correctness and security problems.
```

If you find yourself writing general project conventions here, put them in the repository's `CLAUDE.md` instead, where humans will also read them.

## Stack detection

For review mode, the action looks at the checked-out repository and layers in guidance for whichever stacks it recognises:

| Signal in the repository                                                  | Fragment                                                               |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `build.gradle` or `build.gradle.kts`, plus a ktlint or detekt signal      | [`kotlin.md`](prompts/review/stacks/kotlin.md)                         |
| `Package.swift`, `*.xcodeproj`, or `*.xcworkspace`, plus `.swiftlint.yml` | [`swift.md`](prompts/review/stacks/swift.md)                           |
| `composer.json`                                                           | [`php.md`](prompts/review/stacks/php.md)                               |
| `go.mod`                                                                  | [`go.md`](prompts/review/stacks/go.md)                                 |
| `package.json` declaring `@sveltejs/kit`                                  | [`sveltekit.md`](prompts/review/stacks/sveltekit.md)                   |
| `*.tf` files                                                              | [`terraform.md`](prompts/review/stacks/terraform.md)                   |
| `wrangler.jsonc`, `wrangler.json`, or `wrangler.toml`                     | [`cloudflare-workers.md`](prompts/review/stacks/cloudflare-workers.md) |
| `tsconfig.json`                                                           | [`typescript.md`](prompts/review/stacks/typescript.md)                 |
| `pubspec.yaml`                                                            | [`flutter.md`](prompts/review/stacks/flutter.md)                       |
| `package.json` plus `schema.prisma` or a Prisma dependency                | [`node-prisma.md`](prompts/review/stacks/node-prisma.md)               |

Detection walks up to four directory levels, so a monorepo's `services/api/go.mod` and `packages/web/package.json` are both found, and it skips `node_modules`, `vendor`, `.terraform`, `Pods`, and the usual build output directories.

**More than one fragment can apply.** A repository with a Go service, a SvelteKit front end, and Terraform infrastructure gets all three, which is the honest answer for a polyglot repository and avoids an arbitrary priority order deciding what a reviewer is told. Gradle and Swift additionally require a lint configuration, so a Java-only Gradle build does not pull in Kotlin guidance.

If nothing matches, review runs on the shared and review base prompts alone. It does not guess at a stack.

To add a stack: write `prompts/review/stacks/<name>.md`, add the detection to the `Detect stack` step in `action.yml`, add a row to the table above, and bump the minor version.

## Calling the action directly

The reusable workflows are the supported entry point, but the composite action can be used on its own if you need a different trigger, your own `permissions:` block, or extra steps in the same job:

```yaml
jobs:
  review:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v7
      - uses: ExaDev/claude-code-action@v1
        with:
          mode: review
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

`mode` is the only required input. Every other input is optional with a default — `action.yml` is the source of truth for the full list, and every input keeps the upstream action's own name, so anything you already know about `anthropics/claude-code-action` applies. See [Extended options](#extended-options) below for what's available beyond the basics (`anthropic_api_key`, `claude_code_oauth_token`, `github_token`, `settings`, `trigger_phrase`, `allowed_bots`, `allowed_non_write_users`, `include_ci_logs`, `model`, `extra_claude_args`).

`extra_claude_args` is appended after the arguments derived from the mode. Because `--allowedTools` and `--disallowedTools` accumulate upstream rather than overwrite, passing `--allowedTools` there widens the mode's allowlist rather than replacing it. It cannot narrow it: to take a tool away, change the mode's allowlist in `action.yml`.

If you call the action directly and omit `github_token`, the underlying action will try to mint a GitHub App token. The reusable workflows always pass the job's own `GITHUB_TOKEN`, so no App installation is needed.

## Extended options

Beyond the basics, every mode's reusable workflow exposes further optional inputs (a subset of the full set on `action.yml`, chosen per mode — the composite action itself accepts all of them if you call it directly). None of these are mandatory; each has a default that reproduces today's behaviour if you don't set it.

**Progress and comment behaviour** (`review`, `triage`, `interactive`): `track_progress` and `use_sticky_comment` are pure passthroughs to upstream's own tracking-comment mechanism, which only its `tag` mode implements — every mode this action runs always sets a `prompt` (see "Compose prompt" in `action.yml`), which upstream's `detectMode` treats as `agent` mode regardless of `track_progress`/`use_sticky_comment`, so **neither input has any visible effect through this action**; they are exposed only because they are harmless passthroughs, not because they do anything here. `post_progress_comment` (on by default) is the input that actually gets you a visible signal: it posts a plain "Claude is working on this" comment via `gh api`, entirely from this action's own steps rather than upstream, before the run starts, and edits that same comment once the run (and any optional follow-up pass) finishes. It needs no special token identity — just whatever `issues: write` / `pull-requests: write` scope the calling job already grants for its own mode — so it works in both the reusable-workflow and direct forms. Set it `false` to restore the previous silent-until-output behaviour. `include_comments_by_actor` / `exclude_comments_by_actor` filter whose comments feed into context (supports `*[bot]` wildcards) — worth setting `exclude_comments_by_actor` on `interactive` specifically, since that mode already treats comment text as untrusted input per the security notes above. `include_fix_links` (`review` only, on by default upstream) adds "fix this" links to findings.

**Review behaviour** (`review` only): `severity_ratings` controls emoji severity on findings (see [Severity labels and emoji ratings](#severity-labels-and-emoji-ratings)); `allowed_review_states` controls which review states the bot may submit — including whether it can approve (see [Review states](#review-states)); `include_suggestions` (on by default) controls whether review comments carry apply-able GitHub suggestion blocks for findings with a confident, drop-in fix — set `false` for prose-only reviews; `fix_pr_metadata` (on by default) checks whether the pull request's title and description are complete and accurate and rewrites them directly, grounded in the diff, when they fall short — the allowlist grants the whole `update_pull_request` tool, which can also close the pull request or change its base branch, and only the prompt restricts it to the title and body fields, so treat this as at least as sensitive as `resolve_stale_threads` below and set `false` on repositories that accept untrusted fork pull requests; unlike `resolve_stale_threads` it needs no special token identity and works in both the reusable-workflow and direct forms; `resolve_stale_threads` (on by default) resolves the bot's own prior review threads that a new revision has addressed, updates ones whose finding still holds but whose comment text has drifted out of sync with the diff, and dismisses the bot's own prior `CHANGES_REQUESTED` or `APPROVED` reviews on re-review regardless of what the new review's own verdict turns out to be — clearing each dismissed review's body first, since GitHub's dismissal only changes state and otherwise leaves the write-up fully visible on the timeline — so neither stale comments nor a stale blocking-or-approving verdict accumulate across pushes — **it only takes effect in the [direct form](examples/direct/claude-review.yml)**, which runs review as `claude[bot]` (the reusable form's `github-actions[bot]` is forbidden from resolving threads, so the step no-ops there); it also widens the review allowlist (adds `gh api:*`), so set `false` on repositories that accept untrusted fork pull requests; `verify_prior_findings` (on by default) re-checks a technical claim a past review made — whether an API exists, how it is meant to be used, what a version supports — against the actual package, lockfile, or vendored source, and against current documentation via `WebFetch` when that is not decisive on its own, before trusting that claim again on a re-review; unlike `resolve_stale_threads` it needs no special token identity and works in both the reusable-workflow and direct forms, but it grants unrestricted `WebFetch` — arbitrary network egress that nothing else in this allowlist grants — so set `false` on repositories that accept untrusted fork pull requests; `include_ci_logs` grants the CI-inspection tools so a review can read and mention this pull request's failing workflow logs (needs the calling job to hold `actions: read`); `classify_inline_comments` (on by default) buffers inline comments Claude hasn't marked `confirmed=true` and classifies each as a genuine finding or a test/probe before posting once the session ends, so low-value probe comments are suppressed from the final review — set `false` to restore immediate, unbuffered posting of every inline comment (upstream's pre-buffering behavior); `structured_review_summary` (off by default, unlike the toggles above) runs a bounded follow-up call after the review that re-fetches what was actually submitted and produces a `structured_output` JSON summary (`review_state`, and finding counts by `blocker`/`should_fix`/`nit`) for a caller to consume — it costs a second call on every review regardless of whether anything reads the output, which is why it defaults off rather than on; a schema-validation failure in that follow-up call only leaves `structured_output` empty, it cannot fail the review itself, which has already been submitted by the time the follow-up starts.

**Branch and commit behaviour** (`interactive` only — `review` and `triage` hold no write scope, so these are absent from those two workflows entirely, not just defaulted off): `base_branch`, `branch_prefix` (default `claude/`), and `branch_name_template` control how a fix branch is named and based. `use_commit_signing` turns on GitHub's own commit signature verification with no key management required — it's a plain boolean, off by default, nothing to provision. `ssh_signing_key` is a separate, optional **secret** (a real SSH private key) for signing commits yourself instead; it takes precedence over `use_commit_signing` if both are set. Neither is required — plain git commits are the default if you set neither.

**Bot identity** (all modes): `bot_id` / `bot_name` control the identity used for git commit authorship specifically (separate from `github_token`, which governs API calls and therefore who _comments_ appear from). Default to Claude's own upstream identity (`41898282` / `claude[bot]`) — leave them unset rather than passing an empty string, which would blank that identity out instead of falling back to it.

**Plugins** (all modes): `plugins` / `plugin_marketplaces` install Claude Code plugins before the run.

**Alternative model providers** (all modes): `use_bedrock`, `use_vertex`, and `use_foundry` switch off the direct Anthropic API. If your cloud credentials come from static secrets in the calling job's own environment (an AWS access key, a GCP service account JSON key), this works fine through the reusable workflows — set the relevant credentials in your own caller workflow's `env:` before it calls one of ours. **Only the OIDC-based path is restricted**: authenticating via GitHub's own OIDC token — whether that's Bedrock/Vertex/Foundry's own OIDC support, or the `anthropic_*` workload-identity-federation inputs — needs `id-token: write` reaching the composite action call itself, and (per step 3 above) none of this repository's reusable workflows declare that scope in their own hardcoded `permissions:` block — so there is nothing for even an explicit caller-side grant of `id-token: write` to flow into. If you need OIDC-based auth specifically, call `ExaDev/claude-code-action@v1` directly from your own job with your own `permissions:` block instead of going through review.yml/triage.yml/interactive.yml.

**Output verbosity** (all modes): `display_report` and `show_full_output` are debugging aids, both off by default and both carrying the same warning upstream gives — they can surface Claude-authored or tool-execution content (potentially including secrets) in public Actions logs, so only enable them in trusted, non-sensitive contexts.

**Explicit entity-number and prompt-directory overrides** (all modes): `pr_number` and `issue_number` override the pull request or issue number this run is about — every mode auto-detects this from the triggering event (`github.event.pull_request.number` / `github.event.issue.number`) by default, so these are only needed for a trigger that carries no such context of its own (`workflow_dispatch`, a matrix-driven batch run). `triage_label` (default `needs-triage`) and `update_issue_body` (triage only, on by default) are described in [Stack detection](#stack-detection)'s sibling section on triage below. `prompt_dir` overrides which directory's `base.md` this run loads instead of the one `mode` would normally select — a rarely-needed escape hatch for testing a fragment set without changing what mode actually runs as.

**Upstream trigger passthroughs, currently inert through this action** (all modes): `assignee_trigger` and `label_trigger` are forwarded to upstream unchanged, but every mode this action runs always sets `prompt` (see "Compose prompt" in `action.yml`), which puts upstream into `agent` mode regardless of either input's value — `agent` mode never runs upstream's own trigger detection, only `tag` mode does. They're exposed only because they're harmless passthroughs, in the same spirit as `track_progress`/`use_sticky_comment` above, not because they currently do anything through this action.

**Custom executables** (all modes): `path_to_claude_code_executable` and `path_to_bun_executable` skip this action's automatic installation of either tool and use the given path instead. Debugging-only — an older or incompatible executable can cause problems the automatic install wouldn't.

## Triage: native metadata and issue-body updates

Beyond labelling and commenting, triage mode can set a native GitHub issue type (where the organisation has issue types configured — checked via `gh api /orgs/<owner>/issue-types`, skipped entirely on a 404), record a sub-issue relationship when an issue is clearly a component of an existing one, and note a blocker relationship when the issue text explicitly states a dependency ("blocked by #42"). None of these are inferred from topical similarity alone.

`update_issue_body` (on by default) additionally appends a short triage summary directly to the issue's own description, wrapped in `<!-- claude-triage:start -->` / `<!-- claude-triage:end -->` markers so a later re-triage can find and replace its own section rather than duplicating it — everything outside the markers is left untouched. Set it `false` to keep triage comment-only. `triage_label` (default `needs-triage`) names the label that, when applied to an already-triaged issue, re-runs triage — on a re-triage, existing metadata is checked before anything is changed, and nothing already set is removed unless it is now clearly wrong.

These native-metadata capabilities widen triage's allowlist with `Bash(gh api:*)` — no narrower `gh issue` subcommand covers setting an issue type or a sub-issue relationship — the same broad-but-documented trade-off `resolve_stale_threads`/`structured_review_summary` already make in review mode for the identical reason (see [Security notes](#security-notes)).

## Versioning

Releases are automated by [`semantic-release`](https://semantic-release.gitbook.io/) (`release.config.ts`), triggered by the `release` job in `.github/workflows/ci.yml` on every push to `main` that passes `required-checks` — the single gate job aggregating commitlint, actionlint, typecheck, lint, and format, so adding, renaming, or splitting a check only ever means editing that one job's `needs:` list, never touching branch protection settings. It computes the next version from the conventional-commit types of the commits since the last release, writes `CHANGELOG.md`, creates the GitHub Release and the version tag, and moves the moving `v1` tag to it (`scripts/move-major-tag.mjs`, a local plugin — semantic-release has no concept of a moving major tag, since that's a GitHub-Actions-consumer convention, not a package-semver one). Consuming repositories reference `@v1`; a breaking change would ship as `v2` and require callers to opt in.

**The commit type you use is the release decision — get it right.** `commitlint.config.ts` and `release.config.ts` share one list (`commitTypes` in `release.config.ts`) mapping each conventional-commit type to a release level:

- **`feat:` → minor.** Use this for anything that changes what Claude is actually told, not just new capabilities in the traditional sense — a reworded review instruction, a new stack fragment, a new input, a new mode. A reworded prompt changes what every repository in the organisation gets told; that is not a patch even though no application code moved.
- **`fix:`, `docs:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:` → patch.** A bug fix, a documentation correction, a security-motivated bump of the pinned upstream SHA — anything with no intended change in what Claude is told.
- **A commit footer of `BREAKING CHANGE:` → major.**

Never bundle a prompt change into a commit whose type says "no behavioural change" (e.g. `fix:` for a security-motivated SHA bump). Someone applying that release needs to be able to take it without also getting a change in review behaviour across the estate — split them into separate commits if both are needed in the same PR.

The upstream `anthropics/claude-code-action` dependency is pinned by commit SHA in `action.yml`, not by `@v1`, so an upstream tag move cannot change behaviour here without a commit in this repository. `CHANGELOG.md` records the SHA and the upstream version it corresponds to automatically, generated from the commit message describing the bump.

### One known limitation

The reusable workflows reference the composite action as `ExaDev/claude-code-action@v1`, a hardcoded tag, because GitHub does not allow an expression in `uses:` and a relative path inside a reusable workflow resolves against the _caller's_ checkout rather than this repository. So pinning a workflow to an exact ref, `.../review.yml@v1.2.3`, still runs the engine at whatever `v1` currently points to. Keep the `v1` tag moving with releases, and treat `@v1` as the intended way to reference both.

## Automated upstream bumps

Bumping the pinned `anthropics/claude-code-action` SHA above used to be entirely manual: notice a release, read its changelog, diff `action.yml`, decide whether this wrapper needs a matching change, commit, open a pull request, wait for review, merge. `.github/dependabot.yml` and `.github/workflows/dependabot.yml` automate the whole cycle for this repository's own dependency on its own upstream — not for any repository that consumes `ExaDev/claude-code-action`, which is unaffected.

`.github/dependabot.yml` also carries a second, independent `npm` ecosystem entry, added to give the CLI `investigate` now runs (`@anthropic-ai/claude-code`, see below) its own npm-tracked pin. Its bump pull requests aren't special-cased: `metadata`'s own gate above triggers on any Dependabot-authored pull request against this repository, not just an upstream Action bump, so every npm devDependency bump — the isolated CLI bump and the batched "everything else" group alike — already gets the same review-and-auto-merge treatment described below, skipping only the `investigate` step (whose own gate stays scoped to `is-upstream`, i.e. `anthropics/claude-code-action` bumps specifically).

Dependabot opens the bump pull request (with a seven-day cooldown, so a same-day compromised or broken release doesn't reach anything before there's been time to notice), and a Claude Code run reads every upstream release between the old and new pinned version — the changelog and the full commit diff, not just the target release's own notes — and decides whether this repository's `inputs:`/`outputs:` need a matching change: a new upstream input worth threading through, a renamed or removed one needing an update at the call sites, a renamed output. If so, it makes that change and commits it separately from Dependabot's own bump commit, typed by this section's own commit-type rules above (`feat:`/`fix:`, never `build:`, since that would understate a real behavioural change under Dependabot's patch-level commit). It leaves a pull request comment either way, so a human reviewer can see what was checked even when nothing needed to change.

The review that follows runs from `dependabot.yml` itself rather than from `claude-review.yml` (which explicitly excludes Dependabot-authored pull requests): a Dependabot-triggered run gets a forced-read-only `GITHUB_TOKEN` by GitHub's own platform design, and whether declaring a `permissions:` block on a job calling a reusable workflow (which is what `claude-review.yml` does — this is possible in general, see step 3 above) also lifts that Dependabot-specific restriction has not been tested; `dependabot.yml`'s own jobs call the composite action directly instead, which is the already-proven, already-working path. Declaring `permissions:` explicitly there is what lifts Dependabot's forced-read-only default for the plain `GITHUB_TOKEN`, so review here runs as `github-actions[bot]`, the same identity `claude-review.yml`'s reusable form already uses for every non-Dependabot pull request (so `resolve_stale_threads` stays a no-op here too — a pre-existing, accepted limitation, not something new). This deliberately does **not** act as the `claude` GitHub App the way [`examples/direct/claude-review.yml`](examples/direct/claude-review.yml) does: that App is owned by Anthropic ([github.com/apps/claude](https://github.com/apps/claude)), not this organisation, so there is no private key this organisation could ever hold to mint its token explicitly, and the alternative — OIDC, via `id-token: write` — triggers a GitHub platform check that the calling workflow file be byte-identical to the version on the default branch. A Dependabot pull request that bumps a pin used _inside_ `dependabot.yml` itself (`dependabot/fetch-metadata`, `actions/setup-node`) always fails that check, silently skipping the review step — confirmed live rather than theorised. The investigation job's own `git push`, which does need an identity other than `GITHUB_TOKEN` (a `GITHUB_TOKEN` push never retriggers a new workflow run, so without one the fix commit's checks would never run and nothing downstream would go green), instead authenticates as this repository's own sync App — the same App the `release` job above already uses — minted just for that one push and never used for reading or commenting, since it holds `contents: write` and nothing else.

Once that review actually clears — not merely runs; a `CHANGES_REQUESTED` state on the current head blocks auto-merge explicitly, since this repository's own branch ruleset has no required-review-count rule to enforce that on its own — the pull request auto-merges for a patch or minor bump (both configurable, see below). A major bump is still fully investigated and reviewed the same way; by default it never auto-merges, since a major means upstream's own interface contract broke, which is a decision for a human rather than a CI outcome — although that too can be opted into explicitly. Merging uses `--merge`, never `--squash`, so Dependabot's own commit and any adaptation commit stay distinct rather than being collapsed under one patch-level title.

**Configuring this pipeline.** Four secrets, read once by `metadata`'s own "Read configuration flags" step and threaded through as job outputs, control the pipeline described above. Each defaults to reproducing the behaviour described above when unset — none of this needs setting up to get that default behaviour.

| Secret                                        | Default when unset | What it controls                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------------------------------------- | ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `DEPENDABOT_INVESTIGATE_ENABLED`              | `true`             | Set to `false` to skip the "Investigate and adapt" Claude Code call entirely for every upstream bump — Dependabot's raw SHA-bump commit goes straight to review and (if it clears) auto-merge, with no agent editing `action.yml` unattended.                                                                                                                                                              |
| `DEPENDABOT_INVESTIGATE_ALLOW_PROMPT_CHANGES` | `false`            | Set to `true` to let the investigation also adapt a fragment under `prompts/`, but only when it names a specific upstream behavioural change that fragment instructs against or fails to account for — never for a cosmetic or docs-only upstream change. Left at the default, the investigation prompt is hardcoded to leave `prompts/` alone entirely, exactly as before this pipeline was configurable. |
| `DEPENDABOT_AUTOMERGE_ENABLED`                | `true`             | Set to `false` to disable auto-merge outright, at every semver level — investigation and review still run and still comment/leave a formal review, but nothing merges without a human clicking merge.                                                                                                                                                                                                      |
| `DEPENDABOT_AUTOMERGE_LEVELS`                 | `patch,minor`      | Comma-separated, no spaces, any combination of `patch`, `minor`, `major` — which `dependabot/fetch-metadata` update types are eligible for auto-merge once review clears. A level left out of this list still gets fully investigated and reviewed, exactly as a major bump already does by default; it just never auto-merges.                                                                            |

These four are read only inside `metadata`, a job that — like `investigate` — always runs on a Dependabot-triggered event, so per the file header's point (1) they can only ever be read from the separate **Dependabot** secrets store (Settings → Secrets and variables → Dependabot), never the ordinary Actions one: a Dependabot-triggered run has no visibility into the Actions store at all, and there is no Dependabot-scoped _variables_ store to fall back on either (confirmed: the API for one 404s), so these are secrets rather than variables even though none of the four values is actually sensitive. Unlike `CLAUDE_CODE_OAUTH_TOKEN` and `APP_PRIVATE_KEY` below, these four do **not** need duplicating into the ordinary Actions secrets store too — nothing outside this one Dependabot-triggered job ever reads them.

**Setup, once, before the first Dependabot pull request lands:** enable auto-merge on this repository (`allow_auto_merge`, off by default); and add `CLAUDE_CODE_OAUTH_TOKEN` and `EXADEV_SYNC_PRIVATE_KEY` to this repository's **Dependabot** secrets (Settings → Secrets and variables → Dependabot) in addition to wherever they already live for Actions — Dependabot secrets are a separate store, and the only one a Dependabot-triggered run can read. There is no equivalent Dependabot-scoped variables store (confirmed: the API for one 404s), which is why `investigate`'s own token-minting step hardcodes the sync App's numeric App ID rather than reading `vars.EXADEV_APP_ID` the way the `release` job above does — that variable would always resolve empty on a Dependabot-triggered run. Add any of the four `DEPENDABOT_*` secrets above at the same time, to the same Dependabot store, if you want behaviour other than their defaults.

**Adding a working Claude credential to the Dependabot secrets store is safe, deliberately.** A naive version of the `investigate` job's "Investigate and adapt" step would call `anthropics/claude-code-action` directly, pinned to the same SHA `action.yml` pins — meaning a Dependabot bump PR would make that step execute the exact unreviewed SHA it was investigating, with `CLAUDE_CODE_OAUTH_TOKEN` and a `pull-requests: write`-scoped `GITHUB_TOKEN` in scope, before any human reviewed it. This is why it instead runs `@anthropic-ai/claude-code` — Anthropic's own CLI, installed as an ordinary `npm` devDependency by the `actions/setup-node`/`npm ci` steps already in that job, and invoked directly via `npx claude` — instead. That CLI is pinned in `package-lock.json` like any other dependency, tracked by its own `npm` Dependabot ecosystem entry with its own seven-day cooldown, and never bumped by the same pull request that bumps `anthropics/claude-code-action`: the two are on entirely separate registries and release cadences, so investigating a bump of one never means running the unreviewed code of the other.

## Organisation-wide SHA pinning

`action.yml` pins its upstream dependency by commit SHA, and the reusable workflows pin `actions/checkout` the same way, so an upstream tag move cannot silently change what runs here. That protects this repository only.

The organisation's Actions policy does not currently require SHA pinning of anything else, which means any other workflow in this organisation using `some-action@v3` will pick up whatever that tag points at, including a tag repointed after a maintainer account compromise. This is the mechanism behind most real-world Actions supply-chain incidents.

Worth enabling `sha_pinning_required` in the organisation's Actions settings (Settings → Actions → General). Doing so will fail existing workflows that use tags, so it needs a pass over the estate to pin them first rather than being flipped on blind. Raising it now, while there is someone to do that pass, is better than inheriting it later.

## Development

`npm run lint` / `npm run typecheck` / `npm run format:check` are the underlying commands; `turbo.json` wraps each in [Turborepo](https://turborepo.com)'s local task cache (single-package mode — this repository has no workspaces, just one `package.json`), so a rerun with nothing relevant changed completes from cache instead of re-executing `eslint`/`tsc`/`prettier` from scratch. `.github/workflows/ci.yml`'s `typecheck`/`lint`/`format` jobs route through `npx turbo run <task>` for the same reason. Invoke a task directly with `npx turbo run <task>` (or a plain `npm run <task>`, which skips the cache).

`action.yml`'s own `runs.steps` array cannot be linted by `actionlint` directly — that tool only understands workflow files (`on:`/`jobs:`), not a composite action's `inputs:`/`runs:` shape. To validate it anyway, wrap the steps array in a synthetic `workflow_call` reusable workflow whose `on.workflow_call.inputs` mirror `action.yml`'s own `inputs:` (giving `actionlint` a real `inputs.*`/`steps.*` context to resolve against, not just the file's raw YAML), then run `actionlint` against that synthetic file. There's no committed script for this — it's a five-line Python/PyYAML snippet run by hand (or by a reviewing agent) before a change to `action.yml` ships; see the git history of this repository's own review comments for a worked example if you need one.

## Layout

```text
action.yml                     Composite action: input validation, prompt composition, stack
                               detection, session-cache resume, credential fallback, per-mode
                               tool allowlists, pinned upstream call, automatic fixes
turbo.json                     Turborepo task cache config (lint/typecheck/format:check)
commitlint.config.ts           Conventional-commit enforcement (local hook + CI)
release.config.ts              semantic-release config; scripts/move-major-tag.mjs is its
                               local plugin that moves the moving vN tag after each release
lint-staged.config.js          Deliberately .js, not .ts -- see its own header comment
.github/dependabot.yml         Dependabot config: daily npm + github-actions scan, 7-day cooldown
.github/workflows/
  ci.yml                       commitlint, actionlint, typecheck, lint, format, release
  review.yml                   Reusable workflow, contents:read + pull-requests:write
  triage.yml                   Reusable workflow, contents:read + issues:write
  interactive.yml              Reusable workflow, write scopes, trigger-phrase gated
  dependabot.yml               Investigates, reviews, and auto-merges upstream bump PRs
  claude-review.yml            This repository's own dogfooding review trigger
  claude-triage.yml            This repository's own dogfooding triage trigger
  claude-interactive.yml       This repository's own dogfooding @claude trigger
prompts/
  shared/base.md               Applies to every mode
  review/base.md                Review instructions
  review/stacks/*.md           Per-stack review guidance
  triage/base.md               Triage instructions
  interactive/base.md          Interactive instructions
examples/                      Caller workflows to copy into a consuming repository
  direct/                      Direct (composite-action-step) form of the same examples
schemas/                       JSON schema for structured_review_summary's --json-schema
```

Prompt layering order, in full: `prompts/shared/base.md`, then the mode's `base.md`, then any matched stack fragments (review only), then a generated section stating which conventions document exists and how to tag findings, then `.github/claude/shared.md` and `.github/claude/<mode>.md` from the calling repository, then a generated section of facts about the run.
