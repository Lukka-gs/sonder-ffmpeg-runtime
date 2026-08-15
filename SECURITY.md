# Security Policy

## Reporting a vulnerability

If you find a security issue in this repository's build scripts, CI workflows, or in the way
upstream FFmpeg/dav1d sources are fetched and verified here, please open a private security
advisory on GitHub (once this repository is published) rather than a public issue. Do not disclose
details publicly until a fix is available.

This repository does not currently have a dedicated security contact email. Until one is
established, use GitHub's private vulnerability reporting feature on the repository once it is
published.

## Scope

This policy covers:

- `build/` (Dockerfile, build.sh, package-source.sh, configure-flags.txt) and the reproducibility
  guarantees they make;
- `.github/workflows/` (verify.yml, release.yml) and their permissions;
- `scripts/` (Node.js verification scripts).

It does **not** cover vulnerabilities in FFmpeg or dav1d themselves -- report those upstream:

- FFmpeg: <https://ffmpeg.org/security.html>
- dav1d: <https://code.videolan.org/videolan/dav1d/-/security/policy>

This build tracks specific pinned commits/tags of both projects (see
[`build/sources.lock.json`](build/sources.lock.json)); a security fix upstream requires this
repository to be updated to a newer pinned version before it takes effect here.

## Supply-chain integrity guarantees

- Every source download (FFmpeg, dav1d) is fixed by immutable URL + SHA-256, verified before
  extraction -- never `latest`, never an unpinned branch.
- The Docker base image is pinned by digest.
- The APT package repository is pinned to an immutable `snapshot.debian.org` timestamp, with every
  installed package version fixed explicitly (`apt-get install package=version`) -- the base image
  digest alone does not pin the package repository's contents.
- No `curl | bash` pattern is used anywhere in this repository.
- GitHub Actions workflows request only `contents: read` in every job of both workflows. Neither
  `verify.yml` nor `release.yml` grants `contents: write` anywhere -- `release.yml` only produces a
  release candidate as a workflow artifact (ZIP, checksums, source package, SBOM, notices) and does
  not publish a GitHub Release in its current form.
- Third-party GitHub Actions are pinned by commit SHA where practical.

## No code signing

Binaries produced by this repository are not digitally signed (no Authenticode signature). Always
verify the published SHA-256 checksum against the external `.sha256` sidecar file before trusting
a downloaded artifact.
