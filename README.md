# Claude Code Action

Runs Claude Code in GitHub Actions, for four jobs:

| Mode            | What it does                                                                                                                                                                | When it runs                                                                                                  |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **review**      | Reviews a pull request and submits a formal review — inline comments plus a summary body, requesting changes on any real finding and approving when only minor nits remain. | A pull request is opened, pushed to, reopened, or marked ready for review.                                    |
| **triage**      | Classifies a new issue (native issue type, labels, sub-issue/blocker relationships), hunts for duplicates, and says what information is missing.                            | An issue is opened, or re-labelled for re-triage.                                                             |
| **interactive** | Answers a question, or makes a change on a branch and opens a pull request for it.                                                                                          | Someone with write access mentions `@claude` in a comment or review.                                          |
| **generic**     | Runs a caller-supplied prompt file verbatim, with no tools and no GitHub posting, and returns plain text or (with `--json-schema`) validated JSON.                          | Never on its own — called imperatively from inside a job you already have, not dispatched off a GitHub event. |

## Why this exists rather than per-repository workflows

This wraps Anthropic's own [`anthropics/claude-code-action`](https://github.com/anthropics/claude-code-action) (MIT licensed). A consuming repository gets a short workflow file; this repository holds the prompts, the tool allowlists, the per-mode permission scoping, and the pinned upstream version, so improving how review works everywhere is a change made here, not in every consumer.

The prompts assume an inherited, sparsely documented repository rather than a greenfield one, and review mode distinguishes a finding grounded in the project's own documented policy from one grounded in a general convention for the stack; see [Documented policy versus stack default](docs/review-conventions.md#documented-policy-versus-stack-default). Full background and the copy-paste prompt for handing setup to an agent: [docs/adopting.md](docs/adopting.md).

## Adopting it in a repository

**1. Make a Claude credential available.** Set one of these as an organisation secret (Settings → Secrets and variables → Actions), so every repository inherits it, or as a repository secret for a single repository:

- `ANTHROPIC_API_KEY` — an Anthropic API key.
- `CLAUDE_CODE_OAUTH_TOKEN` — a Claude Code OAuth token, if the organisation bills through a Claude subscription rather than API credit.

Either works; the run fails with an explicit error if neither is present. A second credential of either kind can be added later as a fallback; see [Credential fallback](docs/credentials.md#credential-fallback).

**2. Copy the workflows you want** from [`examples/`](examples/) into the repository's own `.github/workflows/`:

| Copy this                                                            | To                                         | Gives you             |
| -------------------------------------------------------------------- | ------------------------------------------ | --------------------- |
| [`examples/claude-review.yml`](examples/claude-review.yml)           | `.github/workflows/claude-review.yml`      | Pull request review   |
| [`examples/claude-triage.yml`](examples/claude-triage.yml)           | `.github/workflows/claude-triage.yml`      | Issue triage          |
| [`examples/claude-interactive.yml`](examples/claude-interactive.yml) | `.github/workflows/claude-interactive.yml` | `@claude` in comments |

They are independent: take one, two, or all three, and add your own `on:`/`paths:`/`branches:` filters to the caller. [`examples/direct/`](examples/direct/) holds a direct, composite-action-step form of the same three modes, needed for OIDC-based auth or for review running as the Claude Code GitHub App rather than `github-actions[bot]`; `generic` mode only exists in this direct form. Full detail on both forms is in [docs/adopting.md](docs/adopting.md).

**3. Add a `permissions:` block to the caller job if the repository's own default workflow permissions fall short of what the mode needs.** A job with no `permissions:` block of its own inherits the repository's default `GITHUB_TOKEN` scope, and a reusable workflow's own requested permissions can only be downgraded from that, never elevated; if the default falls short, the run fails at startup with no useful diagnostic, and `actionlint` will not catch it. Check Settings → Actions → General → Workflow permissions against [Modes at a glance](#modes-at-a-glance), and add a matching `permissions:` block to the caller job if needed. Full mechanism, including why a caller-side grant cannot reach `id-token: write` through a reusable workflow: [docs/adopting.md](docs/adopting.md).

**4. That is it.** There is nothing else to install and no bot to add. Runs authenticate as the repository's own `GITHUB_TOKEN`, so comments appear from `github-actions[bot]`.

## Modes at a glance

| Mode        | Token scopes                                               | What it can touch                                                                                                                                                                             |
| ----------- | ---------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| review      | `contents: read`, `pull-requests: write`, `actions: read`  | Submits a formal review (inline comments plus a summary); no file writes or commits unless an opt-in automatic-fix input is on, and never on a fork pull request.                             |
| triage      | `contents: read`, `issues: write`                          | Labels, comments on, and edits the triggering issue; no pull-request scope at all.                                                                                                            |
| interactive | `contents: write`, `pull-requests: write`, `issues: write` | Edits files, commits to a new branch, pushes, opens a pull request, comments. Merging, closing, releases, secrets, and workflow edits are blocked by denylist and prompt, not by token scope. |
| generic     | Whatever the calling job's own token already has           | Runs `prompt_file` verbatim, with no tools and no GitHub posting.                                                                                                                             |

Each mode also carries a `--allowedTools`/`--disallowedTools` list passed to Claude Code, so the deny list, not just the token scope, keeps a mode from doing more than the table says. Full scopes, the tool-allowlist mechanics, and every opt-in input that widens a mode (automatic fixes, issue escalation, review states) are in [docs/modes-and-permissions.md](docs/modes-and-permissions.md).

## Security

Untrusted text (issue bodies, comments, pull request descriptions, and the contents of a pull request's own files) reaches the model on a public repository or one accepting fork pull requests. The prompt treats it as data, not instructions, but that is mitigation, not a guarantee; the token scopes and tool allowlists in [Modes at a glance](#modes-at-a-glance) are the real control, so check the blast radius they allow rather than trusting the prompt alone.

Hard rules when changing this repository:

- **Only users with repository write access can trigger a run by default.** Widening that (`allowed_non_write_users`) is safe for triage, which holds no code-write scope, and unsafe for interactive, which can commit and push.
- **A fork pull request's `GITHUB_TOKEN` is read-only by GitHub's own platform rule**, regardless of `permissions:`. Reviewing a fork pull request through the reusable workflow silently fails to post; the direct review example authenticates as the Claude Code GitHub App instead so it can post.
- **Interactive mode's `Bash` grant is unscoped**, not an enumerated `Bash(<cmd>:*)` list, because the SDK's permission model requires every operation in a compound command to match an allow rule individually. The deny list in `action.yml` is defence in depth against an accidental invocation, not the security boundary; the actual boundary is the token's capped scope, branch protection on the default branch, and the write-access gate above.
- **Branch protection on the default branch is what stops interactive mode rewriting history**, not the prompt, which only forbids it.
- **Headroom (see [docs/headroom.md](docs/headroom.md)) is a third-party dependency that sees every diff, log, issue body, and file read** before this action does. Set `headroom_enabled: false` if that trust addition is not wanted.

Full detail, including the self-modifying-workflow trap and exactly what each review-widening input (`fix_pr_metadata`, `resolve_stale_threads`, `verify_prior_findings`, `fix_ci_failures`, and the rest) exposes, is in [docs/security.md](docs/security.md).

## Review conventions and stack detection

Review mode looks for `CLAUDE.md`, then `AGENTS.md`, then `README.md` at the repository root, treats the first one found as authoritative, and tags every substantive finding `[policy]` (grounded in that document or a committed lint/formatter config) or `[stack-default]` (grounded in general convention for the stack alone). It also detects the stack automatically from files present (a `go.mod`, a `tsconfig.json`, `*.tf` files, and so on) and layers in matching guidance. Extend the prompts for one repository with `.github/claude/shared.md` and `.github/claude/<mode>.md`, without forking anything.

Full detection table, severity labels, and the repository-local instruction files: [docs/review-conventions.md](docs/review-conventions.md).

## Versioning

Releases are automated by [`semantic-release`](https://semantic-release.gitbook.io/), triggered on every push to `main` that passes CI, and the moving `v1` tag is what consuming repositories reference. The upstream `anthropics/claude-code-action` dependency is pinned by commit SHA in `action.yml`, not by a tag, so an upstream tag move cannot change behaviour here without a commit in this repository.

**The commit type you use is the release decision — get it right.** `commitlint.config.ts` and `release.config.ts` share one list (`commitTypes` in `release.config.ts`) mapping each conventional-commit type to a release level:

- **`feat:` → minor.** Use this for anything that changes what Claude is actually told, not just new capabilities in the traditional sense — a reworded review instruction, a new stack fragment, a new input, a new mode. A reworded prompt changes what every repository in the organisation gets told; that is not a patch even though no application code moved.
- **`fix:`, `docs:`, `refactor:`, `perf:`, `test:`, `build:`, `ci:`, `chore:`, `revert:` → patch.** A bug fix, a documentation correction, a security-motivated bump of the pinned upstream SHA — anything with no intended change in what Claude is told.
- **A commit footer of `BREAKING CHANGE:` → major.**

Never bundle a prompt change into a commit whose type says "no behavioural change" (e.g. `fix:` for a security-motivated SHA bump). Someone applying that release needs to be able to take it without also getting a change in review behaviour across the estate — split them into separate commits if both are needed in the same PR.

Automated Dependabot bumps of the pinned upstream SHA, the moving-`v1`-tag mechanics, and the organisation's wider SHA-pinning stance are in [docs/release-pipeline.md](docs/release-pipeline.md).

## Development

`npm run lint` / `npm run typecheck` / `npm run format:check` are the underlying commands; `turbo.json` wraps each in [Turborepo](https://turborepo.com)'s local task cache (single-package mode — this repository has no workspaces, just one `package.json`), so a rerun with nothing relevant changed completes from cache instead of re-executing `eslint`/`tsc`/`prettier` from scratch. `.github/workflows/ci.yml`'s `typecheck`/`lint`/`format` jobs route through `npx turbo run <task>` for the same reason. Invoke a task directly with `npx turbo run <task>` (or a plain `npm run <task>`, which skips the cache).

`action.yml`'s own `runs.steps` array cannot be linted by `actionlint` directly — that tool only understands workflow files (`on:`/`jobs:`), not a composite action's `inputs:`/`runs:` shape. To validate it anyway, wrap the steps array in a synthetic `workflow_call` reusable workflow whose `on.workflow_call.inputs` mirror `action.yml`'s own `inputs:` (giving `actionlint` a real `inputs.*`/`steps.*` context to resolve against, not just the file's raw YAML), then run `actionlint` against that synthetic file. There's no committed script for this — it's a five-line Python/PyYAML snippet run by hand (or by a reviewing agent) before a change to `action.yml` ships; see the git history of this repository's own review comments for a worked example if you need one.

## Layout

```text
action.yml                     Composite action: input validation, prompt composition, stack
                               detection, session-cache resume, credential fallback with
                               rate-limit retry, per-mode tool allowlists, pinned upstream
                               call, automatic fixes
turbo.json                     Turborepo task cache config (lint/typecheck/format:check)
scripts/execution-result.sh    Extracts the final result message from an upstream execution file; used
                               by the rate-limit retry gates and the failed-attempt diagnosis
commitlint.config.ts           Conventional-commit enforcement (local hook + CI)
release.config.ts              semantic-release config; scripts/move-major-tag.mts is its
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

`mode: generic` skips all of the above: its `prompt_file` input becomes the entire prompt, verbatim — see [`prompt_file`](docs/calling-and-options.md#extended-options) on `action.yml`.

## References

- [docs/adopting.md](docs/adopting.md): why this action exists, full adoption steps for both the reusable-workflow and direct forms, and the copy-paste prompt for handing setup to an agent.
- [docs/credentials.md](docs/credentials.md): the multi-credential fallback chain, retrying a genuine rate limit against the same credential, and diagnosing why a run failed.
- [docs/headroom.md](docs/headroom.md): the optional context-compression proxy, its install methods, and where its savings are reported.
- [docs/modes-and-permissions.md](docs/modes-and-permissions.md): full token scopes and tool allowlists per mode, review states, automatic fixes, and escalating blocked findings to issues.
- [docs/security.md](docs/security.md): the full security model behind the Security section above.
- [docs/review-conventions.md](docs/review-conventions.md): policy-versus-stack-default tagging, severity labels, repository-local instructions, and the stack-detection table.
- [docs/calling-and-options.md](docs/calling-and-options.md): calling the composite action directly, every extended input, and triage's native-metadata behaviour.
- [docs/release-pipeline.md](docs/release-pipeline.md): the automated Dependabot upstream-bump pipeline and the organisation's SHA-pinning stance.
