#!/usr/bin/env bash
# Tests for scripts/headroom-pins.sh. Each case copies action.yml and the two Headroom anchor files into a scratch repository root, changes one side the way a Dependabot bump or a hand edit would, and runs the check against it.
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
  mkdir -p "${root}/docker" "${root}/python"
  cp "$action" "${root}/action.yml"
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

# The default line of an input, which follows its description and required lines.
set_default() {
  local root="$1" input="$2" value="$3"
  awk -v input="$input" -v value="$value" '
    $0 == "  " input ":" { in_input = 1; print; next }
    in_input && /^  [^ ]/ { in_input = 0 }
    in_input && index($0, "    default: ") == 1 { print "    default: \"" value "\""; in_input = 0; next }
    { print }
  ' "${root}/action.yml" > "${root}/action.yml.new"
  mv "${root}/action.yml.new" "${root}/action.yml"
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
expect_equal "a Dockerfile digest bump with the matching headroom_image default passes" "0" "$(run_check "$root")"

root="$(fixture_root pip-bump-alone)"
bump_requirements "$root"
expect_equal "a requirements bump without the headroom_version default fails" "1" "$(run_check "$root")"
expect_contains "the failure names headroom_version and the new version" "pins '${bumped_version}'" "$(cat "${work_dir}/stdout")"

root="$(fixture_root pip-bump-with-default)"
bump_requirements "$root"
set_default "$root" headroom_version "$bumped_version"
expect_equal "a requirements bump with the matching headroom_version default passes" "0" "$(run_check "$root")"

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
