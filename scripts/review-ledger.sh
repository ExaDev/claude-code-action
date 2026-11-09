#!/usr/bin/env bash
# Reads, checks, updates and renders review mode's ledger: the record of a pull request's earlier review rounds that the action keeps in a comment on the pull request. Its shape is schemas/review-ledger.schema.json, and docs/review-ledger.md describes how review mode uses it.
#
# Usage, one subcommand per line:
# - `review-ledger.sh id <class-key> <instance>` prints the stable id of one instance of a class.
# - `review-ledger.sh patch-id < diff` prints git patch-id --stable of a diff, or nothing for an empty diff.
# - `review-ledger.sh extract < comments` reads a JSON array of issue comments and prints {"commentId": <id>, "ledger": <ledger>} for the newest comment written by a bot that carries the ledger marker, or nothing when there is none; a marker comment whose data block is missing or not JSON is an error.
# - `review-ledger.sh validate <definition> <file>` exits non-zero, naming every violation on stderr, unless the file matches the schema definition named (`ledger` for the ledger itself, or a name under $defs such as `repositoryInvariants`).
# - `review-ledger.sh check <ledger-file>` exits non-zero, naming every problem on stderr, unless the file is a valid ledger whose ids are the ones its class keys and instances produce.
# - `review-ledger.sh update-block <execution-file>` prints the JSON between the last <review-ledger-update> and </review-ledger-update> tags of a run's final result message, or, when that message has none, of the newest of the run's own assistant messages (text or tool call input) that has one, naming on stderr which it read; prints nothing when the run wrote no block.
# - `review-ledger.sh apply <update-file> <facts-file> [<previous-ledger-file>]` prints the ledger after this round: the previous ledger (if any) with the reviewer's update merged in and the runner's facts (pullRequest, reviewedHead, baseSha, patchId, reviewedFiles, scope) set.
# - `review-ledger.sh scope <head> <reviewed-files-file> <previous-ledger-file> <delta-file>` decides what a re-review is given, prints the scope as JSON and writes the delta diff to <delta-file>: the diff from the previous reviewed head to <head> over the paths either round's diff touched, when the previous head is an ancestor of <head>, and otherwise the whole pull request with the reason (a force push or rebase moved the branch past it, or it is no longer fetchable), leaving <delta-file> empty. Runs in the repository holding the commits.
# - `review-ledger.sh prepare <commit> <facts-file> [<previous-ledger-file>]` prints what a round starts from, for `context`: its round number, the previous reviewed head, the invariants to check with every instance their grep enumerators find at the commit, and the findings on record, each open grep-enumerated one marked with whether its instance still matches. Runs in the repository holding the commit.
# - `review-ledger.sh context <prepared-file> [<delta-file>]` prints the "Review ledger" section of the review prompt from what `prepare` printed, with the delta diff embedded when the scope is a delta.
# - `review-ledger.sh enumerate-ledger <commit> <ledger-file>` prints the ledger with every invariant's instances found at the commit, every open grep-enumerated finding whose instance no longer matches marked fixed, and every one marked fixed whose instance still matches reopened. A finding reported this round whose instance its own grep enumerator does not find is an error. Runs in the repository holding the commit.
# - `review-ledger.sh render <ledger-file>` prints the comment body that stores the ledger.
#
# A command that finds invalid input prints why on stderr and exits 1; nothing is skipped silently.
set -euo pipefail
# A failure inside $(...) stops the script too, so an enumerator error deep in a pipeline is never read as an empty result.
shopt -s inherit_errexit

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
schema="${script_dir}/../schemas/review-ledger.schema.json"

# The first line of the comment that stores the ledger. Reading looks for it; the version in it is the schema's.
readonly COMMENT_MARKER='<!-- claude-review-ledger:v1 -->'
readonly DATA_OPEN='<!-- claude-review-ledger-data'
readonly DATA_CLOSE='-->'
# GitHub rejects an issue comment body longer than this many characters; the API's validation error states the limit ("Body is too long (maximum is 65536 characters)").
readonly COMMENT_BODY_LIMIT=65536
# Hex digits of SHA-256 kept in an id: 64 bits, so two distinct instances on one pull request collide with odds far below one in a billion even at tens of thousands of findings (birthday bound 2^32), while an id stays short enough to quote in a prompt.
readonly ID_HEX_DIGITS=16

die() {
  echo "review-ledger: $*" >&2
  exit 1
}

# The id of one instance: SHA-256 of the class key, a NUL byte and the instance, so no class key and instance pair can be confused with another by concatenation. Takes a JSON object with classKey and the field named by $2 on stdin.
id_of() {
  local field="$1"
  jq -j --arg field "$field" '.classKey + "\u0000" + .[$field]' | openssl dgst -sha256 -r | cut -c "1-${ID_HEX_DIGITS}"
}

# Reads a JSON array of objects on stdin and prints it with an "id" computed from each one's classKey and the named field.
with_ids() {
  local field="$1" items count index id
  items="$(cat)"
  count="$(jq 'length' <<< "$items")"
  local ids=()
  for ((index = 0; index < count; index++)); do
    id="$(jq -c --argjson index "$index" '.[$index]' <<< "$items" | id_of "$field")"
    ids+=("$id")
  done
  jq -c --args '[., $ARGS.positional] | transpose | map(.[0] + {id: .[1]})' "${ids[@]}" <<< "$items"
}

# Prints every violation of the schema definition named $1 ("ledger" for the root) by the JSON file $2.
schema_errors() {
  local definition="$1" file="$2"
  jq -r -L "$script_dir" --slurpfile root "$schema" --arg definition "$definition" '
    include "json-schema";
    schema_errors($root[0]; (if $definition == "ledger" then $root[0] else $root[0]["$defs"][$definition] end); "$")
  ' "$file"
}

validate() {
  local definition="$1" file="$2" errors
  jq -e . "$file" > /dev/null 2>&1 || die "not valid JSON: ${file}"
  errors="$(schema_errors "$definition" "$file")"
  [ -z "$errors" ] || die "not a valid ${definition}: ${file}"$'\n'"${errors}"
  if [ "$definition" = "repositoryInvariants" ]; then
    jq -c '.invariants' "$file" | refuse_duplicate_classes "$file"
  fi
}

# Reads a JSON array of repository invariants on stdin and stops, naming every class key listed more than once, unless each class key appears once. A repeated key is a configuration error: two entries may state different properties or enumerators, and choosing one would silently drop the other. JSON Schema cannot express uniqueness by one field, so it is checked here.
refuse_duplicate_classes() {
  local where="$1" duplicates
  duplicates="$(jq -r '[group_by(.classKey)[] | select(length > 1) | .[0].classKey] | join(", ")')"
  [ -z "$duplicates" ] || die "the repository invariants list a class key more than once (${duplicates}) in ${where}; give each class one entry"
}

# Prints, as a JSON array of instance records (id, key, path, line), every match of a grep enumerator in the tree of a commit. Takes the class key, the enumerator JSON and the commit; runs in the repository holding the commit. An instance's key is its path and its matched line with surrounding whitespace trimmed, with " #2", " #3" and so on appended to the second and later identical lines in one file, so a key, and the id made from it, stays the same when lines are added or removed around it. A pattern or pathspec git grep rejects stops with its error.
grep_instances() {
  local class_key="$1" enumerator="$2" commit="$3" pattern matches status=0
  pattern="$(jq -r '.pattern' <<< "$enumerator")"
  local paths=()
  while IFS= read -r -d '' path; do
    paths+=("$path")
  done < <(jq -j '.paths[] | (., "\u0000")' <<< "$enumerator")
  matches="$(mktemp)"
  # -z separates the path, line number and text with NUL bytes, so a path holding ":" parses correctly; NUL bytes cannot pass through a shell variable, hence the file.
  git grep -n -I -E -z -e "$pattern" "$commit" -- ${paths[@]+"${paths[@]}"} > "$matches" || status=$?
  # git grep exits 1 when nothing matches, which is an empty list of instances; anything higher is an error.
  if [ "$status" -gt 1 ]; then
    rm -f "$matches"
    die "the grep enumerator of ${class_key} (pattern ${pattern}) failed: git grep exited ${status}"
  fi
  jq -R -s -c --arg prefix "${commit}:" --arg classKey "$class_key" '
    split("\n")
    | map(select(. != "") | split("\u0000") | {path: (.[0] | ltrimstr($prefix)), line: (.[1] | tonumber), text: (.[2:] | join("\u0000") | gsub("^\\s+|\\s+$"; ""))})
    | sort_by(.path, .line)
    | reduce .[] as $match ({seen: {}, instances: []};
        "\($match.path) :: \($match.text)" as $base
        | (.seen[$base] // 0) as $earlier
        | .seen[$base] = $earlier + 1
        | .instances += [{classKey: $classKey, key: (if $earlier == 0 then $base else "\($base) #\($earlier + 1)" end), path: $match.path, line: $match.line}])
    | .instances
  ' "$matches" | with_ids key | jq -c 'map({id, key, path, line})'
  rm -f "$matches"
}

# Reads a JSON array of invariants on stdin and prints it with each one's instances in the tree of the commit $1: a grep enumerator's matches, and none for a test or lens enumerator, which the action cannot run.
enumerate_invariants() {
  local commit="$1" invariants count index invariant found
  invariants="$(cat)"
  count="$(jq 'length' <<< "$invariants")"
  local results=()
  for ((index = 0; index < count; index++)); do
    invariant="$(jq -c --argjson index "$index" '.[$index]' <<< "$invariants")"
    if [ "$(jq -r '.enumerator.type' <<< "$invariant")" = "grep" ]; then
      found="$(grep_instances "$(jq -r '.classKey' <<< "$invariant")" "$(jq -c '.enumerator' <<< "$invariant")" "$commit")"
      results+=("$found")
    else
      results+=("[]")
    fi
  done
  jq -c --args '[., ($ARGS.positional | map(fromjson))] | transpose | map(.[0] + {instances: .[1]})' ${results[@]+"${results[@]}"} <<< "$invariants"
}

# Reads a JSON array of findings on stdin and prints an object mapping the id of each finding with a grep enumerator to whether its instance is still among the enumerator's matches in the tree of the commit $1. Findings with a test or lens enumerator are left out: only the reviewer can check those.
grep_finding_matches() {
  local commit="$1" findings count index finding instances
  findings="$(cat)"
  count="$(jq 'length' <<< "$findings")"
  local pairs=()
  for ((index = 0; index < count; index++)); do
    finding="$(jq -c --argjson index "$index" '.[$index]' <<< "$findings")"
    [ "$(jq -r '.enumerator.type' <<< "$finding")" = "grep" ] || continue
    instances="$(grep_instances "$(jq -r '.classKey' <<< "$finding")" "$(jq -c '.enumerator' <<< "$finding")" "$commit")"
    pairs+=("$(jq -c -n --argjson finding "$finding" --argjson instances "$instances" '{key: $finding.id, value: ([$instances[].key] | index($finding.instance) != null)}')")
  done
  jq -c -n --args '$ARGS.positional | map(fromjson) | from_entries' ${pairs[@]+"${pairs[@]}"}
}

command="${1:-}"
shift || true

case "$command" in
  id)
    [ "$#" -eq 2 ] || die "usage: review-ledger.sh id <class-key> <instance>"
    jq -n -c --arg classKey "$1" --arg instance "$2" '{classKey: $classKey, instance: $instance}' | id_of instance
    ;;

  patch-id)
    # Run from the root directory so the command never depends on, or reads, a repository around it: patch-id needs only the diff text.
    (cd / && git patch-id --stable) | cut -d ' ' -f 1
    ;;

  extract)
    jq -c --arg marker "$COMMENT_MARKER" --arg open "$DATA_OPEN" --arg close "$DATA_CLOSE" '
      [.[] | select(.user.type == "Bot" and ((.body // "") | startswith($marker)))]
      | sort_by(.updated_at, .id) | last
      | select(. != null)
      # A comment that carries the marker is the ledger, so a data block that cannot be found or parsed is an error, never "no ledger": reading it as absent would start the record again and drop every finding on it.
      | .id as $id
      | ([.body | capture("(?s)" + $open + "\n(?<data>.*?)\n" + $close)] | first // error("no readable data block in the ledger comment \($id), which carries the marker"))
      | {commentId: $id, ledger: (.data | try fromjson catch error("the data block of the ledger comment \($id) is not valid JSON"))}
    ' || die "the ledger comment could not be read (see the message above)"
    ;;

  validate)
    [ "$#" -eq 2 ] || die "usage: review-ledger.sh validate <definition> <file>"
    [ "$1" = "ledger" ] || jq -e --arg definition "$1" '."$defs" | has($definition)' "$schema" > /dev/null || die "no schema definition named ${1}; use ledger or a name under \$defs in ${schema}"
    validate "$1" "$2"
    ;;

  check)
    [ "$#" -eq 1 ] || die "usage: review-ledger.sh check <ledger-file>"
    file="$1"
    validate ledger "$file"
    problems=""
    expected="$(jq -c '.findings' "$file" | with_ids instance)"
    problems+="$(jq -r --argjson expected "$expected" '
      [.findings, $expected] | transpose[]
      | select(.[0].id != .[1].id)
      | "finding \(.[0].id) does not match its class key and instance (expected \(.[1].id))"
    ' "$file")"
    problems+="$(jq -r '.findings | group_by(.id)[] | select(length > 1) | "finding id \(.[0].id) appears \(length) times"' "$file")"
    for index in $(jq -r '.invariants | keys[]' "$file"); do
      class_key="$(jq -r --argjson index "$index" '.invariants[$index].classKey' "$file")"
      expected="$(jq -c --argjson index "$index" '[.invariants[$index].instances[] | {classKey: $classKey, key}]' --arg classKey "$class_key" "$file" | with_ids key)"
      problems+="$(jq -r --argjson index "$index" --argjson expected "$expected" '
        [.invariants[$index].instances, $expected] | transpose[]
        | select(.[0].id != .[1].id)
        | "instance \(.[0].id) of \(.[1].classKey) does not match its key (expected \(.[1].id))"
      ' "$file")"
    done
    [ -z "$problems" ] || die "ids that do not match what they identify, so the ledger was not written by this action as it stands: ${file}"$'\n'"${problems}"
    ;;

  update-block)
    [ "$#" -eq 1 ] || die "usage: review-ledger.sh update-block <execution-file>"
    execution_file="$1"
    [ -f "$execution_file" ] || exit 0
    # The final result message is where the prompt asks for the block. A reviewer that put it somewhere else in the same run, such as the end of the review body it submitted, still wrote it in one of its own messages, so the run's assistant messages are searched next, newest first: their text and every string in their tool calls' input. Only the model's own messages are searched, never the prompt or a tool result, so the example block in the instructions and text read back from GitHub can never be taken for it.
    found="$(jq -c '
      def blocks: [match("(?s)<review-ledger-update>(.*?)</review-ledger-update>"; "g") | .captures[0].string];
      def strings_in: if type == "string" then . elif type == "array" or type == "object" then .[] | strings_in else empty end;
      if type != "array" then empty else
        ([.[] | select(type == "object" and .type == "result")] | last | (.result // "") | blocks | last) as $final
        | if $final != null then {source: "the final result message", block: $final}
          else
            [ .[] | select(type == "object" and .type == "assistant") | .message.content // [] | .[]
              | if .type == "text" then .text elif .type == "tool_use" then (.input | strings_in) else empty end
              | blocks[] ]
            | last
            | select(. != null)
            | {source: "an earlier message of the run, not its final result message", block: .}
          end
      end
    ' "$execution_file")"
    [ -n "$found" ] || exit 0
    echo "review-ledger: read the update block from $(jq -r '.source' <<< "$found")." >&2
    jq -r '
      .block
      | gsub("^\\s+|\\s+$"; "")
      | sub("^```(?:json)?\\s*"; "") | sub("\\s*```$"; "")
      | select(. != "")
    ' <<< "$found"
    ;;

  apply)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "usage: review-ledger.sh apply <update-file> <facts-file> [<previous-ledger-file>]"
    update_file="$1"
    facts_file="$2"
    previous_file="${3:-}"
    validate update "$update_file"
    jq -c '.repositoryInvariants' "$facts_file" | refuse_duplicate_classes "$facts_file"
    if [ -n "$previous_file" ]; then
      validate ledger "$previous_file"
      previous="$(cat "$previous_file")"
    else
      previous='null'
    fi
    reported="$(jq -c '.findings' "$update_file" | with_ids instance)"
    jq -c --argjson previous "$previous" --argjson reported "$reported" --slurpfile facts "$facts_file" '
      . as $update
      | ($facts[0]) as $facts
      | (($previous.round // 0) + 1) as $round
      | ($previous.findings // []) as $prior
      | ([$prior[].id]) as $prior_ids
      | ([$update.statuses[].id]) as $changed_ids
      | ([$reported[].id]) as $reported_ids
      | ([$changed_ids[] | select(. as $id | $prior_ids | index($id) | not)]) as $unknown
      | if ($unknown | length) > 0 then error("the update changes the status of findings the ledger does not hold: \($unknown | join(", "))") else . end
      | ([$changed_ids[] | select(. as $id | $reported_ids | index($id))]) as $conflicting
      | if ($conflicting | length) > 0 then error("the update both reports and changes the status of: \($conflicting | join(", "))") else . end
      | ($update.statuses | map({key: .id, value: .}) | from_entries) as $changes
      | ($reported | map({key: .id, value: .}) | from_entries) as $reports
      | ($prior | map(
          if $reports[.id] then . + ($reports[.id] | {path, severity, summary, enumerator}) + {status: "open", statusReason: "", lastRound: $round}
          elif $changes[.id] then . + {status: $changes[.id].status, statusReason: $changes[.id].reason, lastRound: $round}
          else . end
        )) as $carried
      | ($reported | map(select(.id as $id | $prior_ids | index($id) | not)) | unique_by(.id)
          | map({id, classKey, instance, path, severity, summary, enumerator, status: "open", statusReason: "", firstRound: $round, lastRound: $round})) as $new
      | ($facts.repositoryInvariants | map(. + {source: "repository", checkedRound: $round, instances: []})) as $repository_invariants
      | ([$repository_invariants[].classKey]) as $repository_classes
      | (($previous.invariants // []) | map(select(.source == "review"))
          # A class the repository now declares belongs to the repository from this round on, so a copy an earlier round derived is dropped rather than kept beside it.
          | map(select(.classKey as $class | ([$update.invariants[].classKey] + $repository_classes) | index($class) | not))) as $kept_review_invariants
      | ($update.invariants | map(select(.classKey as $class | $repository_classes | index($class) | not)) | unique_by(.classKey)
          | map(. + {source: "review", checkedRound: $round, instances: []})) as $declared
      | {
          version: 1,
          pullRequest: $facts.pullRequest,
          round: $round,
          reviewedHead: $facts.reviewedHead,
          baseSha: $facts.baseSha,
          patchId: $facts.patchId,
          reviewedFiles: $facts.reviewedFiles,
          scope: $facts.scope,
          invariants: ($repository_invariants + $kept_review_invariants + $declared),
          findings: ($carried + $new)
        }
    ' "$update_file" || die "the update could not be applied (see the message above)"
    ;;

  scope)
    [ "$#" -eq 4 ] || die "usage: review-ledger.sh scope <head> <reviewed-files-file> <previous-ledger-file> <delta-file>"
    head="$1"
    files_file="$2"
    validate ledger "$3"
    delta_file="$4"
    : > "$delta_file"
    since="$(jq -r '.reviewedHead' "$3")"
    # A head the checkout lacks is fetched by its id; GitHub serves one that a force push has left unreferenced only until it is collected, after which it is unreachable.
    if ! git cat-file -e "${since}^{commit}" 2> /dev/null && ! git fetch --no-tags --quiet origin "$since" 2> /dev/null; then
      jq -n -c '{kind: "full", since: null, reason: "the last reviewed head \($since[0:12]) can no longer be fetched, so the whole pull request is reviewed again"}' --arg since "$since"
    # In a shallow checkout whose boundary is at or below the head, the head's parents are cut off, so the ancestry check would call every head a force push. The head's whole history is fetched first, as a full-depth checkout already has it.
    elif [ "$(git rev-parse --is-shallow-repository)" = "true" ] && ! git fetch --no-tags --quiet --unshallow origin "$head"; then
      die "the checkout is shallow and fetching the history of ${head} from origin failed, so whether the last reviewed head ${since} is its ancestor cannot be decided"
    elif ! git merge-base --is-ancestor "$since" "$head"; then
      jq -n -c '{kind: "full", since: null, reason: "the last reviewed head \($since[0:12]) is not an ancestor of this head (a force push or rebase), so the whole pull request is reviewed again"}' --arg since "$since"
    else
      paths=()
      while IFS= read -r -d '' path; do
        paths+=("$path")
      done < <(jq -j --slurpfile previous "$3" '(. + $previous[0].reviewedFiles) | unique | .[] | (., "\u0000")' "$files_file")
      git diff --no-color --no-ext-diff "$since" "$head" -- ${paths[@]+"${paths[@]}"} > "$delta_file"
      jq -n -c '{kind: "delta", since: $since, reason: "the head moved forward from the last reviewed head, so only the changes since it are reviewed"}' --arg since "$since"
    fi
    ;;

  prepare)
    [ "$#" -ge 2 ] && [ "$#" -le 3 ] || die "usage: review-ledger.sh prepare <commit> <facts-file> [<previous-ledger-file>]"
    commit="$1"
    facts_file="$2"
    jq -c '.repositoryInvariants' "$facts_file" | refuse_duplicate_classes "$facts_file"
    if [ "$#" -eq 3 ]; then
      validate ledger "$3"
      previous="$(cat "$3")"
    else
      previous='null'
    fi
    # The invariants this round starts from: the repository's own, then those earlier rounds derived that the repository's do not replace.
    invariants="$(jq -c --argjson previous "$previous" '
      (.repositoryInvariants | map(. + {source: "repository"})) as $repository
      | ([$repository[].classKey]) as $repository_classes
      | $repository + (($previous.invariants // []) | map(select(.source == "review" and (.classKey as $class | $repository_classes | index($class) | not))) | map({classKey, statement, enumerator, source}))
    ' "$facts_file" | enumerate_invariants "$commit")"
    matches="$(jq -c --argjson previous "$previous" -n '($previous.findings // []) | map(select(.status == "open"))' | grep_finding_matches "$commit")"
    jq -n -c --argjson previous "$previous" --argjson invariants "$invariants" --argjson matches "$matches" --slurpfile facts "$facts_file" '{
      round: (($previous.round // 0) + 1),
      previousHead: $previous.reviewedHead,
      scope: $facts[0].scope,
      invariants: $invariants,
      findings: (($previous.findings // []) | map(. + {stillMatched: $matches[.id]}))
    }'
    ;;

  context)
    [ "$#" -ge 1 ] && [ "$#" -le 2 ] || die "usage: review-ledger.sh context <prepared-file> [<delta-file>]"
    delta_file="${2:-/dev/null}"
    jq -r --rawfile delta "$delta_file" '
      # A fence one backtick longer than the longest run of backticks in the diff, and never shorter than three, so no line of the diff can close it.
      def fence: "`" * ([3, ([$delta | match("`+"; "g") | .length] | max // 0) + 1] | max);
      def enumerator_text:
        if .type == "grep" then "grep `\(.pattern)` in \(if (.paths | length) == 0 then "the whole tree" else (.paths | map("`\(.)`") | join(", ")) end)"
        elif .type == "test" then "test `\(.name)`"
        else "lens `\(.name)`" end;
      def check_text:
        if .status != "open" then ""
        elif .stillMatched == true then " Its enumerator still matches this instance at this head."
        elif .stillMatched == false then " Its enumerator no longer matches this instance at this head, so the action records it as fixed: do not report it again, since a grep-enumerated finding whose instance the action cannot find fails the run."
        else "" end;
      [
        "# Review ledger",
        "",
        if .previousHead == null then
          "This is round 1: no earlier review round of this pull request is on record. Review the whole pull request."
        else
          ( "This is round \(.round). The ledger records \(.round - 1) earlier round(s); the last one reviewed head `\(.previousHead)`.",
            "",
            "Findings on record (id, class, severity, status, instance, summary):",
            "",
            (if (.findings | length) == 0 then "- none" else
              (.findings[] | "- `\(.id)` `\(.classKey)` \(.severity), \(.status): \(.instance | tojson). \(.summary | tojson)\(check_text)")
            end) )
        end,
        (if .previousHead == null then empty
         elif .scope.kind == "delta" then
           ( "",
             "## What this round reviews",
             "",
             "This round reviews the delta since the last reviewed head, `\(.scope.since)`: \(.scope.reason). The delta below is every change since that head to the files the pull request touches, and it is your input in place of the whole diff.",
             "",
             (if ($delta | length) == 0 then "The delta is empty: nothing in the pull request'"'"'s files changed since the last reviewed head." else
               (fence as $fence | "\($fence)diff\n\($delta | sub("\n$"; ""))\n\($fence)")
             end) )
         else
           ( "",
             "## What this round reviews",
             "",
             "This round reviews the whole pull request: \(.scope.reason)." )
         end),
        "",
        "Invariants to check this round, with every instance their enumerator finds at this head (class, where it came from, statement, enumerator, instances):",
        "",
        (if (.invariants | length) == 0 then "- none on record yet: derive them before you review, as the review instructions say" else
          (.invariants[]
            | "- `\(.classKey)` (\(.source)): \(.statement | tojson); \(.enumerator | enumerator_text)",
              (if .enumerator.type != "grep" then "  - not run by the action: check it yourself"
               elif (.instances | length) == 0 then "  - no instances"
               else (.instances[] | "  - \(.key | tojson) (\(.path), line \(.line))") end))
        end)
      ] | join("\n")
    ' "$1"
    ;;

  enumerate-ledger)
    [ "$#" -eq 2 ] || die "usage: review-ledger.sh enumerate-ledger <commit> <ledger-file>"
    commit="$1"
    file="$2"
    validate ledger "$file"
    invariants="$(jq -c '.invariants | map(del(.instances))' "$file" | enumerate_invariants "$commit")"
    matches="$(jq -c '.findings | map(select(.status != "retracted"))' "$file" | grep_finding_matches "$commit")"
    jq -c --argjson invariants "$invariants" --argjson matches "$matches" '
      .round as $round
      | .reviewedHead as $head
      | ([.findings[] | select(.lastRound == $round and .status == "open" and $matches[.id] == false) | .id]) as $unmatched
      | if ($unmatched | length) > 0 then
          error("findings reported this round name an instance their own grep enumerator does not find at \($head): \($unmatched | join(", ")); an instance of a grep-enumerated class must be one of the instance keys its enumerator lists")
        else . end
      | .invariants = $invariants
      | .findings |= map(
          if $matches[.id] == null then .
          elif .status == "open" and $matches[.id] == false then .status = "fixed" | .statusReason = "Its grep enumerator no longer matches this instance at \($head)."
          elif .status == "fixed" and $matches[.id] == true then .status = "open" | .statusReason = "Its grep enumerator matches this instance at \($head), so it is not fixed."
          else . end)
    ' "$file" || die "the ledger could not be enumerated (see the message above)"
    ;;

  render)
    [ "$#" -eq 1 ] || die "usage: review-ledger.sh render <ledger-file>"
    file="$1"
    body="$(jq -r --arg marker "$COMMENT_MARKER" --arg open "$DATA_OPEN" --arg close "$DATA_CLOSE" '
      # Class keys match a kebab-case pattern, so they are safe inside inline code. Nothing else the reviewer wrote is shown: a summary or instance could carry a mention or a link.
      def counts($status): [.findings[] | select(.status == $status)] | length;
      . as $ledger
      | [
          $marker,
          "**Review ledger**: round \(.round), reviewed head `\(.reviewedHead[0:12])`, \(if .scope.kind == "delta" then "a delta review since `\(.scope.since[0:12])`" else "a full review" end) (\(.scope.reason)).",
          "",
          "Findings: \(counts("open")) open, \(counts("fixed")) fixed, \(counts("retracted")) retracted.",
          (if counts("open") > 0 then
             "",
             "| Class | Open |",
             "| --- | --- |",
             ([.findings[] | select(.status == "open")] | group_by(.classKey)[] | "| `\(.[0].classKey)` | \(length) |")
           else empty end),
          "",
          "This comment is the record review mode keeps between rounds. Editing it changes what the next review is told.",
          "",
          $open,
          # ">" only ever appears inside a JSON string, where > is the same character, so the data can never close the HTML comment that holds it.
          ($ledger | tojson | gsub(">"; "\\u003e")),
          $close
        ]
      | join("\n")
    ' "$file")"
    length="$(jq -Rs 'length' <<< "$body")"
    if [ "$length" -gt "$COMMENT_BODY_LIMIT" ]; then
      die "the rendered ledger is ${length} characters, over GitHub's ${COMMENT_BODY_LIMIT}-character comment limit; the largest parts are: $(jq -r '[(.invariants[] | {what: "invariant \(.classKey)", size: (tojson | length)}), (.findings[] | {what: "finding \(.id)", size: (tojson | length)})] | sort_by(-.size) | .[0:3] | map("\(.what) (\(.size))") | join(", ")' "$file")"
    fi
    printf '%s\n' "$body"
    ;;

  *)
    die "usage: review-ledger.sh <subcommand> [<argument>...], with the subcommands the header of this script lists"
    ;;
esac
