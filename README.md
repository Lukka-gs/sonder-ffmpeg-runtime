# sonder-ffmpeg-runtime

A reproducible, auditable, minimal LGPL build of FFmpeg (`ffmpeg.exe` / `ffprobe.exe`) for Windows
x64, plus the scripts and CI pipeline used to build, verify, and package it.

## What this repository is NOT

**This repository does not contain the Sonder application.** There is no Rust/Tauri code, no
frontend, no database, no Cloudflare integration, and no proprietary Sonder logic here. This is a
standalone, general-purpose FFmpeg runtime that any project can consume independently -- it was
originally developed as part of Sonder's own build pipeline, but this repository contains only the
build system and documentation for the runtime itself, nothing about how any particular
application uses it.

## What this repository produces

Two executables for Windows x86_64:

- **`ffmpeg.exe`** -- transcodes video/audio.
- **`ffprobe.exe`** -- inspects container/stream metadata.

Built from official FFmpeg source, configured minimally: everything is disabled by default
(`--disable-everything`), and only the specific demuxers, decoders, encoders, parsers, filters, and
protocols actually needed are re-enabled one by one. See
[`docs/USAGE_MATRIX.md`](docs/USAGE_MATRIX.md) for the exact, justified list.

### Licensing summary

- **LGPL configuration**: built with `--enable-version3`, `--disable-gpl`, `--disable-nonfree`.
  No GPL-only or nonfree component is present -- confirmed empirically against the real compiled
  binary (`ffmpeg -buildconf`), not just by configure flags. See
  [`docs/VALIDATION_REPORT.md`](docs/VALIDATION_REPORT.md).
- **Video encoding**: `h264_mf` -- Windows' native Media Foundation H.264 encoder. No `libx264`
  (GPL) anywhere in this build.
- **Audio encoding**: FFmpeg's own native AAC encoder. No `libfdk_aac` (nonfree).
- **AV1 decoding**: via [`dav1d`](https://code.videolan.org/videolan/dav1d) (BSD-2-Clause), the
  **only** external library statically linked into this build. FFmpeg's own native `av1` decoder
  has no software decode path at all (it's hwaccel-only by upstream design) -- `dav1d` decodes AV1
  entirely in software, with no GPU dependency. See
  [`docs/USAGE_MATRIX.md`](docs/USAGE_MATRIX.md) section 6 for the full technical finding.

## Reproducing the build

```bash
cd build
docker build -t sonder-ffmpeg-runtime:build .
mkdir -p out
docker run --rm -v "$(pwd)/out:/out" sonder-ffmpeg-runtime:build
```

Full walkthrough, including how to prove two independent builds are byte-identical, in
[`docs/REPRODUCE.md`](docs/REPRODUCE.md).

## Verifying hashes

Every release publishes external SHA-256 sidecars (`*.sha256`) next to each artifact -- never
embedded inside a document that is itself part of the artifact (that would be a self-reference
paradox: updating the hash changes the file, which changes the artifact, which changes the hash
again, forever). Always verify against the sidecar file published alongside the release, e.g.:

```bash
sha256sum -c sonder-ffmpeg-windows-x64.zip.sha256
```

## Accessing the corresponding source code

This repository already **is** the corresponding source for the runtime it produces: `build/`
contains the exact build recipe (pinned FFmpeg commit, pinned dav1d tag, pinned toolchain
versions, pinned Debian snapshot), and `build/package-source.sh` produces a deterministic,
self-sufficient source package (`sonder-ffmpeg-source.tar.gz`) that bundles the original,
unmodified upstream tarballs alongside the build scripts and documentation -- reproducible from a
clean clone, with no dependency on anything outside this repository (beyond network access to the
pinned Debian snapshot and Docker base image, both digest/timestamp-pinned).

## No legal or patent warranty

This project makes **no legal warranty of any kind**, including but not limited to patent
non-infringement. H.264, HEVC, AAC, and other codecs implemented or invoked by this build may be
covered by patents in some jurisdictions; obtaining any necessary patent licenses for your use case
is your responsibility. This repository is provided "as is", with no warranty express or implied --
see [`LICENSE`](LICENSE) for the scripts/documentation and
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) for the upstream components' own disclaimers.

## No code signing

Artifacts produced by this repository (including any future GitHub Release) are **not digitally
signed**. Windows SmartScreen or antivirus software may flag unsigned executables. Verify the
SHA-256 checksum against the published sidecar before trusting a downloaded binary; there is
currently no Authenticode signature to validate instead.

## Repository layout

```
build/           Dockerfile, build.sh, package-source.sh, pinned configure flags and source lock
docs/            SBOM, build manifest, reproduction instructions, capability matrix, validation report
licenses/        Full upstream license texts (FFmpeg, dav1d, GCC, MinGW-w64 runtime)
scripts/         Node.js verification scripts used by CI
.github/workflows/  verify.yml (PR/push CI) and release.yml (manual-only, produces a workflow artifact)
```

## Status

This repository is being prepared for eventual publication as `Lukka-gs/sonder-ffmpeg-runtime`. It
has not yet been published, and no release has been made.
