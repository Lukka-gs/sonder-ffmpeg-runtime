#!/usr/bin/env node
// Verifies ffmpeg.exe/ffprobe.exe and (optionally) their link maps.
// No dependencies beyond Node's own standard library -- deliberately, to
// avoid any supply-chain risk in a script that runs as part of the
// integrity-verification pipeline itself.
//
// Usage:
//   node scripts/verify-artifacts.mjs \
//     --ffmpeg <path> --ffprobe <path> \
//     [--sha256sums <path>] \
//     [--ffmpeg-link-map <path>] [--ffprobe-link-map <path>]
//
// Exit code 0 = all requested checks passed. Exit code 1 = any check
// failed. Never silently skips a check that was explicitly requested via
// a CLI argument.

import { createHash } from "node:crypto";
import { readFileSync, existsSync } from "node:fs";
import { basename } from "node:path";

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const value = argv[i + 1];
    args[key] = value;
    i += 1;
  }
  return args;
}

function sha256File(path) {
  const data = readFileSync(path);
  return createHash("sha256").update(data).digest("hex");
}

function fail(message) {
  console.error(`FAIL: ${message}`);
  process.exitCode = 1;
}

function ok(message) {
  console.log(`OK: ${message}`);
}

function requireFile(path, label) {
  if (!path) {
    fail(`${label} não foi informado (argumento ausente)`);
    return false;
  }
  if (!existsSync(path)) {
    fail(`${label} não existe: ${path}`);
    return false;
  }
  return true;
}

function parseSha256Sums(path) {
  // Formato padrao de `sha256sum`: "<hash>  <arquivo>" por linha.
  const text = readFileSync(path, "utf8");
  const map = new Map();
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line) continue;
    const match = line.match(/^([0-9a-fA-F]{64})\s+\*?(.+)$/);
    if (!match) continue;
    const [, hash, file] = match;
    map.set(basename(file.trim()), hash.toLowerCase());
  }
  return map;
}

function main() {
  const args = parseArgs(process.argv.slice(2));

  const ffmpegPath = args["ffmpeg"];
  const ffprobePath = args["ffprobe"];

  if (!requireFile(ffmpegPath, "--ffmpeg") || !requireFile(ffprobePath, "--ffprobe")) {
    return;
  }

  const ffmpegHash = sha256File(ffmpegPath);
  const ffprobeHash = sha256File(ffprobePath);
  console.log(`ffmpeg.exe  sha256=${ffmpegHash}`);
  console.log(`ffprobe.exe sha256=${ffprobeHash}`);

  if (args["sha256sums"]) {
    if (!requireFile(args["sha256sums"], "--sha256sums")) return;
    const expected = parseSha256Sums(args["sha256sums"]);
    const expectedFfmpeg = expected.get(basename(ffmpegPath));
    const expectedFfprobe = expected.get(basename(ffprobePath));
    if (!expectedFfmpeg) {
      fail(`SHA256SUMS não contém uma entrada para ${basename(ffmpegPath)}`);
    } else if (expectedFfmpeg !== ffmpegHash) {
      fail(
        `SHA-256 de ffmpeg.exe não bate. esperado=${expectedFfmpeg} obtido=${ffmpegHash}`,
      );
    } else {
      ok("SHA-256 de ffmpeg.exe confere com SHA256SUMS.txt");
    }
    if (!expectedFfprobe) {
      fail(`SHA256SUMS não contém uma entrada para ${basename(ffprobePath)}`);
    } else if (expectedFfprobe !== ffprobeHash) {
      fail(
        `SHA-256 de ffprobe.exe não bate. esperado=${expectedFfprobe} obtido=${ffprobeHash}`,
      );
    } else {
      ok("SHA-256 de ffprobe.exe confere com SHA256SUMS.txt");
    }
  }

  const ffmpegMapPath = args["ffmpeg-link-map"];
  const ffprobeMapPath = args["ffprobe-link-map"];
  if (ffmpegMapPath || ffprobeMapPath) {
    if (!requireFile(ffmpegMapPath, "--ffmpeg-link-map")) return;
    if (!requireFile(ffprobeMapPath, "--ffprobe-link-map")) return;

    const ffmpegMap = readFileSync(ffmpegMapPath, "utf8");
    const ffprobeMap = readFileSync(ffprobeMapPath, "utf8");

    const checks = [
      [ffmpegMap.includes("fftools/ffmpeg.o"), "ffmpeg-link.map contém fftools/ffmpeg.o"],
      [
        !ffmpegMap.includes("fftools/ffprobe.o"),
        "ffmpeg-link.map NÃO contém fftools/ffprobe.o",
      ],
      [
        ffprobeMap.includes("fftools/ffprobe.o"),
        "ffprobe-link.map contém fftools/ffprobe.o",
      ],
      [
        !ffprobeMap.includes("fftools/ffmpeg.o"),
        "ffprobe-link.map NÃO contém fftools/ffmpeg.o",
      ],
      [ffmpegMap !== ffprobeMap, "os dois link maps NÃO são idênticos"],
    ];
    for (const [passed, label] of checks) {
      if (passed) ok(label);
      else fail(label);
    }
  }

  if (process.exitCode === 1) {
    console.error("\nverify-artifacts: FALHOU");
  } else {
    console.log("\nverify-artifacts: OK");
  }
}

main();
