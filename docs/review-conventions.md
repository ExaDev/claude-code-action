# Review conventions and stack detection

How review mode finds and applies a repository's own conventions, how it tags a finding as policy versus stack default, severity labels and emoji ratings, how to add repository-local instructions, and the table of stacks it detects automatically.

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

| Signal in the repository                                                  | Fragment                                                                  |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `build.gradle` or `build.gradle.kts`, plus a ktlint or detekt signal      | [`kotlin.md`](../prompts/review/stacks/kotlin.md)                         |
| `Package.swift`, `*.xcodeproj`, or `*.xcworkspace`, plus `.swiftlint.yml` | [`swift.md`](../prompts/review/stacks/swift.md)                           |
| `composer.json`                                                           | [`php.md`](../prompts/review/stacks/php.md)                               |
| `go.mod`                                                                  | [`go.md`](../prompts/review/stacks/go.md)                                 |
| `package.json` declaring `@sveltejs/kit`                                  | [`sveltekit.md`](../prompts/review/stacks/sveltekit.md)                   |
| `*.tf` files                                                              | [`terraform.md`](../prompts/review/stacks/terraform.md)                   |
| `wrangler.jsonc`, `wrangler.json`, or `wrangler.toml`                     | [`cloudflare-workers.md`](../prompts/review/stacks/cloudflare-workers.md) |
| `tsconfig.json`                                                           | [`typescript.md`](../prompts/review/stacks/typescript.md)                 |
| `pubspec.yaml`                                                            | [`flutter.md`](../prompts/review/stacks/flutter.md)                       |
| `package.json` plus `schema.prisma` or a Prisma dependency                | [`node-prisma.md`](../prompts/review/stacks/node-prisma.md)               |

Detection walks up to four directory levels, so a monorepo's `services/api/go.mod` and `packages/web/package.json` are both found, and it skips `node_modules`, `vendor`, `.terraform`, `Pods`, and the usual build output directories.

**More than one fragment can apply.** A repository with a Go service, a SvelteKit front end, and Terraform infrastructure gets all three, which is the honest answer for a polyglot repository and avoids an arbitrary priority order deciding what a reviewer is told. Gradle and Swift additionally require a lint configuration, so a Java-only Gradle build does not pull in Kotlin guidance.

If nothing matches, review runs on the shared and review base prompts alone. It does not guess at a stack.

To add a stack: write `prompts/review/stacks/<name>.md`, add the detection to the `Detect stack` step in `action.yml`, add a row to the table above, and bump the minor version.
