# stash.sh

A small Docker CLI for Stash's `metadataScan` and `metadataGenerate` GraphQL mutations. It submits one job, prints the job ID, and exits. Stash performs the work asynchronously; successful submission does not mean the job has completed.

The supported API is the latest stable Stash release, currently **v0.31.1**. All input fields of both mutations are exposed. There is no watcher, scheduler, or persisted configuration.

## Quick Start

Create your environment file from [stash-sh.env.example](stash-sh.env.example):

```bash
cp stash-sh.env.example stash-sh.env
chmod 600 stash-sh.env
```

Edit the connection settings:

```dotenv
STASH_URL=http://stash:9999/graphql
STASH_APIKEY=your-stash-api-key
```

`STASH_URL` must be the complete HTTP(S) GraphQL endpoint. `STASH_APIKEY` may be empty if your Stash server does not require authentication. Docker env-files use literal `KEY=value` lines: no `export`, shell expansion, or surrounding shell quotes. JSON list values still need JSON quotes around their elements.

Scan:

```bash
docker run --rm \
  --env-file "/path/to/stash-sh/stash-sh.env" \
  ghcr.io/written2001/stash-sh:latest scan /path/to/scan
```

Generate:

```bash
docker run --rm \
  --env-file "/path/to/stash-sh/stash-sh.env" \
  ghcr.io/written2001/stash-sh:latest generate /path/to/generate
```

Paths are **paths visible to Stash**, not paths inside this helper container or necessarily on the Docker host. No media volume mounts are needed. The helper does not check local file existence or scan media itself. Generation operates on content already indexed by Stash; use `scan` first for new files.

Multiple paths, including paths with spaces, are supported:

```bash
docker run --rm --env-file stash-sh.env \
  ghcr.io/written2001/stash-sh:latest scan "/media/new content" /media/other
```

Inside Docker, `localhost` means the helper container. Use a reachable server address, or attach the helper to Stash's Docker network with `--network NETWORK` and use Stash's service/container name. For a server on a Linux Docker host, add `--add-host=host.docker.internal:host-gateway` and use `http://host.docker.internal:9999/graphql`; Stash must listen on an interface reachable from containers. Alternatively, Linux `--network host` allows access to the host's localhost. HTTPS certificates are verified normally; there is no insecure mode.

## Defaults And Overrides

**Every output-generation switch defaults to `true`.** `rescan`, `overwrite`, and `force-transcodes` default to `false`. These are helper-owned defaults, not settings fetched from the Stash UI.

Precedence: **built-in defaults < nonempty environment values < CLI flags**.

- Enable a Boolean with `--NAME`; disable it with `--no-NAME`.
- Boolean environment values must be exactly `true` or `false`.
- Empty environment values are treated as unset.
- For repeated Boolean/scalar flags, the last value wins.
- Scalar flags take a separate argument, for example `--preview-segments 12`; `--NAME=value` is not supported.
- Options may appear before or after paths. Use `--` before dash-prefixed paths.
- Only the active command's environment options are used.
- Unset preview settings are omitted, letting Stash use its configured values. An unset scan filter applies no modification-time restriction.

Disable expensive generation features in your env-file:

```dotenv
STASH_SCAN_PREVIEWS=false
STASH_SCAN_IMAGE_PREVIEWS=false
STASH_GENERATE_TRANSCODES=false
```

Override those defaults for one run:

```bash
docker run --rm --env-file stash-sh.env \
  ghcr.io/written2001/stash-sh:latest generate --transcodes --no-sprites /media/new
```

The script also documents every switch's built-in default and environment variable offline:

```bash
docker run --rm ghcr.io/written2001/stash-sh:latest scan --help
docker run --rm ghcr.io/written2001/stash-sh:latest generate --help
```

## Targets

Supply at least one path, a nonempty generate ID selector, or explicit `--all`. Omitting targets is an error, not an implicit whole-library operation.

```bash
docker run --rm --env-file stash-sh.env ghcr.io/written2001/stash-sh:latest scan --all
docker run --rm --env-file stash-sh.env ghcr.io/written2001/stash-sh:latest generate --all
```

`--all` defaults to false and cannot be combined with paths or IDs, including targets from the environment. It submits no selectors so Stash applies its whole-library behavior. Be deliberate: whole-library generation can be expensive.

| Target | CLI | Environment | GraphQL field | Default |
| --- | --- | --- | --- | --- |
| Scan paths | Positional `PATH ...` | `STASH_SCAN_PATHS` | `paths` | Unset; target required |
| Generate paths | Positional `PATH ...` | `STASH_GENERATE_PATHS` | `paths` | Unset; target required |
| Scene IDs | Repeat `--scene-id ID` | `STASH_GENERATE_SCENE_IDS` | `sceneIDs` | Unset |
| Marker IDs | Repeat `--marker-id ID` | `STASH_GENERATE_MARKER_IDS` | `markerIDs` | Unset |
| Image IDs | Repeat `--image-id ID` | `STASH_GENERATE_IMAGE_IDS` | `imageIDs` | Unset |
| Gallery IDs | Repeat `--gallery-id ID` | `STASH_GENERATE_GALLERY_IDS` | `galleryIDs` | Unset |

Environment target lists must be JSON arrays of nonempty strings:

```dotenv
STASH_GENERATE_SCENE_IDS=["123","456"]
STASH_GENERATE_PATHS=["/media/new content"]
```

CLI paths replace the entire environment path list. Repeated CLI ID flags replace the environment list for that ID type and collect IDs in argument order; other ID types remain unchanged. Empty arrays are omitted and do not count as targets.

ID-only generation:

```bash
docker run --rm --env-file stash-sh.env ghcr.io/written2001/stash-sh:latest \
  generate --scene-id 123 --scene-id 456 --marker-id 789
```

Paths and different ID selector types can be combined. They are forwarded directly to Stash; Stash's mutation controls the resulting selection, including paths in addition to ID lists.

## Scan Options

All switches below are Boolean and also accept the corresponding `--no-` form, except `--min-mod-time`.

| CLI | Environment | GraphQL field | Built-in default |
| --- | --- | --- | --- |
| `--covers` | `STASH_SCAN_COVERS` | `scanGenerateCovers` | `true` |
| `--previews` | `STASH_SCAN_PREVIEWS` | `scanGeneratePreviews` | `true` |
| `--image-previews` | `STASH_SCAN_IMAGE_PREVIEWS` | `scanGenerateImagePreviews` | `true` |
| `--sprites` | `STASH_SCAN_SPRITES` | `scanGenerateSprites` | `true` |
| `--phashes` | `STASH_SCAN_PHASHES` | `scanGeneratePhashes` | `true` |
| `--image-phashes` | `STASH_SCAN_IMAGE_PHASHES` | `scanGenerateImagePhashes` | `true` |
| `--thumbnails` | `STASH_SCAN_THUMBNAILS` | `scanGenerateThumbnails` | `true` |
| `--clip-previews` | `STASH_SCAN_CLIP_PREVIEWS` | `scanGenerateClipPreviews` | `true` |
| `--rescan` | `STASH_SCAN_RESCAN` | `rescan` | `false` |
| `--min-mod-time TIMESTAMP` | `STASH_SCAN_MIN_MOD_TIME` | `filter.minModTime` | Unset |

`--rescan` includes unchanged files. `--min-mod-time` excludes files modified before the supplied timestamp. Use RFC3339 with a timezone; Stash validates its Timestamp scalar.

```bash
docker run --rm --env-file stash-sh.env ghcr.io/written2001/stash-sh:latest \
  scan --min-mod-time 2026-01-01T00:00:00Z --no-previews /media/new
```

## Generate Options

Every switch in this table is Boolean and accepts its corresponding `--no-` form.

| CLI | Environment | GraphQL field | Built-in default |
| --- | --- | --- | --- |
| `--covers` | `STASH_GENERATE_COVERS` | `covers` | `true` |
| `--sprites` | `STASH_GENERATE_SPRITES` | `sprites` | `true` |
| `--previews` | `STASH_GENERATE_PREVIEWS` | `previews` | `true` |
| `--image-previews` | `STASH_GENERATE_IMAGE_PREVIEWS` | `imagePreviews` | `true` |
| `--markers` | `STASH_GENERATE_MARKERS` | `markers` | `true` |
| `--marker-image-previews` | `STASH_GENERATE_MARKER_IMAGE_PREVIEWS` | `markerImagePreviews` | `true` |
| `--marker-screenshots` | `STASH_GENERATE_MARKER_SCREENSHOTS` | `markerScreenshots` | `true` |
| `--transcodes` | `STASH_GENERATE_TRANSCODES` | `transcodes` | `true` |
| `--phashes` | `STASH_GENERATE_PHASHES` | `phashes` | `true` |
| `--interactive-heatmaps-speeds` | `STASH_GENERATE_INTERACTIVE_HEATMAPS_SPEEDS` | `interactiveHeatmapsSpeeds` | `true` |
| `--image-phashes` | `STASH_GENERATE_IMAGE_PHASHES` | `imagePhashes` | `true` |
| `--image-thumbnails` | `STASH_GENERATE_IMAGE_THUMBNAILS` | `imageThumbnails` | `true` |
| `--clip-previews` | `STASH_GENERATE_CLIP_PREVIEWS` | `clipPreviews` | `true` |
| `--force-transcodes` | `STASH_GENERATE_FORCE_TRANSCODES` | `forceTranscodes` | `false` |
| `--overwrite` | `STASH_GENERATE_OVERWRITE` | `overwrite` | `false` |

`--transcodes` generates transcodes when Stash determines they are needed. `--force-transcodes` requests them even when not required; use it with transcoding enabled. `--overwrite` allows replacing existing generated media. Stash controls dependencies between output types and how these options affect existing media.

### Preview Settings

These flags set members of `previewOptions`. All are unset by default, preserving Stash's configured preview settings. Each takes a separate value.

| CLI | Environment | GraphQL field | Type |
| --- | --- | --- | --- |
| `--preview-segments` | `STASH_GENERATE_PREVIEW_SEGMENTS` | `previewOptions.previewSegments` | 32-bit integer |
| `--preview-segment-duration` | `STASH_GENERATE_PREVIEW_SEGMENT_DURATION` | `previewOptions.previewSegmentDuration` | Finite number, seconds |
| `--preview-exclude-start` | `STASH_GENERATE_PREVIEW_EXCLUDE_START` | `previewOptions.previewExcludeStart` | Duration string |
| `--preview-exclude-end` | `STASH_GENERATE_PREVIEW_EXCLUDE_END` | `previewOptions.previewExcludeEnd` | Duration string |
| `--preview-preset` | `STASH_GENERATE_PREVIEW_PRESET` | `previewOptions.previewPreset` | Enum |

Presets: `ultrafast`, `veryfast`, `fast`, `medium`, `slow`, `slower`, `veryslow`. Duration strings are interpreted by Stash, for example `10s`. Numeric types and enums are validated locally; Stash validates domain-specific values.

```bash
docker run --rm --env-file stash-sh.env ghcr.io/written2001/stash-sh:latest \
  generate --preview-segments 12 --preview-segment-duration 0.5 \
  --preview-exclude-start 10s --preview-exclude-end 5s --preview-preset fast /media/new
```

## Results And Failures

On successful submission, stdout contains only the returned job ID. Diagnostics go to stderr. Inspect the Stash job queue for execution progress and results; the helper does not wait or poll.

| Exit code | Meaning |
| --- | --- |
| `0` | Job accepted, or help displayed |
| `1` | Transport, HTTP, GraphQL, or response failure |
| `2` | Invalid command, arguments, environment configuration, or missing dependency |

Requests use JSON variables rather than interpolating paths into GraphQL. Connection timeout is 10 seconds; the total submission timeout is 60 seconds. No requests are automatically retried: a timed-out submission may already have queued a job, so check Stash before retrying manually. HTTP success with GraphQL errors is still treated as failure.

## Local Use And Development

Runtime dependencies: Bash 4.3+, `jq`, and `curl` 7.76+ (for `--fail-with-body`). Export environment variables yourself; the script does not load env-files.

```bash
export STASH_URL=http://localhost:9999/graphql
export STASH_APIKEY=your-stash-api-key
bash stash.sh scan /media/new
bash stash.sh generate --no-transcodes /media/new
```

Build locally:

```bash
docker build -t stash-sh:local .
docker run --rm --env-file stash-sh.env stash-sh:local scan /media/new
```

Validation requires ShellCheck in addition to the runtime dependencies. Tests use a mock HTTP transport and never contact your Stash server:

```bash
bash -n stash.sh tests/stash_test.sh
shellcheck stash.sh tests/stash_test.sh
bash tests/stash_test.sh
docker run --rm --entrypoint bash -v "$PWD/tests:/tests:ro" stash-sh:local /tests/stash_test.sh
```

CI runs syntax, lint, and behavior checks before publishing `latest` for `linux/amd64` and `linux/arm64`. The registry namespace follows the repository owner; this repository's target is `ghcr.io/written2001/stash-sh`.

API references: [metadata inputs](https://github.com/stashapp/stash/blob/v0.31.1/graphql/schema/types/metadata.graphql), [preview presets](https://github.com/stashapp/stash/blob/v0.31.1/graphql/schema/types/config.graphql), and [mutation signatures](https://github.com/stashapp/stash/blob/v0.31.1/graphql/schema/schema.graphql). Older Stash releases are not supported automatically; future schema changes require updating the helper.

## License

MIT, originally Copyright 2024 feederbox826. This project is derived from and inspired by [feederbox826/stash.sh](https://github.com/feederbox826/stash.sh). The original copyright notice, permission notice, and disclaimer are preserved in [LICENCE](LICENCE), also included at `/LICENCE` in the Docker image.
