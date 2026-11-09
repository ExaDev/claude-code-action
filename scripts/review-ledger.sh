#!/usr/bin/env bash
# Reads, checks, updates and renders review mode's ledger: the record of a pull request's earlier review rounds that the action keeps in a comment on the pull request. Its shape is schemas/review-ledger.schema.json, and docs/review-ledger.md describes how review mode uses it.
#
# Usage, one subcommand per line:
# - `review-ledger.sh id <class-key> <instance>` prints the stable id of one instance of a class.
# - `review-ledger.sh patch-id < diff` prints git patch-id --stable of a diff, or nothing for an empty diff.
# - `review-ledger.sh extract < comments` reads a JSON array of issue comments and prints {"commentId": <id>, "ledger": <ledger>} for the newest comment written by a bot that carries the ledger marker, or nothing when there is none; a marker comment whose data block is missing or not JSON is an error.
# - `review-ledger.sh check <ledger-file>` exits non-zero, naming every problem on stderr, unless the file is a valid ledger whose ids are the ones its class keys and instances produce.
# - `review-ledger.sh update-block <execution-file>` prints the JSON between the last <review-ledger-update> and </review-ledger-update> tags of a run's final result message, or, when that message has none, of the newest of the run's own assistant messages (text or tool call input) that has one, naming on stderr which it read; prints nothing when the run wrote no block.
# - `review-ledger.sh apply <update-file> <facts-file> [<previous-ledger-file>]` prints the ledger after this round: the previous ledger (if any) with the reviewer's update merged in and the runner's facts (pullRequest, reviewedHead, baseSha, patchId, reviewedFiles, scope) set.
# - `review-ledger.sh render <ledger-file>` prints the comment body that stores the ledger.
#
# A command that finds invalid input prints why on stderr and exits 1; nothing is skipped silently.
set -euo pipefail

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
      | (($previous.invariants // []) | map(select(.source == "repository"))) as $repository_invariants
      | ([$repository_invariants[].classKey]) as $repository_classes
      | (($previous.invariants // []) | map(select(.source == "review"))
          | map(select(.classKey as $class | [$update.invariants[].classKey] | index($class) | not))) as $kept_review_invariants
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

  context)
    [ "$#" -le 1 ] || die "usage: review-ledger.sh context [<previous-ledger-file>]"
    if [ "$#" -eq 1 ]; then
      validate ledger "$1"
      previous="$(cat "$1")"
    else
      previous='null'
    fi
    jq -n -r --argjson previous "$previous" '
      def enumerator_text:
        if .type == "grep" then "grep `\(.pattern)` in \(if (.paths | length) == 0 then "the whole tree" else (.paths | map("`\(.)`") | join(", ")) end)"
        elif .type == "test" then "test `\(.name)`"
        else "lens `\(.name)`" end;
      [
        "# Review ledger",
        "",
        if $previous == null then
          "This is round 1: no earlier review round of this pull request is on record. Review the whole pull request."
        else
          ( "This is round \($previous.round + 1). The ledger records \($previous.round) earlier round(s); the last one reviewed head `\($previous.reviewedHead)`.",
            "",
            "Findings on record (id, class, severity, status, instance, summary):",
            "",
            (if ($previous.findings | length) == 0 then "- none" else
              ($previous.findings[] | "- `\(.id)` `\(.classKey)` \(.severity), \(.status): \(.instance | tojson). \(.summary | tojson)")
            end),
            "",
            "Invariants on record (class, statement, enumerator):",
            "",
            (if ($previous.invariants | length) == 0 then "- none" else
              ($previous.invariants[] | "- `\(.classKey)` (\(.source)): \(.statement | tojson); \(.enumerator | enumerator_text)")
            end) )
        end
      ] | join("\n")
    '
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
