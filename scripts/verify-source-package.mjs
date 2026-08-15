#!/usr/bin/env node
// Verifies the deterministic source-code package (sonder-ffmpeg-source.tar.gz):
// - external sidecar checksum matches the actual file;
// - two packages (e.g. from two independent builds) are byte-identical;
// - no file inside the package contains a self-referencing hash of the
//   package itself (the paradox: a document included IN the package that
//   records the package's OWN hash can never converge, since updating the
//   hash changes the document, which changes the package, which changes
//   the hash again).
//
// No dependencies beyond Node's own standard library and the system `tar`
// binary (invoked with structured argv, never a shell string) -- kept
// deliberately dependency-free for a script that is itself part of the
// integrity-verification pipeline.
//
// Usage:
//   node scripts/verify-source-package.mjs --package <path> \
//     [--sidecar <path>] \
//     [--compare-with <other-package-path>] \
//     [--check-self-reference]
//
// Exit code 0 = all requested checks passed. Exit code 1 = any check
// failed.

import { createHash } from "node:crypto";
import { readFileSync, existsSync, mkdtempSync, rmSync, readdirSync, statSync } from "node:fs";
import { basename, join, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

function parseArgs(argv) {
  const args = { "check-self-reference": false };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    if (key === "check-self-reference") {
      args[key] = true;
      continue;
    }
    args[key] = argv[i + 1];
    i += 1;
  }
  return args;
}

function sha256File(path) {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
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

// Lista os membros do tar de forma estruturada (argv, nunca shell) --
// protege contra path traversal ao extrair depois (nunca confia em nomes
// de entrada com `..` ou caminho absoluto).
function listTarMembers(tarPath) {
  const result = spawnSync("tar", ["--force-local", "-tzf", tarPath], { encoding: "utf8" });
  if (result.status !== 0) {
    throw new Error(`tar -tzf falhou (exit ${result.status}): ${result.stderr}`);
  }
  return result.stdout.split(/\r?\n/).filter(Boolean);
}

function assertSafeMembers(members, tarPath) {
  for (const member of members) {
    if (member.startsWith("/") || member.includes("..")) {
      throw new Error(
        `entrada insegura no tar (${tarPath}): "${member}" -- possível path traversal, extração recusada`,
      );
    }
  }
}

function extractTar(tarPath) {
  const members = listTarMembers(tarPath);
  assertSafeMembers(members, tarPath);
  const dest = mkdtempSync(join(tmpdir(), "verify-source-package-"));
  // `cwd` (opcao do proprio spawnSync, resolvida pelo Node antes de invocar
  // o processo) em vez de `-C <dest>` como argumento de string -- evita
  // qualquer ambiguidade de tradução de caminho (ex.: tar do Git Bash no
  // Windows interpretando "C:\..." como sintaxe de host remoto) entre
  // Node (caminhos nativos do Windows) e uma instalação MSYS/Cygwin de
  // `tar`. `--force-local` tambem mantido como defesa em profundidade para
  // o argumento de ENTRADA (tarPath), que ainda precisa ser passado como
  // string.
  const result = spawnSync("tar", ["--force-local", "-xzf", resolve(tarPath)], {
    encoding: "utf8",
    cwd: dest,
  });
  if (result.status !== 0) {
    rmSync(dest, { recursive: true, force: true });
    throw new Error(`tar -xzf falhou (exit ${result.status}): ${result.stderr}`);
  }
  return dest;
}

function walkFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) out.push(...walkFiles(full));
    else out.push(full);
  }
  return out;
}

function isTextFile(path) {
  return /\.(md|json|txt|sh|mjs|yml|yaml)$/i.test(path);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const packagePath = args["package"];
  if (!requireFile(packagePath, "--package")) return;

  const packageHash = sha256File(packagePath);
  console.log(`pacote: ${packagePath}`);
  console.log(`sha256: ${packageHash}`);

  if (args["sidecar"]) {
    if (!requireFile(args["sidecar"], "--sidecar")) return;
    const sidecarText = readFileSync(args["sidecar"], "utf8").trim();
    const match = sidecarText.match(/^([0-9a-fA-F]{64})\s+\*?([^\r\n]+)$/);
    if (!match) {
      fail(`sidecar (${args["sidecar"]}) não contém um registro sha256sum completo`);
    } else if (match[1].toLowerCase() !== packageHash) {
      fail(
        `sidecar não confere com o pacote real. sidecar=${match[1]} pacote=${packageHash}`,
      );
    } else if (match[2].trim() !== basename(packagePath)) {
      fail(
        `sidecar não é portátil. esperado=${basename(packagePath)} registrado=${match[2].trim()}`,
      );
    } else {
      ok("sidecar externo confere e referencia somente o nome portátil do pacote");
    }
  }

  if (args["compare-with"]) {
    if (!requireFile(args["compare-with"], "--compare-with")) return;
    const otherHash = sha256File(args["compare-with"]);
    if (otherHash !== packageHash) {
      fail(
        `pacotes divergem. ${packagePath}=${packageHash} ${args["compare-with"]}=${otherHash}`,
      );
    } else {
      ok(`pacotes idênticos (${packageHash})`);
    }

    const membersA = listTarMembers(packagePath);
    const membersB = listTarMembers(args["compare-with"]);
    const orderMatches =
      membersA.length === membersB.length && membersA.every((m, i) => m === membersB[i]);
    if (orderMatches) {
      ok("ordem dos membros do tar é idêntica entre os dois pacotes");
    } else {
      fail("ordem dos membros do tar DIVERGE entre os dois pacotes");
    }
  }

  if (args["check-self-reference"]) {
    let extractDir;
    try {
      extractDir = extractTar(packagePath);
      const suspiciousHashPattern = /[0-9a-f]{64}/i;
      let foundSelfReference = false;
      for (const file of walkFiles(extractDir)) {
        if (!isTextFile(file)) continue;
        const content = readFileSync(file, "utf8");
        // O pacote nao pode conter, em nenhum arquivo texto embutido nele
        // mesmo, o proprio hash SHA-256 do .tar.gz que o contem -- isso
        // seria a autorreferencia (paradoxo) que este verificador existe
        // para detectar.
        if (content.includes(packageHash)) {
          fail(
            `autorreferência detectada: ${file.replace(extractDir + sep, "")} contém o próprio SHA-256 do pacote`,
          );
          foundSelfReference = true;
        }
      }
      if (!foundSelfReference) {
        ok("nenhum arquivo dentro do pacote contém o hash do próprio pacote (sem autorreferência)");
      }
      // Verificacao adicional, mais ampla: nenhum arquivo de texto deveria
      // conter QUALQUER string de 64 caracteres hex imediatamente ao lado
      // de "sonder-ffmpeg-source.tar.gz" -- sinal de um hash historico
      // deixado para tras mesmo que nao seja o hash ATUAL (documentacao
      // desatualizada e igualmente um problema).
      for (const file of walkFiles(extractDir)) {
        if (!isTextFile(file)) continue;
        const content = readFileSync(file, "utf8");
        const lines = content.split(/\r?\n/);
        for (const line of lines) {
          if (
            line.toLowerCase().includes("sonder-ffmpeg-source.tar.gz") &&
            suspiciousHashPattern.test(line) &&
            !line.includes("sha256Note") &&
            !line.includes("sha256SidecarFile") &&
            !line.includes("sidecar")
          ) {
            fail(
              `possível hash obsoleto do próprio pacote em ${file.replace(extractDir + sep, "")}: "${line.trim()}"`,
            );
          }
        }
      }
    } catch (error) {
      fail(String(error.message || error));
    } finally {
      if (extractDir) rmSync(extractDir, { recursive: true, force: true });
    }
  }

  if (process.exitCode === 1) {
    console.error("\nverify-source-package: FALHOU");
  } else {
    console.log("\nverify-source-package: OK");
  }
}

main();
