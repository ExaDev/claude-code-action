#!/usr/bin/env bash
# Shared setup and assertions for the test files under scripts/: a scratch directory removed on exit, pass and fail counters, and helpers that take a step's run: script and its expression-built lines out of action.yml so a test runs exactly what the action runs. Sourced, never run on its own.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${repo_root}/action.yml"
fixtures="${repo_root}/scripts/test-fixtures"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
runner_temp="${work_dir}/runner-temp"

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

# Every line of the step with the given id, from its id line up to the next step.
step_lines() {
  awk -v id="$1" '
    $0 == "      id: " id { in_step = 1; print; next }
    in_step && /^    - / { exit }
    in_step { print }
  ' "$action"
}

# The body of the run: block of the step with the given id, unindented, as the runner would execute it.
step_script() {
  step_lines "$1" | awk '
    $0 == "      run: |" { in_run = 1; next }
    in_run {
      if ($0 != "" && substr($0, 1, 8) != "        ") { exit }
      print substr($0, 9)
    }
  '
}

# The value of a step's own `key: value` line (its condition, or an entry of its with: or env: block).
step_value() {
  step_lines "$1" | awk -v key="$2" '
    index($0, "      " key ": ") == 1 { print substr($0, length(key) + 9); exit }
    index($0, "        " key ": ") == 1 { print substr($0, length(key) + 11); exit }
  '
}

# The value written for a field in a GitHub output file, in either the name=value or the name<<DELIMITER form.
output_value() {
  local file="$1" field="$2"
  awk -v field="$field" '
    delimiter != "" { if ($0 == delimiter) { exit } print; next }
    index($0, field "<<") == 1 { delimiter = substr($0, length(field) + 3); next }
    index($0, field "=") == 1 { print substr($0, length(field) + 2); exit }
  ' "$file"
}

reset_runner_temp() {
  rm -rf "$runner_temp"
  mkdir -p "$runner_temp"
}

# Runs a step's script with the given environment assignments and prints its exit status; its output file is $work_dir/output and its log $work_dir/stdout.
run_step() {
  local id="$1"
  shift
  local script="${work_dir}/${id}.sh"
  step_script "$id" > "$script"
  if [ ! -s "$script" ]; then
    echo "no run: script for step ${id}" >&2
    exit 1
  fi
  : > "${work_dir}/output"
  local status=0
  env -i PATH="$PATH" GITHUB_OUTPUT="${work_dir}/output" ACTION_PATH="$repo_root" RUNNER_TEMP="$runner_temp" "$@" bash "$script" > "${work_dir}/stdout" 2>&1 || status=$?
  echo "$status"
}

# Prints the totals and fails when any assertion failed; the last command of every test file.

finish() {

  echo "${passes} passed, ${failures} failed"

  [ "$failures" -eq 0 ]

}
