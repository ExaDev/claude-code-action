#!/usr/bin/env bash
# Fails when action.yml's Headroom defaults differ from the anchor files Dependabot bumps. The action runs headroom_image's default with `docker run` and pip-installs headroom-ai at headroom_version's default, and neither is visible to Dependabot, so each pin has an anchor file Dependabot does read: docker/headroom.Dockerfile, whose FROM image reference must equal headroom_image's default, and python/requirements-headroom.txt, whose headroom-ai version must equal headroom_version's default. A Dependabot pull request bumps only the anchor, so it fails here until the matching default in action.yml is changed in the same pull request.
#
# Usage: bash scripts/headroom-pins.sh [repository root]
#
# Needs bash and awk.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${1:-$(cd "${script_dir}/.." && pwd)}"
action="${root}/action.yml"
dockerfile="${root}/docker/headroom.Dockerfile"
requirements="${root}/python/requirements-headroom.txt"

# The default of an input in action.yml, with its surrounding double quotes removed.
input_default() {
  awk -v input="$1" '
    $0 == "  " input ":" { in_input = 1; next }
    in_input && /^  [^ ]/ { exit }
    in_input && index($0, "    default: ") == 1 {
      value = substr($0, 14)
      if (value ~ /^".*"$/) { value = substr(value, 2, length(value) - 2) }
      print value
      exit
    }
  ' "$action"
}

# The image reference of the Dockerfile's FROM line.
dockerfile_image() {
  awk '$1 == "FROM" { print $2; exit }' "$dockerfile"
}

# The version headroom-ai is pinned to with ==, whatever extras it names.
requirements_version() {
  awk '/^headroom-ai(\[[^]]*\])?==/ { sub(/^[^=]*==/, ""); sub(/[ \t;#].*$/, ""); print; exit }' "$requirements"
}

failed=0

# Reports a pair that differs, or a value that could not be read; an empty value never matches.
compare() {
  local what="$1" anchor_file="$2" anchor="$3" input="$4" default="$5"
  if [ -z "$anchor" ]; then
    echo "::error file=${anchor_file}::Could not read the ${what} from ${anchor_file}."
    failed=1
  elif [ -z "$default" ]; then
    echo "::error file=action.yml::Could not read the default of ${input} from action.yml."
    failed=1
  elif [ "$anchor" != "$default" ]; then
    echo "::error file=action.yml::${input} defaults to '${default}' but ${anchor_file} pins '${anchor}'; change the default to match in the same pull request."
    failed=1
  fi
}

compare "image reference" "docker/headroom.Dockerfile" "$(dockerfile_image)" headroom_image "$(input_default headroom_image)"
compare "headroom-ai version" "python/requirements-headroom.txt" "$(requirements_version)" headroom_version "$(input_default headroom_version)"

if [ "$failed" -eq 0 ]; then
  echo "action.yml's Headroom defaults match docker/headroom.Dockerfile and python/requirements-headroom.txt."
fi
exit "$failed"
