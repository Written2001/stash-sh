#!/usr/bin/env bash
set -euo pipefail

if [[ "${0##*/}" == curl ]]; then
  jq -cn --args '$ARGS.positional' -- "$@" > "$TEST_TMP/arguments.json"
  printf 'request\n' >> "$TEST_TMP/requests"
  while (( $# )); do
    if [[ "$1" == --data-binary ]]; then
      printf '%s\n' "$2" > "$TEST_TMP/payload.json"
      break
    fi
    shift
  done
  if [[ -v MOCK_BODY ]]; then
    printf '%s' "$MOCK_BODY"
  else
    mutation=$(jq -r 'if .query | contains("metadataScan") then "metadataScan" else "metadataGenerate" end' "$TEST_TMP/payload.json")
    jq -cn --arg mutation "$mutation" '{data: {($mutation): "42"}}'
  fi
  exit "${MOCK_EXIT:-0}"
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d)
export TEST_TMP
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/bin"
ln -s "$root/tests/stash_test.sh" "$TEST_TMP/bin/curl"
checks=0

assert() {
  if ! "$@" >/dev/null; then
    printf 'Assertion failed: %s\n' "$*" >&2
    exit 1
  fi
  checks=$((checks + 1))
}

run() {
  local expected=$1 status=0
  shift
  local environment=()
  while [[ "$1" != -- ]]; do
    environment+=("$1")
    shift
  done
  shift
  rm -f "$TEST_TMP/requests" "$TEST_TMP/payload.json" "$TEST_TMP/arguments.json"
  env -i PATH="$TEST_TMP/bin:$PATH" HOME="$TEST_TMP" TEST_TMP="$TEST_TMP" \
    STASH_URL=http://stash:9999/graphql "${environment[@]}" \
    bash "$root/stash.sh" "$@" > "$TEST_TMP/stdout" 2> "$TEST_TMP/stderr" || status=$?
  if [[ "$status" != "$expected" ]]; then
    printf 'Expected exit %s, got %s: %s\n' "$expected" "$status" "$*" >&2
    cat "$TEST_TMP/stderr" >&2
    exit 1
  fi
  checks=$((checks + 1))
  if [[ "$expected" == 2 ]]; then
    assert test ! -e "$TEST_TMP/requests"
    assert test ! -s "$TEST_TMP/stdout"
    assert test -s "$TEST_TMP/stderr"
  elif [[ -e "$TEST_TMP/requests" ]]; then
    assert test "$(wc -l < "$TEST_TMP/requests")" -eq 1
    if [[ "$expected" == 0 ]]; then
      assert test "$(< "$TEST_TMP/stdout")" = 42
      assert test ! -s "$TEST_TMP/stderr"
    else
      assert test ! -s "$TEST_TMP/stdout"
      assert test -s "$TEST_TMP/stderr"
    fi
  fi
}

payload_is() {
  assert jq -e "$1" "$TEST_TMP/payload.json"
}

scan_options=(
  'covers:scanGenerateCovers:true' 'previews:scanGeneratePreviews:true'
  'image-previews:scanGenerateImagePreviews:true' 'sprites:scanGenerateSprites:true'
  'phashes:scanGeneratePhashes:true' 'image-phashes:scanGenerateImagePhashes:true'
  'thumbnails:scanGenerateThumbnails:true' 'clip-previews:scanGenerateClipPreviews:true'
  'rescan:rescan:false'
)
generate_options=(
  'covers:covers:true' 'sprites:sprites:true' 'previews:previews:true'
  'image-previews:imagePreviews:true' 'markers:markers:true'
  'marker-image-previews:markerImagePreviews:true' 'marker-screenshots:markerScreenshots:true'
  'transcodes:transcodes:true' 'phashes:phashes:true'
  'interactive-heatmaps-speeds:interactiveHeatmapsSpeeds:true'
  'image-phashes:imagePhashes:true' 'image-thumbnails:imageThumbnails:true'
  'clip-previews:clipPreviews:true' 'force-transcodes:forceTranscodes:false' 'overwrite:overwrite:false'
)
for command in scan generate; do
  if [[ "$command" == scan ]]; then
    options=("${scan_options[@]}")
    mutation=metadataScan
    input_type=ScanMetadataInput
  else
    options=("${generate_options[@]}")
    mutation=metadataGenerate
    input_type=GenerateMetadataInput
  fi
  run 0 -- "$command" '/media/default target'
  payload_is ".query == \"mutation(\$input: $input_type!) { $mutation(input: \$input) }\""
  payload_is '.variables.input.paths == ["/media/default target"]'
  payload_is ".variables.input | length == $((${#options[@]} + 1))"
  for entry in "${options[@]}"; do
    IFS=: read -r name field default <<< "$entry"
    payload_is ".variables.input.$field == $default"
  done
  run 0 STASH_URL= STASH_APIKEY= -- "$command" --help
  help=$(< "$TEST_TMP/stdout")
  assert test ! -e "$TEST_TMP/requests"
  assert test ! -s "$TEST_TMP/stderr"
  assert test "${help##*$'\n'}" = 'README: https://github.com/Written2001/stash-sh/blob/main/README.md'
  if [[ "$command" == scan ]]; then
    assert test "${help#*'RFC3339 timestamp, e.g. 2026-01-01T00:00:00Z (UTC)'}" != "$help"
  fi
  environment=()
  flags=()
  for entry in "${options[@]}"; do
    IFS=: read -r name field default <<< "$entry"
    suffix=${name//-/_}
    variable="STASH_${command^^}_${suffix^^}"
    block=${help#*"--$name / --no-$name"}
    block=${block%%Environment:*}
    assert test "$block" != "$help"
    assert test "${block#*"(default: $default)"}" != "$block"
    assert test "${help#*"Environment: $variable"}" != "$help"
    environment+=("$variable=false")
    flags+=("--$name")
  done
  run 0 "${environment[@]}" -- "$command" /media
  payload_is '.variables.input | del(.paths) | all(.[]; . == false)'
  run 0 "${environment[@]}" -- "$command" "${flags[@]}" /media
  payload_is '.variables.input | del(.paths) | all(.[]; . == true)'
  flags=()
  for entry in "${options[@]}"; do
    flags+=("--no-${entry%%:*}")
  done
  run 0 -- "$command" "${flags[@]}" /media
  payload_is '.variables.input | del(.paths) | all(.[]; . == false)'
  run 0 -- "$command" --all
  payload_is '.variables.input | has("paths") | not'
  run 2 -- "$command"
  run 2 -- "$command" --all /media
  run 2 -- "$command" --unknown /media
  run 2 -- "$command" ''
done

run 0 -- --help
assert test ! -e "$TEST_TMP/requests"
run 0 -- scan -h
run 0 -- generate --covers --no-covers --covers /media
payload_is '.variables.input.covers == true'
run 0 STASH_GENERATE_COVERS= STASH_SCAN_COVERS=invalid -- generate /media
payload_is '.variables.input.covers == true'
run 0 STASH_GENERATE_COVERS=invalid -- generate --covers /media
payload_is '.variables.input.covers == true'
run 2 STASH_SCAN_COVERS=yes -- scan /media
run 2 -- watch /media
run 2 --
run 2 -- scan --overwrite /media
run 2 -- generate --rescan /media
run 2 -- generate --no-preview-preset /media
run 2 -- generate --preview-segments
run 2 -- generate --preview-exclude-start --no-previews /media
run 2 -- generate --scene-id --all
run 2 -- scan --no- /media
run 2 -- generate --preview-segments abc /media
run 2 -- generate --preview-segments 2147483648 /media
run 2 -- generate --preview-segments 1.5 /media
run 2 -- generate --preview-segment-duration NaN /media
run 2 -- generate --preview-segment-duration 1e999 /media
run 2 -- generate --preview-preset invalid /media
run 2 -- scan --min-mod-time '' /media
run 2 STASH_URL= -- scan /media
run 2 STASH_URL=http://stash:9999 -- scan /media
run 0 STASH_URL=https://stash.example/stash/graphql/ -- scan /media
run 2 STASH_APIKEY=$'invalid\nheader' -- scan /media
run 2 -- scan -relative
run 0 -- scan -- '/media/a "quote"\slash' $'/media/line\nbreak' '/media/日本語' '-relative'
assert jq -e --argjson expected "$(jq -cn --args '$ARGS.positional' -- '/media/a "quote"\slash' $'/media/line\nbreak' '/media/日本語' '-relative')" \
  ".variables.input.paths == \$expected" "$TEST_TMP/payload.json"
run 0 STASH_SCAN_PATHS='["/old","/other"]' -- scan '/new path' --no-covers /second
payload_is '.variables.input.paths == ["/new path","/second"] and .variables.input.scanGenerateCovers == false'
run 0 STASH_GENERATE_PATHS='["/from-env"]' -- generate
payload_is '.variables.input.paths == ["/from-env"]'
run 2 STASH_SCAN_PATHS='["/from-env"]' -- scan --all
for invalid in 'not json' '{}' 'null' '[1]' '[null]' '[""]' '[] []'; do
  run 2 "STASH_SCAN_PATHS=$invalid" -- scan
  run 2 "STASH_GENERATE_SCENE_IDS=$invalid" -- generate
done
run 2 STASH_SCAN_PATHS='[]' -- scan
run 2 STASH_GENERATE_SCENE_IDS='[]' -- generate
run 2 -- generate --scene-id ''
run 2 -- generate --all --scene-id 1
run 2 STASH_GENERATE_SCENE_IDS='["1"]' -- generate --all
run 0 STASH_GENERATE_SCENE_IDS='["old"]' STASH_GENERATE_MARKER_IDS='["keep"]' -- generate \
  --scene-id 1 --scene-id 2 --image-id 3 --image-id 4 --gallery-id 5 /media
payload_is '.variables.input | .sceneIDs == ["1","2"] and .markerIDs == ["keep"] and .imageIDs == ["3","4"] and .galleryIDs == ["5"] and .paths == ["/media"]'
run 0 STASH_GENERATE_SCENE_IDS='["scene"]' STASH_GENERATE_MARKER_IDS='["marker"]' \
  STASH_GENERATE_IMAGE_IDS='["image"]' STASH_GENERATE_GALLERY_IDS='["gallery"]' -- generate
payload_is '.variables.input | .sceneIDs == ["scene"] and .markerIDs == ["marker"] and .imageIDs == ["image"] and .galleryIDs == ["gallery"] and (has("paths") | not)'
run 0 -- generate --marker-id 9 --marker-id 10
payload_is '.variables.input.markerIDs == ["9","10"]'
run 0 STASH_GENERATE_PREVIEW_SEGMENTS=8 STASH_GENERATE_PREVIEW_SEGMENT_DURATION=0.5 \
  STASH_GENERATE_PREVIEW_EXCLUDE_START=10s STASH_GENERATE_PREVIEW_EXCLUDE_END=5s STASH_GENERATE_PREVIEW_PRESET=fast -- generate /media
payload_is '.variables.input.previewOptions == {previewSegments:8, previewSegmentDuration:0.5, previewExcludeStart:"10s", previewExcludeEnd:"5s", previewPreset:"fast"}'
run 0 STASH_GENERATE_PREVIEW_SEGMENTS=8 -- generate /media --preview-segments 12 \
  --preview-segment-duration 1.25 --preview-exclude-start 2s --preview-exclude-end 3s --preview-preset slow
payload_is '.variables.input.previewOptions == {previewSegments:12, previewSegmentDuration:1.25, previewExcludeStart:"2s", previewExcludeEnd:"3s", previewPreset:"slow"}'
run 0 -- generate /media --preview-exclude-start ''
payload_is '.variables.input.previewOptions == {previewExcludeStart:""}'
run 0 STASH_SCAN_MIN_MOD_TIME=2026-01-01T00:00:00Z -- scan /media
payload_is '.variables.input.filter == {minModTime:"2026-01-01T00:00:00Z"}'
run 0 STASH_SCAN_MIN_MOD_TIME=2026-01-01T00:00:00Z -- scan --min-mod-time 2026-02-01T00:00:00+01:00 /media
payload_is '.variables.input.filter == {minModTime:"2026-02-01T00:00:00+01:00"}'

run 0 STASH_APIKEY=test-key -- scan /media
assert jq -e 'index("ApiKey: test-key") != null and index("--insecure") == null and index("--retry") == null and index("--fail-with-body") != null and index("--connect-timeout") != null and index("--max-time") != null' "$TEST_TMP/arguments.json"
run 0 -- generate /media
assert jq -e 'all(.[]; startswith("ApiKey:") | not)' "$TEST_TMP/arguments.json"
for body in 'not JSON' '' 'null' '[]' '{} {}' '{"errors":[{"message":"denied"}]}' \
  '{"errors":[{"message":"partial failure"}],"data":{"metadataGenerate":"42"}}' \
  '{}' '{"data":{"metadataGenerate":null}}' '{"data":{"metadataGenerate":""}}' '{"data":{"metadataGenerate":42}}'; do
  run 1 "MOCK_BODY=$body" -- generate /media
done
for status in 7 22 28; do
  run 1 "MOCK_EXIT=$status" 'MOCK_BODY={"data":{"metadataScan":"42"}}' -- scan /media
done
run 0 'MOCK_BODY={"errors":[],"data":{"metadataScan":"42"}}' -- scan /media
printf 'Passed %s assertions.\n' "$checks"