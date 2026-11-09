# Validates a JSON value against a JSON Schema, for the scripts that read a schema committed under schemas/ and must check data against it in the runner, where no schema library is installed.
#
# Usage (from a script): jq -L "<this directory>" 'include "json-schema"; schema_errors($root; $schema; "$")'
#
# schema_errors emits one human-readable string per violation, each prefixed with the path of the offending value ("$.findings[0].status"), and emits nothing for a valid value. It implements the keywords the schemas in this repository use: type, const, enum, pattern, minLength, minimum, required, properties, additionalProperties (false only), items, oneOf and local $ref ("#/$defs/<name>"). Any other keyword in a schema, and any other form of $ref, stops with an error rather than being skipped, so a schema can never silently ask for a check this validator does not make.

def _known_keywords:
  ["$schema", "$id", "$ref", "$defs", "title", "description", "type", "const", "enum", "pattern", "minLength", "minimum", "required", "properties", "additionalProperties", "items", "oneOf"];

# The schema a local $ref points at, followed until it is not itself a $ref.
def _resolve($root):
  if type == "object" and has("$ref") then
    ."$ref" as $ref
    | if ($ref | startswith("#/$defs/")) then
        ($root["$defs"][$ref | ltrimstr("#/$defs/")] // error("json-schema: undefined $ref \($ref)")) | _resolve($root)
      else
        error("json-schema: unsupported $ref \($ref); only #/$defs/<name> is implemented")
      end
  else
    .
  end;

# The JSON Schema type names a value satisfies; a whole number is both an integer and a number.
def _type_names:
  if type == "number" then
    (if . == floor then ["integer", "number"] else ["number"] end)
  else
    [type]
  end;

def schema_errors($root; $schema; $path):
  . as $value
  | ($schema | _resolve($root)) as $s
  | ($s | keys - _known_keywords) as $unknown
  | if ($unknown | length) > 0 then
      error("json-schema: unsupported keyword(s) \($unknown | join(", ")) at \($path)")
    else
      (if $s | has("type") then
         ($s.type | if type == "array" then . else [.] end) as $wanted
         | if any($value | _type_names[]; . as $name | any($wanted[]; . == $name)) then empty
           else "\($path): expected \($wanted | join(" or ")), got \($value | type)"
           end
       else empty end),
      (if $s | has("const") then
         (if $value == $s.const then empty else "\($path): expected \($s.const | tojson)" end)
       else empty end),
      (if $s | has("enum") then
         (if any($s.enum[]; . == $value) then empty else "\($path): \($value | tojson) is not one of \($s.enum | tojson)" end)
       else empty end),
      (if ($s | has("pattern")) and ($value | type) == "string" then
         (if ($value | test($s.pattern)) then empty else "\($path): \($value | tojson) does not match \($s.pattern)" end)
       else empty end),
      (if ($s | has("minLength")) and ($value | type) == "string" then
         (if ($value | length) >= $s.minLength then empty else "\($path): shorter than \($s.minLength)" end)
       else empty end),
      (if ($s | has("minimum")) and ($value | type) == "number" then
         (if $value >= $s.minimum then empty else "\($path): less than \($s.minimum)" end)
       else empty end),
      (if ($s | has("required")) and ($value | type) == "object" then
         $s.required[] | select(. as $key | $value | has($key) | not) | "\($path): missing \(.)"
       else empty end),
      (if ($value | type) == "object" then
         $value | to_entries[]
         | .key as $key
         | if (($s.properties // {}) | has($key)) then
             .value | schema_errors($root; $s.properties[$key]; "\($path).\($key)")
           elif $s.additionalProperties == false then
             "\($path): unexpected property \($key | tojson)"
           else empty end
       else empty end),
      (if ($s | has("items")) and ($value | type) == "array" then
         range(0; $value | length) as $index
         | $value[$index] | schema_errors($root; $s.items; "\($path)[\($index)]")
       else empty end),
      (if $s | has("oneOf") then
         ([$s.oneOf[] as $branch | [$value | schema_errors($root; $branch; $path)] | length == 0] | map(select(.)) | length) as $matched
         | if $matched == 1 then empty else "\($path): matches \($matched) of the \($s.oneOf | length) allowed shapes, not exactly one" end
       else empty end)
    end;
