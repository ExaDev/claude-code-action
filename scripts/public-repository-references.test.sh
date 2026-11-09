#!/usr/bin/env bash
# Tests for scripts/public-repository-references.sh. Each case builds a throwaway git repository naming made-up repositories and runs the check against a stub curl that answers from a table, so no test names a real repository or reaches the network.
#
# Usage: bash scripts/public-repository-references.test.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
check="${repo_root}/scripts/public-repository-references.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# The fixture repository's git commands must not act on an outer repository a hook may have exported.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
unset GITHUB_TOKEN

failures=0
passes=0

pass() {
  passes=$((passes + 1))
  echo "ok - $1"
}

fail() {
  failures=$((failures + 1))
  echo "not ok - $1"
}

expect_equal() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    pass "$name"
  else
    fail "$name (expected '${expected}', got '${actual}')"
  fi
}

expect_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$name"
  else
    fail "$name (no '${needle}' in '${haystack}')"
  fi
}

expect_absent() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$name ('${needle}' found in '${haystack}')"
  else
    pass "$name"
  fi
}

# A curl that answers a repository lookup from $STUB_TABLE (lines of `owner/repo code visibility`, matched case-insensitively; anything else is a 404), writes the body and headers where -o and -D ask, and records each URL and whether it carried an Authorization header in $STUB_LOG. STUB_CODE, when set, answers every lookup with that status and a rate-limit reset header.
stub_bin="${work_dir}/stub-bin"
mkdir -p "$stub_bin"
cat > "${stub_bin}/curl" <<'STUB'
#!/usr/bin/env bash
body="" headers="" url="" authorised=no
while [ "$#" -gt 0 ]; do
  case "$1" in
  -o) body="$2"; shift ;;
  -D) headers="$2"; shift ;;
  -H) if [[ "$2" == Authorization:* ]]; then authorised=yes; fi; shift ;;
  -w) shift ;;
  -*) ;;
  *) url="$1" ;;
  esac
  shift
done
slug="${url#*/repos/}"
echo "${slug} ${authorised}" >> "$STUB_LOG"
if [ -n "${STUB_CODE:-}" ]; then
  printf 'HTTP/2 %s\r\nx-ratelimit-remaining: 0\r\nx-ratelimit-reset: 1700000000\r\n\r\n' "$STUB_CODE" > "$headers"
  echo '{"message":"API rate limit exceeded"}' > "$body"
  printf '%s' "$STUB_CODE"
  exit 0
fi
read -r code visibility < <(awk -v slug="$slug" 'tolower($1) == tolower(slug) { print $2, $3; exit }' "$STUB_TABLE")
code="${code:-404}"
printf 'HTTP/2 %s\r\n\r\n' "$code" > "$headers"
if [ "$code" = "200" ]; then
  printf '{"visibility":"%s"}\n' "$visibility" > "$body"
else
  echo '{"message":"Not Found"}' > "$body"
fi
printf '%s' "$code"
STUB
chmod +x "${stub_bin}/curl"

table="${work_dir}/table"
cat > "$table" <<'TABLE'
example-open/tool 200 public
example-open/other 200 public
example-internal/action 200 internal
example-visible/secret 200 private
TABLE

# A fixture repository holding the given files (path, then content, repeated), all tracked.
make_repository() {
  local dir="$1"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  while [ "$#" -gt 0 ]; do
    mkdir -p "$(dirname "${dir}/$1")"
    printf '%s\n' "$2" > "${dir}/$1"
    shift 2
  done
  git -C "$dir" add -A
}

# Runs the check against a fixture repository, leaving its output in $work_dir/output and its log of lookups in $work_dir/log, and prints its exit status.
run_check() {
  local dir="$1"
  shift
  rm -f "${work_dir}/log"
  touch "${work_dir}/log"
  local status=0
  env "$@" PATH="${stub_bin}:${PATH}" STUB_TABLE="$table" STUB_LOG="${work_dir}/log" bash "$check" "$dir" > "${work_dir}/output" 2>&1 || status=$?
  echo "$status"
}

# Public references in every form pass, and each repository is looked up once whatever its spelling.
clean="${work_dir}/clean"
make_repository "$clean" \
  README.md 'See https://github.com/example-open/tool and example-open/tool#4, and Example-Open/Tool, installed from https://github.com/apps/example-app.' \
  docs/setup.md "Calls api.github.com/repos/example-open/other/pulls; also git@github.com:example-open/tool.git." \
  .github/workflows/ci.yml 'uses: example-open/other/.github/workflows/x.yml@v1' \
  docs/paths.md 'Read docs/guides and the notes/plan.md file, and use actions/unlisted-thing.' \
  docs/guides/intro.md 'An introduction.' \
  scripts/public-repository-references.not-repositories.txt $'# Terms that are not repositories\nread/write' \
  docs/prose.md 'Some read/write access.'
printf 'binary\0example-hidden/binary\n' > "${clean}/blob.bin"
printf '{"x": "example-hidden/locked"}\n' > "${clean}/package-lock.json"
git -C "$clean" add -A
status="$(run_check "$clean")"
expect_equal "a repository naming only public repositories passes" "0" "$status"
expect_equal "each distinct repository is looked up once, whatever its case or form" "example-open/other no
example-open/tool no" "$(sort "${work_dir}/log")"
expect_absent "a lockfile is not read" "locked" "$(cat "${work_dir}/log")"
expect_absent "a binary file is not read" "binary" "$(cat "${work_dir}/log")"
expect_absent "an owner whose private repositories no contributor can see is not looked up" "actions/" "$(cat "${work_dir}/log")"
expect_absent "a tracked path is not looked up" "docs/" "$(cat "${work_dir}/log")"
expect_absent "a term listed as not a repository is not looked up" "read/write" "$(cat "${work_dir}/log")"
expect_absent "a URL under one of GitHub's own routes is not looked up" "apps/" "$(cat "${work_dir}/log")"

# A reference to a repository the API does not return fails, naming the file and line but never the repository.
hidden="${work_dir}/hidden"
make_repository "$hidden" \
  README.md 'Public: example-open/tool.' \
  docs/notes.md $'First line.\nConfirmed directly on example-hidden/thing (commit 0123456789).'
status="$(run_check "$hidden")"
output="$(cat "${work_dir}/output")"
expect_equal "a reference to a private or absent repository fails" "1" "$status"
expect_contains "the failure names the file and line" "::error file=docs/notes.md,line=2::" "$output"
expect_contains "the failure says the repository is private or absent" "private or does not exist" "$output"
expect_absent "the failure never prints the repository it rejects" "example-hidden" "$output"

# The same reference in a URL and as a cross-reference fails at each place it appears.
make_repository "$hidden" \
  CHANGELOG.md $'- fix ([abc](https://github.com/example-open/tool/commit/abc)), closes [example-hidden/thing#12](https://github.com/example-hidden/thing/issues/12)'
status="$(run_check "$hidden")"
expect_equal "a private repository in a changelog link fails" "1" "$status"
expect_equal "it is looked up once for both forms on the line" "1" "$(grep -c '^example-hidden/thing ' "${work_dir}/log")"

# A repository the API returns as anything but public fails, so a token that can read a private repository cannot let it pass.
visible="${work_dir}/visible"
make_repository "$visible" \
  action.yml '      uses: example-internal/action@v1' \
  docs/a.md 'See example-visible/secret.'
status="$(run_check "$visible" GITHUB_TOKEN=made-up-token)"
output="$(cat "${work_dir}/output")"
expect_equal "an internal or private repository returned by the API fails" "1" "$status"
expect_contains "an internal repository is reported with its visibility" "::error file=action.yml,line=1::action.yml:1 names a repository whose visibility is internal" "$output"
expect_contains "a private repository is reported with its visibility" "::error file=docs/a.md,line=1::docs/a.md:1 names a repository whose visibility is private" "$output"
expect_equal "a token in GITHUB_TOKEN is sent with every lookup" "yes yes" "$(awk '{ print $2 }' "${work_dir}/log" | tr '\n' ' ' | sed 's/ $//')"

# Without GITHUB_TOKEN the lookups are unauthenticated.
status="$(run_check "$clean")"
expect_equal "without GITHUB_TOKEN no lookup carries a token" "no no" "$(awk '{ print $2 }' "${work_dir}/log" | tr '\n' ' ' | sed 's/ $//')"

# A rate-limited lookup stops the check with an error instead of passing what it could not check.
for code in 403 429; do
  status="$(run_check "$clean" STUB_CODE="$code")"
  output="$(cat "${work_dir}/output")"
  expect_equal "a ${code} from the API fails the check" "1" "$status"
  expect_contains "a ${code} is reported as a rate limit with its reset" "HTTP ${code} (rate limit, resetting at epoch 1700000000)" "$output"
  expect_equal "a ${code} stops further lookups" "1" "$(wc -l < "${work_dir}/log" | tr -d ' ')"
done

# Any other answer, or none, fails rather than passes.
status="$(run_check "$clean" STUB_CODE=502)"
expect_equal "an unexpected status fails the check" "1" "$status"
expect_contains "an unexpected status is reported" "failed with HTTP 502" "$(cat "${work_dir}/output")"

echo "${passes} passed, ${failures} failed"
[ "$failures" -eq 0 ]
