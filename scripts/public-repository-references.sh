#!/usr/bin/env bash
# Fails when a tracked text file names a GitHub repository that is not public, since a public repository naming a private one discloses that the private project exists. It extracts every owner/repo reference (a github.com URL, an owner/repo#N cross-reference, a `uses:` action reference, an api.github.com repos/ path and a bare owner/repo slug in prose), looks each distinct one up once on the GitHub REST API, and reports the file and line of every reference whose repository is private, internal or absent. It never prints the repository it rejects, so a CI log on a public repository cannot repeat the name.
#
# A reference passes only when the API returns the repository with "visibility": "public". A 404 fails, because unauthenticated (or to a token without access) a private repository and an absent one are indistinguishable, and both must go. A token in GITHUB_TOKEN is sent only to raise the rate limit: a token that can read a private repository gets it back with its real visibility, which fails too, so what the token can reach never lets a private repository pass. Unauthenticated, the API allows 60 requests an hour per address; each repository is looked up once per run, and a 403 or 429 stops the run with an error rather than passing what it could not check.
#
# Skipped without a lookup: lockfiles and binary files; a slug that is a run of path components of a tracked file (docs/security.md, prompts/triage/base.md) or that ends in a documentation or configuration file extension (.md, .yml, .toml); a slug whose owner or repository is not a valid GitHub name; a github.com URL whose first path segment is one of GitHub's own routes (github.com/apps/..., github.com/orgs/...), which no account can take; an owner in PUBLIC_ONLY_OWNERS; and a term listed in scripts/public-repository-references.not-repositories.txt.
#
# Usage: bash scripts/public-repository-references.sh [repository root]
#
# Environment: GITHUB_TOKEN (optional, see above); GITHUB_API_URL (defaults to https://api.github.com). Needs bash, git, curl, jq and awk.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-$(cd "${script_dir}/.." && pwd)}"
api="${GITHUB_API_URL:-https://api.github.com}"
not_repositories="${root}/scripts/public-repository-references.not-repositories.txt"

# Owners whose private repositories no contributor to this repository can see, so a reference to one cannot disclose anything: third-party organisations whose public actions and repositories the action documents and uses.
PUBLIC_ONLY_OWNERS="actions anthropics dependabot github"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

pathspecs=(. ':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/pnpm-lock.yaml' ':(exclude,glob)**/yarn.lock' ':(exclude,glob)**/npm-shrinkwrap.json')

# Every match of one pattern as `kind<TAB>file:line<TAB>match`; -I skips binary files.
matches() {
  local kind="$1" pattern="$2"
  git -C "$root" grep -nIoE "$pattern" -- "${pathspecs[@]}" | awk -v kind="$kind" '
    {
      file_end = index($0, ":")
      rest = substr($0, file_end + 1)
      line_end = index(rest, ":")
      printf "%s\t%s:%s\t%s\n", kind, substr($0, 1, file_end - 1), substr(rest, 1, line_end - 1), substr(rest, line_end + 1)
    }
  ' || true
}

{
  matches url '(^|[^.A-Za-z0-9-])github\.com[/:][A-Za-z0-9-]+/[A-Za-z0-9_.-]+'
  matches api '(^|[^A-Za-z0-9_.-])repos/[A-Za-z0-9-]+/[A-Za-z0-9_.-]+'
  matches uses 'uses:[[:space:]]*[A-Za-z0-9-]+/[A-Za-z0-9_.-]+'
  matches ref '[A-Za-z0-9-]+/[A-Za-z0-9_.-]+#[0-9]+'
  matches bare '(^|[^A-Za-z0-9_./@:~$\{-])[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+/?'
} > "${work_dir}/matches"

git -C "$root" ls-files > "${work_dir}/tracked"
if [ -f "$not_repositories" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$not_repositories" > "${work_dir}/not-repositories" || true
else
  : > "${work_dir}/not-repositories"
fi

# One `slug<TAB>file:line` per reference left to look up.
awk -F '\t' -v owners="$PUBLIC_ONLY_OWNERS" -v tracked="${work_dir}/tracked" -v listed="${work_dir}/not-repositories" '
  BEGIN {
    split("about apps collections enterprises features login marketplace notifications orgs pricing security settings site sponsors topics users", routes, " ")
    for (i in routes) { reserved[routes[i]] = 1 }
    split(owners, list, " ")
    for (i in list) { public_only[tolower(list[i])] = 1 }
    while ((getline path < tracked) > 0) {
      count = split(path, parts, "/")
      for (i = 1; i < count; i++) { path_pair[parts[i] "/" parts[i + 1]] = 1 }
    }
    while ((getline term < listed) > 0) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", term)
      not_repository[tolower(term)] = 1
    }
  }
  {
    kind = $1; where = $2; text = $3
    if (kind == "bare" && substr(text, length(text)) == "/") { next }
    if (kind == "url") {
      sub(/^.*github\.com[\/:]/, "", text)
      if (tolower(substr(text, 1, index(text, "/") - 1)) in reserved) { next }
    }
    else if (kind == "api") { sub(/^.*repos\//, "", text) }
    else if (kind == "uses") { sub(/^uses:[[:space:]]*/, "", text) }
    else if (kind == "ref") { sub(/#[0-9]+$/, "", text) }
    else { sub(/^[^A-Za-z0-9]/, "", text) }
    sub(/\.+$/, "", text)
    sub(/\.git$/, "", text)
    slash = index(text, "/")
    owner = substr(text, 1, slash - 1)
    repo = substr(text, slash + 1)
    if (length(owner) > 39 || owner !~ /^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$/) { next }
    if (repo == "" || repo !~ /^[A-Za-z0-9_.-]+$/) { next }
    if (tolower(owner) in public_only) { next }
    if (tolower(text) in not_repository) { next }
    if (kind == "bare" && (text in path_pair)) { next }
    if (kind == "bare" && tolower(repo) ~ /\.(md|markdown|ya?ml|toml|txt|sh|lock)$/) { next }
    printf "%s\t%s\n", text, where
  }
' "${work_dir}/matches" | LC_ALL=C sort -u > "${work_dir}/references"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

failures=0
looked_up=0
# GitHub slugs are case-insensitive, so one lookup covers every spelling.
while IFS= read -r slug; do
  looked_up=$((looked_up + 1))
  body="${work_dir}/body"
  headers="${work_dir}/headers"
  code="$(curl -sS -L -o "$body" -D "$headers" -w '%{http_code}' -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' ${auth[@]+"${auth[@]}"} "${api}/repos/${slug}" || true)"
  case "$code" in
  200)
    visibility="$(jq -r '.visibility // "unknown"' "$body")"
    if [ "$visibility" = "public" ]; then
      continue
    fi
    reason="a repository whose visibility is ${visibility}"
    ;;
  404)
    reason="a repository that is private or does not exist"
    ;;
  403 | 429)
    reset="$(awk -F ': ' 'tolower($1) == "x-ratelimit-reset" { gsub(/\r/, "", $2); print $2 }' "$headers" | tail -n 1)"
    echo "::error::The GitHub API refused a repository lookup with HTTP ${code} (rate limit${reset:+, resetting at epoch ${reset}}); no reference after it was checked, so this check cannot pass. Set GITHUB_TOKEN to raise the limit, or retry after the reset." >&2
    exit 1
    ;;
  *)
    echo "::error::A repository lookup failed with HTTP ${code:-no response}; this check cannot pass without an answer." >&2
    exit 1
    ;;
  esac
  while IFS= read -r where; do
    failures=$((failures + 1))
    file="${where%:*}"
    line="${where##*:}"
    echo "::error file=${file},line=${line}::${where} names ${reason}. A public repository must not name a private one: describe it without its name. If the term is not a repository at all, add it to scripts/public-repository-references.not-repositories.txt."
  done < <(awk -F '\t' -v slug="$slug" 'tolower($1) == tolower(slug) { print $2 }' "${work_dir}/references")
done < <(cut -f 1 "${work_dir}/references" | awk '!seen[tolower($0)]++')

if [ "$failures" -gt 0 ]; then
  echo "${failures} reference(s) to a repository that is not public, from ${looked_up} lookup(s)." >&2
  exit 1
fi
echo "Every repository reference is public (${looked_up} lookup(s))."
