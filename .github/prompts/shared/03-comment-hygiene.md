## Step 0 — Clean up before reviewing

**This step is mandatory. Do it FIRST, before reading the diff or writing any
feedback.** Skipping cleanup leaves stale comments and dismissed reviews with
outdated text visible on the PR timeline.

### 0a. List all existing feedback

Your bot identity is `$BOT_NAME`.

List **all** reviews and comments to understand context and avoid duplicating
feedback from others:

```sh
gh api repos/${REPO}/pulls/${PR_NUMBER}/reviews --jq '.[] | {user: .user.login, state, body}'
gh api repos/${REPO}/pulls/${PR_NUMBER}/comments --jq '.[] | {user: .user.login, path, body}'
gh api repos/${REPO}/issues/${PR_NUMBER}/comments --jq '.[] | {user: .user.login, body}'
```

Identify your own previous activity (these are the only items you can modify):

```sh
gh api repos/${REPO}/pulls/${PR_NUMBER}/reviews --jq '.[] | select(.user.login == "$BOT_NAME") | {id, state, body}'
gh api repos/${REPO}/pulls/${PR_NUMBER}/comments --jq '.[] | select(.user.login == "$BOT_NAME") | {id, path, body}'
gh api repos/${REPO}/issues/${PR_NUMBER}/comments --jq '.[] | select(.user.login == "$BOT_NAME") | {id, body}'
```

Do not modify items you did not author.

### 0b. Clean up stale reviews

Only clean up reviews that are **actually stale** — outdated by new commits or
containing feedback that no longer applies. Do not dismiss a review that is still
accurate just to re-submit the same verdict. Dismissing a valid approval only to
re-approve is noise.

Before deciding a previous review is still valid, re-verify any technical
assertions it makes (API existence, correct usage patterns, version compatibility)
using `Read` and `WebFetch`. Your prior review may have been wrong — stale
training data can produce confident but incorrect claims. If a previous review
flagged an API as non-existent or incorrect, confirm that claim against the
actual package or official docs before keeping the review.

For each stale review, run in order. **Do not skip step 1** — a dismissed review
with a non-empty body still displays on the timeline.

```sh
# 1. Clear the body (even if already dismissed):
gh api -X PUT repos/${REPO}/pulls/${PR_NUMBER}/reviews/{REVIEW_ID} -f body=''
# 2. Dismiss if not already dismissed:
gh api -X PUT repos/${REPO}/pulls/${PR_NUMBER}/reviews/{REVIEW_ID}/dismissals -f message='Superseded'
```

### 0c. Update or delete stale inline comments

For inline comments that are **partially stale** (some content still relevant),
update them in place:

```sh
gh api -X PATCH repos/${REPO}/pulls/comments/{COMMENT_ID} -f body='updated text'
```

For inline comments that are **fully stale**, delete them:

```sh
gh api -X DELETE repos/${REPO}/pulls/comments/{COMMENT_ID}
```

### 0d. Update or delete stale top-level comments

Prefer updating a top-level comment over deleting and recreating it — edits
preserve the comment's position in the timeline and avoid notification spam.

```sh
gh api -X PATCH repos/${REPO}/issues/comments/{COMMENT_ID} -f body='updated text'
```

Delete only if the comment is entirely obsolete:

```sh
gh api -X DELETE repos/${REPO}/issues/comments/{COMMENT_ID}
```

### 0e. Resolve addressed review threads

```sh
gh api graphql -f query='query { repository(owner: "${REPO_OWNER}", name: "${REPO_NAME}") { pullRequest(number: ${PR_NUMBER}) { reviewThreads(first: 100) { nodes { id isResolved comments(first: 1) { nodes { body author { login } } } } } } } }'
```

For each unresolved thread whose issue has been fixed:

```sh
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) { thread { isResolved } } }'
```

**Only proceed to reviewing the diff after cleanup is complete.** If your
existing review is still accurate and nothing has changed, do not submit a new
one — there is nothing to add.

## Context awareness

Before commenting, read existing reviews, comments, and threads from all authors
using `gh pr view`, `gh issue view`, and the GitHub API. Use this to:

- Avoid repeating feedback already given by others
- Understand decisions from prior discussion before commenting
- Build on existing threads rather than starting parallel ones

Pay attention to timestamps:

- Compare comment timestamps against commit/push timestamps to determine whether
  feedback has already been addressed
- A force push invalidates old commit SHAs — treat your own pre-force-push
  comments as potentially stale
- Use push event timestamps (not commit author dates) to determine ordering
- On `synchronize`, check whether it was a normal push or force push

## Managing your own feedback

API reference for modifying your own items (never touch others'):

- **Inline comments**: `repos/${REPO}/pulls/comments/{id}` — PATCH to update, DELETE to remove
- **Reviews**: `repos/${REPO}/pulls/${PR_NUMBER}/reviews/{id}` — PUT to update body, PUT `.../dismissals` to dismiss
- **Top-level comments**: `repos/${REPO}/issues/comments/{id}` — PATCH or DELETE

Use reactions instead of noisy reply comments for simple acknowledgments:

- `gh api -X POST repos/${REPO}/pulls/comments/{id}/reactions -f content='+1'`
- Valid values: `+1`, `-1`, `laugh`, `confused`, `heart`, `hooray`, `rocket`, `eyes`

## Signal over noise

- Do not post comments that only praise without substance
- Batch observations into a single review
- The summary comment should add context, not restate inline comments
- If you have nothing meaningful to add, say so briefly and move on
