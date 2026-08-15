# Third-Party Notices

This repository redistributes and builds software from multiple upstream projects, each under its
own license. **No single license applies to everything in this repository or in the binaries it
produces** -- this document lists every component and its own, unmodified license terms.

## This repository's own scripts and documentation

Copyright (c) 2026 Lucca G. Soares. Licensed under the **MIT License** -- see [`LICENSE`](LICENSE).
This covers `build/`, `scripts/`, `.github/workflows/`, and the Markdown/JSON documentation
authored in this repository. It does **not** cover FFmpeg, dav1d, or any compiled binary --see
below.

## FFmpeg

- **License**: LGPL-3.0-or-later.
- **Commit**: pinned exactly in [`build/sources.lock.json`](build/sources.lock.json) and
  [`docs/BUILD_MANIFEST.json`](docs/BUILD_MANIFEST.json).
- **Configuration**: built with `--enable-version3 --disable-gpl --disable-nonfree` -- no GPL-only
  component, no nonfree component. Confirmed against the compiled binary's own
  `ffmpeg -buildconf` output (see [`docs/VALIDATION_REPORT.md`](docs/VALIDATION_REPORT.md)), not
  just the configure flags used to request it.
- **Modifications**: none. `build/build.sh` generates `*-changes.diff` from a pristine,
  hash-verified checkout on every build -- always empty, proving no patch was applied.
- **License text**: [`licenses/FFmpeg/COPYING.LGPLv3`](licenses/FFmpeg/COPYING.LGPLv3) (verbatim
  from gnu.org). [`licenses/FFmpeg/COPYING.GPLv3`](licenses/FFmpeg/COPYING.GPLv3) is included for
  reference (the LGPL incorporates GPL terms by reference) but does not apply to this build, since
  `--enable-gpl` is never used.
- **Corresponding source**: `build/package-source.sh` produces a self-sufficient source package
  bundling the exact, unmodified FFmpeg tarball used, alongside the build scripts that produced the
  binaries -- see [`docs/REPRODUCE.md`](docs/REPRODUCE.md).

## dav1d -- the only external codec library in this build

- **License**: BSD-2-Clause.
- **Copyright**: © 2018-2025, VideoLAN and dav1d authors.
- **Version**: pinned exactly in `build/sources.lock.json`.
- **Reason for inclusion**: FFmpeg's own native `av1` decoder has no software decode path -- it is
  a dispatcher exclusively for hardware acceleration (D3D11VA/DXVA2/NVDEC/VAAPI/VDPAU/
  VideoToolbox/Vulkan/D3D12VA depending on platform), confirmed by reading the upstream source
  itself. `dav1d` is the only way to decode AV1 in software, with no GPU dependency, without adding
  a GPL-licensed dependency. See [`docs/USAGE_MATRIX.md`](docs/USAGE_MATRIX.md) section 6 for the
  full technical finding.
- **Modifications**: none. Same `*-changes.diff` mechanism as FFmpeg, always empty.
- **License text**: [`licenses/dav1d/COPYING`](licenses/dav1d/COPYING) (verbatim from the official
  repository).

## MinGW-w64 runtime (statically linked)

The cross-compilation toolchain's C runtime (`libmingwex`/`libmingw32`/`libmoldname`) and POSIX
threads support (`libwinpthread`, `posix` variant) are statically linked into `ffmpeg.exe` and
`ffprobe.exe`.

- **License**: Zope Public License (ZPL) 2.1, with parts marked Public Domain/BSD/LGPL depending on
  the file -- certified open source and GPL-compatible by the FSF.
- **License text**:
  [`licenses/MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt`](licenses/MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt)
  (verbatim from the official mingw-w64 repository).

## GCC runtime support (statically linked)

`libgcc`/`libgcc_eh`/`libatomic` -- low-level compiler-generated helpers (64-bit integer division,
C++ exception unwinding used internally by FFmpeg, atomic operations) -- are statically linked.

- **License**: GPL-3.0-or-later **with the GCC Runtime Library Exception**, which explicitly
  permits static linking into binaries under any license (including this LGPL build) without
  propagating GPL obligations to the linked binary.
- **License text**:
  [`licenses/GCC/RUNTIME.LIBRARY.EXCEPTION`](licenses/GCC/RUNTIME.LIBRARY.EXCEPTION) (verbatim from
  gnu.org).

## Full inventory and proof

See [`docs/SBOM.md`](docs/SBOM.md) for the complete bill of materials, including link-map-derived
proof (not just `objdump -p`, which only proves the absence of *dynamic* DLL dependencies, never
static libraries) of exactly which object files and static archives were incorporated into each
binary.

## No warranty, no patent grant

None of the components listed above, nor this repository's own scripts, come with any warranty --
express or implied -- including fitness for a particular purpose or non-infringement. Some codecs
implemented or invoked by this build (H.264, HEVC, AAC, and others) may be covered by patents in
some jurisdictions. Obtaining any necessary patent licenses is the responsibility of whoever
deploys or distributes binaries built from this repository.
