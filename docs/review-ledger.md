# Review ledger

Review mode keeps a ledger of each pull request's review rounds: the head each round reviewed, the patch id of the pull request's diff at that head, every finding with a stable id, its class and its status, and the invariants the change was checked against. A review reads the ledger before anything else and writes it after, so a later round starts from what earlier rounds found instead of from nothing, and is given only what changed since the last reviewed head.

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

- `{"type": "grep", "pattern": "...", "paths": ["..."]}`: a mechanical enumerator, `git grep -E` with this pattern over these pathspecs (the whole tree when the list is empty). The action runs it itself.
- `{"type": "test", "name": "..."}`: a test, named as the repository runs it, that fails while an instance exists. The reviewer checks it; the action does not run the repository's tests.
- `{"type": "lens", "name": "..."}`: a named review lens, for a class that needs judgement. The reviewer checks it.

## Invariants first, then enumerate

Before reviewing, the reviewer works out the invariants the change must hold, from the pull request description, the repository's conventions document and committed configuration, and the stack guidance, and gives each the strongest enumerator it allows. The action does every part of this that a machine can:

- **The repository's own invariants** come from `.github/claude/invariants.json`, read from the pull request's base commit (the tip of the branch it targets, which for a stacked pull request is its parent's branch), never the head, so a pull request cannot change the invariants it is reviewed against; a change to the file takes effect for a pull request once it is on the branch that pull request targets. The file holds `{"invariants": [...]}`, each entry a `classKey`, a one-sentence `statement` and an `enumerator`, as the `repositoryInvariants` definition in the schema says, with each class key listed once. A file that does not match, or that lists a class key twice, stops the run with an error naming the file and the repeated key. For example:

  ```json
  {
    "invariants": [
      {
        "classKey": "no-console-log",
        "statement": "Source code logs through the logger, never console.log.",
        "enumerator": {
          "type": "grep",
          "pattern": "console\\.log",
          "paths": ["src"]
        }
      }
    ]
  }
  ```

- **Before the review**, the action runs the grep enumerator of every invariant on record (the repository's, then those earlier rounds derived) over the head commit's tree and puts every instance it finds in the prompt, so the reviewer judges a class once with its whole instance list. It also checks each open grep-enumerated finding on record and says whether its instance still matches.
- **After the review**, the action runs every grep enumerator again at the reviewed head, the reviewer's new ones included, and records each invariant's instance list. A grep-enumerated finding whose instance no longer matches is marked fixed by the action, and one whose instance still matches stays open, whatever status the reviewer gave it. A finding reported this round whose instance its own enumerator does not find fails the run: the instance must be written as the action keys a match.

An instance of a grep match is keyed as `<path> :: <matched line>`, the line with its leading and trailing whitespace removed; the second and later identical lines in one file get ` #2`, ` #3` and so on, in file order. The key holds no line number, so its id stays the same when lines are added or removed above it. Every instance record also notes the line where it was found that round, for the reader; the line takes no part in any id.

A pattern `git grep` rejects stops the run with the class key and pattern named. The repository's tests are not run by the action: a test enumerator is checked by the reviewer, and running them is the repository's own CI's job.

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
2. The read step decides the round's scope (the delta since the last reviewed head, or the whole pull request and why; see [Delta re-review](#delta-re-review)), reads the repository's invariants from the base commit, runs every grep enumerator on record over the head commit's tree, and checks each open grep-enumerated finding against it. The composed prompt gains a "Review ledger" section: the round number, the head the last round reviewed, every finding on record with its id, class, severity, status, instance, summary and that check, and the invariants to check with every instance found at this head.
3. The reviewer ends its run with a `<review-ledger-update>` block of JSON (the `update` definition in the schema) in its final message, never in the review it posts: the findings it reports this round, a status for every open finding on record it does not report again, and the invariants it checked. The write step reads the block from the execution file of the attempt that succeeded (an attempt that failed first, on a usage limit or a rejected credential, is never read), from its final result message, or, when that message has none, from the newest of the run's own messages that has one, such as the body of the review it submitted; the log says which.
4. **Write the review ledger** (after the review) validates the block, merges it into the ledger under the facts the read step took from GitHub, runs every grep enumerator again at the reviewed head to record the instance lists and settle the status of grep-enumerated findings, checks the result, and posts the comment or edits it in place. A finding reported again keeps its id and first round; a status change names a finding by id; a new finding gets its id from its class key and instance. The step adds one line to the job's step summary with the round, the reviewed head and the open findings.

When GitHub does not return the pull request, its changed files or its comments after the read step's retries, the ledger is unavailable for that round rather than the review failing: the reviewer is told the ledger could not be read and reviews the whole pull request, the round is not recorded, and the step adds a warning and a line to the step summary. Comments that could not be read are never taken to mean there is no ledger comment, since that would start the record again over the one already there. When only the diff is refused, as GitHub does for a very large pull request, the round is recorded with its patch id unknown.

A successful review that wrote no valid update block fails the write step and leaves the ledger as it was, so the next round still starts from the last head recorded in full. When no attempt succeeded, the write step fails with an error saying so, and a review a failed attempt posted before failing is not recorded. A run that stopped at its turn limit is not recorded either, because its wrap-up review is partial, and the step says so in a notice.

## Delta re-review

Once the ledger records a round, a later round is given the delta since the last reviewed head plus the ledger, not the whole pull request, and starts a fresh session instead of resuming the earlier rounds' transcript. Its input is therefore the delta and the ledger, and does not grow with the number of earlier rounds.

- **The delta.** When the last reviewed head is an ancestor of the new head, the read step diffs the two with `git diff`, over the paths either round's pull request diff touched, so a file that only a merge from the base branch brought in is left out. The prompt carries the delta in full, fenced so no line of it can close the fence.
- **The fallback.** When the last reviewed head is not an ancestor of the new head (a force push or rebase) or can no longer be fetched, the round reviews the whole pull request instead. The reason is recorded in the ledger's `scope`, shown in the prompt, written in the ledger comment and the step summary, and the reviewer is told to state it in its review body.
- **No resumed transcript.** With a ledger on record, "Resume prior session" passes no `--resume`; the session is still saved, as `resume_sessions` describes. Without a ledger, as on a pull request's first round, resuming works as before.
- **The budget.** The prompt bounds a delta round: verify every open finding on record once (the action has already checked the grep-enumerated ones), review the delta reading outside it only what a changed line needs, and make one fresh sweep for a class no finding or invariant on record covers. The one escape is a delta that cannot be judged without the rest of the change, such as a sweeping rename: the reviewer then reads the whole diff once and says so in its review body.

## Worked example

The test file `scripts/review-ledger.test.sh` builds this example and checks that every block below matches what the action produces line for line, so the example cannot drift from the code. A pull request renames the `old-build` script to `build` without updating the two documents that name it. The repository's `.github/claude/invariants.json` on the base branch declares one invariant of its own, `no-console-log`.

### Round 1

No ledger exists yet, so the read step gives the reviewer the whole pull request and the repository's invariant with its instances at the head. This section is appended to the review prompt:

<!-- worked-example: round-1-input -->

```text
# Review ledger

This is round 1: no earlier review round of this pull request is on record. Review the whole pull request.

Invariants to check this round, with every instance their enumerator finds at this head (class, where it came from, statement, enumerator, instances):

- `no-console-log` (repository): "Source code logs through the logger, never console.log."; grep `console\.log` in `src`
  - "src/index.js :: console.log(\"ready\");" (src/index.js, line 1)
```

The reviewer derives an invariant from the change (no document names the removed script), finds both instances with its grep enumerator, and ends its run with this update block:

<!-- worked-example: round-1-update -->

```text
{
  "invariants": [
    {
      "classKey": "stale-reference",
      "statement": "No document names the removed old-build script.",
      "enumerator": {
        "type": "grep",
        "pattern": "old-build",
        "paths": [
          "README.md",
          "docs"
        ]
      }
    }
  ],
  "findings": [
    {
      "classKey": "stale-reference",
      "instance": "docs/setup.md :: npm run old-build",
      "path": "docs/setup.md",
      "severity": "Should fix",
      "summary": "Names the old-build script, which this change removes.",
      "enumerator": {
        "type": "grep",
        "pattern": "old-build",
        "paths": [
          "README.md",
          "docs"
        ]
      }
    },
    {
      "classKey": "stale-reference",
      "instance": "README.md :: npm run old-build",
      "path": "README.md",
      "severity": "Should fix",
      "summary": "Names the old-build script, which this change removes.",
      "enumerator": {
        "type": "grep",
        "pattern": "old-build",
        "paths": [
          "README.md",
          "docs"
        ]
      }
    }
  ],
  "statuses": []
}
```

The write step records round 1: the head, both findings with ids made from their class key and instance, and the invariant with the instance list its enumerator finds.

### Round 2

The author pushes a commit that fixes `docs/setup.md`, adds lines above the command in `README.md`, and brings in a `CHANGELOG.md` change from the base branch. The last reviewed head is an ancestor of the new one, so the read step gives the reviewer the delta since it plus the ledger. The `README.md` instance has moved down the file and keeps its id; the `docs/setup.md` instance no longer matches, and the prompt says so; `CHANGELOG.md` is not in the pull request's own diff and is left out of the delta. This is the section appended to the review prompt, and the reviewer is not given the earlier round's transcript:

<!-- worked-example: round-2-input -->

`````text
# Review ledger

This is round 2. The ledger records 1 earlier round(s); the last one reviewed head `86b6931e50e14aacdd46d3583aac955f3157bb96`.

Findings on record (id, class, severity, status, instance, summary):

- `2449c27b65901a25` `stale-reference` Should fix, open: "docs/setup.md :: npm run old-build". "Names the old-build script, which this change removes." Its enumerator no longer matches this instance at this head, so the action records it as fixed: do not report it again, since a grep-enumerated finding whose instance the action cannot find fails the run.
- `3e892ed7cc6e0bdc` `stale-reference` Should fix, open: "README.md :: npm run old-build". "Names the old-build script, which this change removes." Its enumerator still matches this instance at this head.

## What this round reviews

This round reviews the delta since the last reviewed head, `86b6931e50e14aacdd46d3583aac955f3157bb96`: the head moved forward from the last reviewed head, so only the changes since it are reviewed. The delta below is every change since that head to the files the pull request touches, and it is your input in place of the whole diff.

````diff
diff --git a/README.md b/README.md
index 0a1f49d..245769b 100644
--- a/README.md
+++ b/README.md
@@ -1,5 +1,12 @@
 # Example

+Four new lines
+above the command
+move it down
+the file.
+
 Build it:

+```sh
 npm run old-build
+```
diff --git a/docs/setup.md b/docs/setup.md
index e868c4b..8a6ff6a 100644
--- a/docs/setup.md
+++ b/docs/setup.md
@@ -1,3 +1,3 @@
 # Setup

-npm run old-build
+npm run build
````

Invariants to check this round, with every instance their enumerator finds at this head (class, where it came from, statement, enumerator, instances):

- `no-console-log` (repository): "Source code logs through the logger, never console.log."; grep `console\.log` in `src`
  - "src/index.js :: console.log(\"ready\");" (src/index.js, line 1)
- `stale-reference` (review): "No document names the removed old-build script."; grep `old-build` in `README.md`, `docs`
  - "README.md :: npm run old-build" (README.md, line 11)
`````

The reviewer verifies the two findings on record, reviews the delta, makes its one sweep for a new class, and ends with:

<!-- worked-example: round-2-update -->

```text
{
  "invariants": [
    {
      "classKey": "stale-reference",
      "statement": "No document names the removed old-build script.",
      "enumerator": {
        "type": "grep",
        "pattern": "old-build",
        "paths": [
          "README.md",
          "docs"
        ]
      }
    }
  ],
  "findings": [
    {
      "classKey": "stale-reference",
      "instance": "README.md :: npm run old-build",
      "path": "README.md",
      "severity": "Should fix",
      "summary": "Still names the old-build script after the second push.",
      "enumerator": {
        "type": "grep",
        "pattern": "old-build",
        "paths": [
          "README.md",
          "docs"
        ]
      }
    }
  ],
  "statuses": [
    {
      "id": "2449c27b65901a25",
      "status": "fixed",
      "reason": "docs/setup.md now names npm run build."
    }
  ]
}
```

The write step re-runs the enumerators at the new head, keeps the `README.md` finding open under its round 1 id, records the `docs/setup.md` finding as fixed, and edits the ledger comment in place. Its visible part reads:

<!-- worked-example: round-2-comment -->

```text
<!-- claude-review-ledger:v1 -->
**Review ledger**: round 2, reviewed head `2fef4ec7b3ae`, a delta review since `86b6931e50e1` (the head moved forward from the last reviewed head, so only the changes since it are reviewed).

Findings: 1 open, 1 fixed, 0 retracted.

| Class | Open |
| --- | --- |
| `stale-reference` | 1 |

This comment is the record review mode keeps between rounds. Editing it changes what the next review is told.
```

A third push is given only what changed since round 2's head, whatever rounds 1 and 2 covered.

## Every failure path has a test

`scripts/review-ledger.test.sh` ends with a check that reads every annotation (`::error::`, `::warning::`, `::notice::`) the ledger steps in `action.yml` can emit, every `die` in `scripts/review-ledger.sh`, and every jq `error(...)` in that script and in `scripts/json-schema.jq`, and fails unless each one has a row in the test's error-path table naming the test that provokes it, the message appeared in the output the tests provoked, and that test passed. A new failure path without a test, a row whose message no longer exists, and two messages that open with the same text all fail `npm test`, and so CI. Each message therefore opens with literal text rather than a variable, so a row can name it.

## Trust

Everything the ledger records about the pull request itself (head, base, patch id, files, round, every id) is set by the action from GitHub's API in the runner. The reviewer's update can report findings, declare invariants and change the status of a finding it names by id, and the schema refuses any update that tries to set anything else. The reviewer has no tool that writes the comment.

Only a comment written by a bot account is read. Anyone who can comment on the pull request can post text that looks like a ledger, but not as a bot. Editing the action's own comment needs write access to the repository, and an edit that changes an instance without its id, or the other way round, fails the id check on the next read.

What the reviewer reports is still the model's judgement over content that may come from the pull request's author. For a grep-enumerated finding the action settles fixed or open itself, so a review subverted by its own pull request cannot close one whose instance is still there; for a test or lens finding the ledger records the reviewer's claim, and does not make it true. A grep enumerator the reviewer declares runs only `git grep`, which reads the tree and executes nothing from it. See [security.md](security.md#security-notes).
