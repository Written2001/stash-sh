#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'stash.sh: %s\n' "$1" >&2
  exit "${2:-2}"
}

option_table() {
  case "$command" in
    scan)
      printf '%s\n' \
        'covers|scanGenerateCovers|bool|true|Generate scene covers' \
        'previews|scanGeneratePreviews|bool|true|Generate video previews' \
        'image-previews|scanGenerateImagePreviews|bool|true|Generate animated image previews' \
        'sprites|scanGenerateSprites|bool|true|Generate scrubber sprites' \
        'phashes|scanGeneratePhashes|bool|true|Generate video perceptual hashes' \
        'image-phashes|scanGenerateImagePhashes|bool|true|Generate image perceptual hashes' \
        'thumbnails|scanGenerateThumbnails|bool|true|Generate image thumbnails' \
        'clip-previews|scanGenerateClipPreviews|bool|true|Generate image clip previews' \
        'rescan|rescan|bool|false|Rescan unchanged files' \
        'min-mod-time|filter.minModTime|timestamp|unset|Ignore files modified before this RFC3339 timestamp, e.g. 2026-01-01T00:00:00Z (UTC)'
      ;;
    generate)
      printf '%s\n' \
        'covers|covers|bool|true|Generate scene covers' \
        'sprites|sprites|bool|true|Generate scrubber sprites' \
        'previews|previews|bool|true|Generate video previews' \
        'image-previews|imagePreviews|bool|true|Generate animated image previews' \
        'markers|markers|bool|true|Generate marker videos' \
        'marker-image-previews|markerImagePreviews|bool|true|Generate marker animated image previews' \
        'marker-screenshots|markerScreenshots|bool|true|Generate marker screenshots' \
        'transcodes|transcodes|bool|true|Generate required transcodes' \
        'phashes|phashes|bool|true|Generate video perceptual hashes' \
        'interactive-heatmaps-speeds|interactiveHeatmapsSpeeds|bool|true|Generate interactive heatmaps and speeds' \
        'image-phashes|imagePhashes|bool|true|Generate image perceptual hashes' \
        'image-thumbnails|imageThumbnails|bool|true|Generate image thumbnails' \
        'clip-previews|clipPreviews|bool|true|Generate image clip previews' \
        'force-transcodes|forceTranscodes|bool|false|Generate transcodes even when not required' \
        'overwrite|overwrite|bool|false|Overwrite existing generated media' \
        'preview-segments|previewOptions.previewSegments|int|unset|Number of preview segments' \
        'preview-segment-duration|previewOptions.previewSegmentDuration|float|unset|Preview segment duration in seconds' \
        'preview-exclude-start|previewOptions.previewExcludeStart|string|unset|Duration to exclude at the start' \
        'preview-exclude-end|previewOptions.previewExcludeEnd|string|unset|Duration to exclude at the end' \
        'preview-preset|previewOptions.previewPreset|preset|unset|ultrafast, veryfast, fast, medium, slow, slower, veryslow' \
        'scene-id|sceneIDs|ids|unset|Select a scene ID; repeat for multiple IDs' \
        'marker-id|markerIDs|ids|unset|Select a marker ID; repeat for multiple IDs' \
        'image-id|imageIDs|ids|unset|Select an image ID; repeat for multiple IDs' \
        'gallery-id|galleryIDs|ids|unset|Select a gallery ID; repeat for multiple IDs'
      ;;
  esac
}

env_name() {
  local suffix=${1//-/_}
  [[ "$2" != ids ]] || suffix="${suffix}S"
  printf 'STASH_%s_%s' "${command^^}" "${suffix^^}"
}

help() {
  printf '%s\n' \
    'Usage: stash.sh {scan|generate} [OPTIONS] [PATH ...]' \
    'Returns a Stash metadata job ID (does not wait for completion).' \
    '' \
    'STASH_URL: required http(s) GraphQL endpoint, e.g. http://stash:9999/graphql' \
    'STASH_APIKEY: optional API key; required if your server requires authentication.' \
    'Precedence: built-in defaults < nonempty environment values < CLI flags.' \
    'Boolean environment values: true or false. Empty environment values are unset.' \
    '' \
    '  --help, -h       Show help without credentials or network access.' \
    '  --all            Target the whole library (default: false); cannot combine with targets.' \
    '  --               Treat remaining arguments as paths.'
  if [[ "$command" == scan || "$command" == generate ]]; then
    printf '\n%s options (defaults below are built-in):\n' "$command"
    local name field type default description label
    while IFS='|' read -r name field type default description; do
      label="--$name VALUE"
      [[ "$type" != bool ]] || label="--$name / --no-$name"
      printf '  %s\n    %s (default: %s)\n    Environment: %s\n' \
        "$label" "$description" "$default" "$(env_name "$name" "$type")"
    done < <(option_table)
  else
    printf '\nCommands:\n  scan      Scan files into the library.\n  generate  Generate supporting media.\n\nUse scan --help or generate --help for every switch and its default.\n'
  fi
  printf '\nREADME: https://github.com/Written2001/stash-sh/blob/main/README.md\n'
}

json_value() {
  local name=$1 type=$2 value=$3
  case "$type" in
    bool)
      [[ "$value" == true || "$value" == false ]] || fail "$name must be true or false"
      printf '%s' "$value"
      ;;
    int)
      [[ "$value" =~ ^-?(0|[1-9][0-9]*)$ ]] || fail "$name must be a 32-bit integer"
      jq -cen --arg value "$value" '$value | tonumber | select(. >= -2147483648 and . <= 2147483647)' \
        || fail "$name must be a 32-bit integer"
      ;;
    float)
      [[ "$value" =~ ^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$ ]] || fail "$name must be a finite number"
      jq -cen --arg value "$value" '$value | tonumber | select(isfinite)' \
        || fail "$name must be a finite number"
      ;;
    ids|paths)
      jq -ces 'select(length == 1) | .[0] | select(type == "array") | select(all(.[]; type == "string" and length > 0))' \
        <<< "$value" 2>/dev/null || fail "$name must be a JSON array of nonempty strings"
      ;;
    preset)
      case "$value" in
        ultrafast|veryfast|fast|medium|slow|slower|veryslow) ;;
        *) fail "$name is not a supported preview preset" ;;
      esac
      jq -cn --arg value "$value" '$value'
      ;;
    timestamp)
      [[ -n "$value" ]] || fail "$name requires a timestamp"
      jq -cn --arg value "$value" '$value'
      ;;
    string) jq -cn --arg value "$value" '$value' ;;
  esac
}

command=${1:-}
case "$command" in
  -h|--help) help; exit 0 ;;
  scan|generate) shift ;;
  *) help >&2; fail 'expected scan or generate' ;;
esac
for argument in "$@"; do
  [[ "$argument" != -- ]] || break
  if [[ "$argument" == --help || "$argument" == -h ]]; then
    help
    exit 0
  fi
done
for dependency in jq curl; do
  command -v "$dependency" >/dev/null || fail "required program not found: $dependency"
done

declare -A fields=() types=() values=() selected=()
names=()
while IFS='|' read -r name field type default description; do
  names+=("$name")
  fields[$name]=$field
  types[$name]=$type
  variable=$(env_name "$name" "$type")
  if [[ -n "${!variable:-}" ]]; then
    values[$name]=${!variable}
  elif [[ "$default" != unset ]]; then
    values[$name]=$default
  fi
done < <(option_table)

paths=()
all=false
while (( $# )); do
  case "$1" in
    --) shift; paths+=("$@"); break ;;
    --all) all=true; shift ;;
    --*)
      name=${1#--}
      enabled=true
      if [[ "$name" == no-* ]]; then
        name=${name#no-}
        enabled=false
        [[ -n "$name" && "${types[$name]:-}" == bool ]] || fail "unknown Boolean switch: $1"
      fi
      [[ -n "${types[$name]:-}" ]] || fail "unknown $command option: $1"
      if [[ "${types[$name]}" == bool ]]; then
        values[$name]=$enabled
        shift
      else
        (( $# >= 2 )) || fail "$1 requires a value"
        [[ "$2" != --* && "$2" != -h ]] || fail "$1 requires a value, not another flag"
        if [[ "${types[$name]}" == ids ]]; then
          [[ -n "$2" ]] || fail "$1 requires a nonempty ID"
          if [[ -z "${selected[$name]:-}" ]]; then
            values[$name]='[]'
            selected[$name]=true
          fi
          values[$name]=$(jq -cn --argjson ids "${values[$name]}" --arg id "$2" '$ids + [$id]')
        else
          values[$name]=$2
        fi
        shift 2
      fi
      ;;
    -*) fail "unknown option: $1 (use -- before dash-prefixed paths)" ;;
    *) paths+=("$1"); shift ;;
  esac
done

input='{}'
targets=0
for name in "${names[@]}"; do
  [[ -v "values[$name]" ]] || continue
  value=$(json_value "--$name / $(env_name "$name" "${types[$name]}")" "${types[$name]}" "${values[$name]}")
  if [[ "${types[$name]}" == ids ]]; then
    count=$(jq 'length' <<< "$value")
    targets=$((targets + count))
    (( count > 0 )) || continue
  fi
  input=$(jq -cn --argjson input "$input" --arg field "${fields[$name]}" --argjson value "$value" \
    '$input | setpath($field | split("."); $value)')
done
variable="STASH_${command^^}_PATHS"
path_value=${!variable:-[]}
if (( ${#paths[@]} )); then
  path_value=$(jq -cn --args '$ARGS.positional' -- "${paths[@]}")
fi
path_value=$(json_value "$variable / PATH" paths "$path_value")
count=$(jq 'length' <<< "$path_value")
targets=$((targets + count))
if (( count > 0 )); then
  input=$(jq -cn --argjson input "$input" --argjson paths "$path_value" '$input + {paths: $paths}')
fi
if [[ "$all" == true ]]; then
  (( targets == 0 )) || fail '--all cannot be combined with paths or IDs'
else
  (( targets > 0 )) || fail 'supply paths, generate IDs, or --all'
fi

[[ "${STASH_URL:-}" =~ ^https?://[^/[:space:]]+(/[^[:space:]?#]*)?/graphql/?$ ]] \
  || fail 'STASH_URL must be a full http(s) /graphql endpoint'
[[ "${STASH_APIKEY:-}" != *$'\n'* && "${STASH_APIKEY:-}" != *$'\r'* ]] \
  || fail 'STASH_APIKEY cannot contain line breaks'
case "$command" in
  scan) mutation=metadataScan; input_type=ScanMetadataInput ;;
  generate) mutation=metadataGenerate; input_type=GenerateMetadataInput ;;
esac
query="mutation(\$input: $input_type!) { $mutation(input: \$input) }"
payload=$(jq -cn --arg query "$query" --argjson input "$input" '{query: $query, variables: {input: $input}}')
headers=(-H 'Content-Type: application/json')
[[ -z "${STASH_APIKEY:-}" ]] || headers+=(-H "ApiKey: $STASH_APIKEY")
response=$(curl --silent --show-error --fail-with-body --connect-timeout 10 --max-time 60 \
  "${headers[@]}" --data-binary "$payload" "$STASH_URL") || fail 'HTTP request failed; job submission was not confirmed' 1
response=$(jq -ces 'select(length == 1 and (.[0] | type == "object")) | .[0]' <<< "$response" 2>/dev/null) \
  || fail 'Stash returned an invalid JSON response' 1
if ! jq -e '(.errors == null) or (.errors == [])' <<< "$response" >/dev/null; then
  jq -r '.errors[]? | .message // "Unknown GraphQL error"' <<< "$response" >&2 || true
  fail 'GraphQL request failed' 1
fi
jq -er --arg mutation "$mutation" '.data[$mutation] | select(type == "string" and length > 0)' \
  <<< "$response" || fail 'Stash did not return a job ID' 1