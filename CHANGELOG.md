# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

Initial extraction of the reproducible minimal LGPL FFmpeg + dav1d build into its own,
independent repository. No release has been published yet.

### Added

- `build/` -- Dockerfile, `build.sh`, `package-source.sh`, pinned `configure-flags.txt` and
  `sources.lock.json` for a reproducible, minimal, LGPL-only FFmpeg + dav1d build for Windows x64.
- `docs/` -- SBOM (with real link-map proof), structured build manifest, reproduction
  instructions, capability matrix, and validation report.
- `licenses/` -- full, unmodified upstream license texts for FFmpeg (LGPLv3/GPLv3), dav1d
  (BSD-2-Clause), the GCC Runtime Library Exception, and the MinGW-w64 runtime.
- `.github/workflows/verify.yml` -- CI pipeline: Linux job builds twice and compares binaries,
  link maps, and source packages byte-for-byte; Windows job downloads the Linux artifacts and runs
  the shared functional verification gate (`scripts/verify-functional.ps1`).
- `.github/workflows/release.yml` -- manual-only (`workflow_dispatch`, no tag trigger) pipeline
  that reuses the same verify gates and the same shared functional verification script, then
  assembles a release candidate (deterministic ZIP, corresponding-source package, SBOM, notices)
  as a workflow artifact only. It does not publish a GitHub Release and grants no job
  `contents: write` in its current form.
- `scripts/verify-artifacts.mjs`, `scripts/verify-source-package.mjs` -- Node.js verification
  helpers used by CI.
- `scripts/verify-functional.ps1` -- shared Windows functional verification gate, called
  identically by both workflows: SHA-256/link-map checks, manifest-driven forbidden-component
  checks, `-encoders` checks, and a mandatory baseline conversion test using a programmatically
  generated Y4M+WAV input (no dependency on a system `ffmpeg` being present on the runner). An
  additional, clearly optional codec/container matrix runs only if a system `ffmpeg` happens to be
  available, and never fails the gate.
- `scripts/generate-baseline-fixture.mjs` -- deterministic Y4M+WAV generator used by the
  mandatory baseline test above.
- `scripts/verify-forbidden-components.mjs` -- reads `docs/BUILD_MANIFEST.json`
  (`forbiddenCheck.forbiddenConfigureFlags`/`forbiddenComponents`) as the single source of truth
  for what is prohibited, and checks it against the real `-buildconf` output (exact-token
  comparison, so `--disable-libx264` is never confused with `--enable-libx264`) and both link maps.
  No second, manually maintained list exists anywhere else.
- `scripts/verify-forbidden-components.test.mjs` -- zero-dependency regression tests for the
  checker above.
- `build/make-release-zip.sh` -- shared deterministic ZIP builder (normalizes locale, timezone,
  timestamps, and permissions before compressing) used by `release.yml` to build the release ZIP
  twice, in independent directories, and confirm the two outputs are byte-for-byte identical
  before an external SHA-256 sidecar is generated.

### Fixed

- The mandatory functional baseline (Y4M+WAV) was being rejected by the real candidate binary
  (`Invalid data found when processing input`) because only the `mov` and `matroska` demuxers were
  enabled. Added `--enable-demuxer=yuv4mpegpipe`, `--enable-demuxer=wav`, and
  `--enable-decoder=rawvideo` (decode-only, no external library, no GPL/nonfree component) to
  `build/configure-flags.txt`. Confirmed against a real rebuild, not just by inspection -- see
  `docs/VALIDATION_REPORT.md` section 1.5.
- `verify.yml`/`release.yml` generated the second independent source package by re-reading `out1`'s
  build evidence instead of `out2`'s, which only proved the packaging script was deterministic
  given the same input twice -- never that the two independent builds produced equivalent source
  evidence. Fixed to read each generation from its own build output, plus an explicit `cmp` of
  `out1`/`out2`'s `sources/*.tar.gz` and `*-changes.diff`.

### Known limitations

- AV1 decoding depends on `dav1d` (the only external library in this build) since FFmpeg's own
  native `av1` decoder has no software decode path.
- No code signing is applied to any artifact.
- No legal or patent review has been performed; see `README.md` for the explicit disclaimer.
