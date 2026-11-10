#!/usr/bin/env bash
# Tests for scripts/headroom-pins.sh. Each case copies action.yml, the reusable workflows and the two Headroom anchor files into a scratch repository root, changes one side the way a Dependabot bump or a hand edit would, and runs the check against it.
#
# Usage: bash scripts/headroom-pins.test.sh
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

check="${repo_root}/scripts/headroom-pins.sh"

# Made-up pins of the anchors' own shapes, never a real release.
bumped_image="ghcr.io/headroomlabs-ai/headroom@sha256:$(printf 'a%.0s' {1..64})"
bumped_version="99.0.0"

# A scratch root holding copies of the three files, named after the case.
fixture_root() {
  local root="${work_dir}/$1"
  mkdir -p "${root}/docker" "${root}/python" "${root}/.github/workflows"
  cp "$action" "${root}/action.yml"
  cp "${repo_root}"/.github/workflows/*.yml "${root}/.github/workflows/"
  cp "${repo_root}/docker/headroom.Dockerfile" "${root}/docker/headroom.Dockerfile"
  cp "${repo_root}/python/requirements-headroom.txt" "${root}/python/requirements-headroom.txt"
  echo "$root"
}

# Replaces the one line matching a pattern in a file, failing the run when no line or several match.
replace_line() {
  local file="$1" pattern="$2" replacement="$3"
  local count
  count="$(grep -c -- "$pattern" "$file" || true)"
  if [ "$count" != "1" ]; then
    echo "expected one line matching '${pattern}' in ${file}, found ${count}" >&2
    exit 1
  fi
  awk -v pattern="$pattern" -v replacement="$replacement" '$0 ~ pattern { print replacement; next } { print }' "$file" > "${file}.new"
  mv "${file}.new" "$file"
}

bump_dockerfile() {
  replace_line "$1/docker/headroom.Dockerfile" "^FROM " "FROM ${bumped_image}"
}

bump_requirements() {
  replace_line "$1/python/requirements-headroom.txt" "^headroom-ai" "headroom-ai[proxy]==${bumped_version}"
}

# Replaces the default of an input declared at the given indent in a file.
set_default_at() {
  local file="$1" indent="$2" input="$3" value="$4"
  awk -v input="$input" -v value="$value" -v indent="$indent" '
    $0 == indent input ":" { in_input = 1; print; next }
    in_input && index($0, indent "  ") != 1 { in_input = 0 }
    in_input && index($0, indent "  default: ") == 1 { print indent "  default: \"" value "\""; in_input = 0; next }
    { print }
  ' "$file" > "${file}.new"
  mv "${file}.new" "$file"
}

# The default of an input in action.yml.
set_default() {
  set_default_at "$1/action.yml" "  " "$2" "$3"
}

# The default of an input in every reusable workflow that declares it, as a complete bump changes them.
set_workflow_defaults() {
  local root="$1" input="$2" value="$3" workflow
  for workflow in "${root}"/.github/workflows/*.yml; do
    if grep -qx "      ${input}:" "$workflow"; then
      set_default_at "$workflow" "      " "$input" "$value"
    fi
  done
}

# The reusable workflows declaring an input, as paths relative to the root.
workflows_declaring() {
  local root="$1" input="$2"
  grep -lx "      ${input}:" "${root}"/.github/workflows/*.yml | sed "s#^${root}/##"
}

# Runs the check against a root and prints its exit status; its output is in $work_dir/stdout.
run_check() {
  local status=0
  bash "$check" "$1" > "${work_dir}/stdout" 2>&1 || status=$?
  echo "$status"
}

expect_equal "this repository's Headroom defaults match its anchors" "0" "$(run_check "$repo_root")"

root="$(fixture_root unchanged)"
expect_equal "unchanged copies pass" "0" "$(run_check "$root")"

root="$(fixture_root docker-bump-alone)"
bump_dockerfile "$root"
expect_equal "a Dockerfile digest bump without the headroom_image default fails" "1" "$(run_check "$root")"
expect_contains "the failure names headroom_image and the new digest" "headroom_image defaults to" "$(cat "${work_dir}/stdout")"
expect_contains "the failure shows the Dockerfile's pin" "$bumped_image" "$(cat "${work_dir}/stdout")"

root="$(fixture_root docker-bump-with-default)"
bump_dockerfile "$root"
set_default "$root" headroom_image "$bumped_image"
expect_equal "a Dockerfile digest bump with only action.yml's headroom_image default fails" "1" "$(run_check "$root")"
for workflow in $(workflows_declaring "$root" headroom_image); do
  expect_contains "the failure names ${workflow}'s stale headroom_image default" "file=${workflow}::headroom_image defaults to" "$(cat "${work_dir}/stdout")"
done
set_workflow_defaults "$root" headroom_image "$bumped_image"
expect_equal "a Dockerfile digest bump with every matching headroom_image default passes" "0" "$(run_check "$root")"

root="$(fixture_root pip-bump-alone)"
bump_requirements "$root"
expect_equal "a requirements bump without the headroom_version default fails" "1" "$(run_check "$root")"
expect_contains "the failure names headroom_version and the new version" "pins '${bumped_version}'" "$(cat "${work_dir}/stdout")"

root="$(fixture_root pip-bump-with-default)"
bump_requirements "$root"
set_default "$root" headroom_version "$bumped_version"
expect_equal "a requirements bump with only action.yml's headroom_version default fails" "1" "$(run_check "$root")"
set_workflow_defaults "$root" headroom_version "$bumped_version"
expect_equal "a requirements bump with every matching headroom_version default passes" "0" "$(run_check "$root")"

root="$(fixture_root one-workflow-stale)"
bump_requirements "$root"
set_default "$root" headroom_version "$bumped_version"
set_workflow_defaults "$root" headroom_version "$bumped_version"
stale="$(workflows_declaring "$root" headroom_version | head -n 1)"
if [ -z "$stale" ]; then
  echo "no reusable workflow declares headroom_version, so the workflow cases test nothing" >&2
  exit 1
fi
set_default_at "${root}/${stale}" "      " headroom_version "0.0.1"
expect_equal "one reusable workflow left on another headroom_version fails" "1" "$(run_check "$root")"
expect_contains "the failure names that workflow" "file=${stale}::headroom_version defaults to '0.0.1'" "$(cat "${work_dir}/stdout")"

root="$(fixture_root default-edited-alone)"
set_default "$root" headroom_version "$bumped_version"
expect_equal "a headroom_version default changed without its anchor fails" "1" "$(run_check "$root")"

root="$(fixture_root no-from-line)"
replace_line "${root}/docker/headroom.Dockerfile" "^FROM " "# no image"
expect_equal "a Dockerfile with no FROM line fails" "1" "$(run_check "$root")"
expect_contains "the failure says the image reference could not be read" "Could not read the image reference" "$(cat "${work_dir}/stdout")"

root="$(fixture_root no-pin)"
replace_line "${root}/python/requirements-headroom.txt" "^headroom-ai" "headroom-ai[proxy]>=${bumped_version}"
expect_equal "a requirements line that is not an exact pin fails" "1" "$(run_check "$root")"
expect_contains "the failure says the version could not be read" "Could not read the headroom-ai version" "$(cat "${work_dir}/stdout")"

finish
