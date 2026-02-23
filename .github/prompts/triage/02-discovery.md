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
