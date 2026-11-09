# Review ledger

Review mode keeps a ledger of each pull request's review rounds: the head each round reviewed, the patch id of the pull request's diff at that head, every finding with a stable id, its class and its status, and the invariants the change was checked against. A review reads the ledger before anything else and writes it after, so a later round starts from what earlier rounds found instead of from nothing.

## What the ledger holds

The shape is [`schemas/review-ledger.schema.json`](../schemas/review-ledger.schema.json), versioned by its `version` field and by the marker line of the comment that stores it. It is plain JSON data:

- `pullRequest`, `round`, `reviewedHead`, `baseSha`: which pull request, which round, and the head and base commits that round reviewed.
- `patchId`: `git patch-id --stable` of the pull request's diff (`base...head`) at `reviewedHead`, which stays the same across a rebase that leaves the change itself alone; `null` when GitHub would not return the diff, as it refuses for a very large pull request.
- `reviewedFiles`: every path that diff touched, a renamed file under both names.
- `scope`: whether the round reviewed the whole pull request or only what changed since an earlier head, and why.
- `findings`: one entry per instance of a defect class, with its `id`, `classKey`, `instance`, `path`, `severity`, `summary`, `enumerator`, `status` (`open`, `fixed` or `retracted`), `statusReason`, and the first and last round that reported it.
- `invariants`: each property the change was checked against, with its class key, statement, enumerator, where it came from and the round that last checked it.

### Classes, instances and stable ids

A finding is one instance of a class. The class key is a short kebab-case name for a kind of defect (`stale-reference`, `security/sql-injection`); the instance names one place it occurs by its path and the symbol or code it concerns (`docs/setup.md :: npm run old-build`), never by a line number. A finding's id is the first sixteen hex digits of the SHA-256 of the class key, a NUL byte and the instance, so the same instance keeps the same id when lines above it move, and a finding reported again in a later round updates the existing entry instead of adding a second one. An update that names an instance with a leading `path:line` reference is refused.

### Enumerators

Each finding and invariant says how every instance of its class is found:

- `{"type": "grep", "pattern": "...", "paths": ["..."]}`: a mechanical enumerator, `git grep -E` with this pattern over these pathspecs.
- `{"type": "test", "name": "..."}`: a test, named as the repository runs it, that fails while an instance exists.
- `{"type": "lens", "name": "..."}`: a named review lens, for a class that needs judgement.

## Where it is stored, and why

The ledger lives in one comment on the pull request, written by the action's own steps with the job's token. The comment starts with the marker line `<!-- claude-review-ledger:v1 -->`, shows a short summary (the round, the reviewed head, and the open findings counted by class), and holds the ledger itself in a hidden `<!-- claude-review-ledger-data ... -->` block. Each round edits the same comment in place.

The requirement is a record that survives a cache miss and the expiry of job logs and artifacts, using only the scopes review mode already holds. A pull request comment meets all three: it is permanent, it needs only `pull-requests: write`, and the reusable review workflow already grants that. The alternatives fall short on one of them:

- The session cache (`resume_sessions`) is the thing the ledger exists to stop depending on: a cache miss, an evicted entry or a fork pull request leaves it empty.
- A workflow artifact expires with the repository's retention period, the same as the job logs, and finding the previous run's artifact needs `actions: read` and a search across runs.
- A check run on the reviewed commit would tie the record to its head, but creating one needs `checks: write`, which the reusable review workflow does not grant and a caller cannot add through it.
- The review's own body is rewritten when review mode supersedes an earlier review, so a record kept there would be lost on the next round.

A comment body is limited to 65,536 characters. A ledger that would render longer than that fails the run with the largest entries named, rather than being cut.

## How a round uses it

1. **Read the review ledger** (before the prompt is composed) takes the pull request's head, base, changed files and diff from GitHub, computes the patch id, and reads the ledger from the newest bot-authored comment that carries the marker. It checks the ledger against the schema and recomputes every id from its class key and instance. A marker comment whose data block cannot be found or parsed, or a ledger that fails either check, stops the run with an error naming the comment: it was edited into a state this action never wrote. Deleting the comment starts the ledger again; restoring its previous version from the comment's edit history keeps it.
2. The composed prompt gains a "Review ledger" section: the round number, the head the last round reviewed, every finding on record with its id, class, severity, status, instance and summary, and the invariants checked so far.
3. The reviewer ends its run with a `<review-ledger-update>` block of JSON (the `update` definition in the schema) in its final message, never in the review it posts: the findings it reports this round, a status for every open finding on record it does not report again, and the invariants it checked. The write step reads the block from the execution file of the attempt that succeeded (an attempt that failed first, on a usage limit or a rejected credential, is never read), from its final result message, or, when that message has none, from the newest of the run's own messages that has one, such as the body of the review it submitted; the log says which.
4. **Write the review ledger** (after the review) validates the block, merges it into the ledger under the facts the read step took from GitHub, checks the result, and posts the comment or edits it in place. A finding reported again keeps its id and first round; a status change names a finding by id; a new finding gets its id from its class key and instance. The step adds one line to the job's step summary with the round, the reviewed head and the open findings.

A successful review that wrote no valid update block fails the write step and leaves the ledger as it was, so the next round still starts from the last head recorded in full. When no attempt succeeded, the write step fails with an error saying so, and a review a failed attempt posted before failing is not recorded. A run that stopped at its turn limit is not recorded either, because its wrap-up review is partial, and the step says so in a notice.

## Trust

Everything the ledger records about the pull request itself (head, base, patch id, files, round, every id) is set by the action from GitHub's API in the runner. The reviewer's update can report findings, declare invariants and change the status of a finding it names by id, and the schema refuses any update that tries to set anything else. The reviewer has no tool that writes the comment.

Only a comment written by a bot account is read. Anyone who can comment on the pull request can post text that looks like a ledger, but not as a bot. Editing the action's own comment needs write access to the repository, and an edit that changes an instance without its id, or the other way round, fails the id check on the next read.

What the reviewer reports is still the model's judgement over content that may come from the pull request's author: a review subverted by its own pull request can report a finding fixed when it is not. The ledger records that claim; it does not make it true. See [security.md](security.md#security-notes).
