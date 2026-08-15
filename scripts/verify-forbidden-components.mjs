#!/usr/bin/env node
// Fonte UNICA de verdade para "o que e proibido neste build": le
// docs/BUILD_MANIFEST.json (forbiddenCheck.forbiddenConfigureFlags e
// forbiddenCheck.forbiddenComponents) -- nunca mantem uma segunda lista
// manual em nenhum script/workflow. Qualquer mudanca na politica de
// componentes proibidos entra SO no manifesto; este script (e quem o chama)
// nunca precisa ser editado por causa disso.
//
// Compara flags de configuracao como TOKENS EXATOS (nunca substring) --
// "--disable-libx264" NUNCA e confundido com "--enable-libx264": o texto de
// `-buildconf` e dividido em tokens por espaco, e a comparacao e igualdade
// exata de string contra cada token, nunca `.includes()`/regex solto sobre
// o texto inteiro.
//
// Tambem verifica os DOIS link maps (ffmpeg-link.map e ffprobe-link.map)
// contra a mesma lista de componentes proibidos -- um componente pode estar
// ausente da linha de configuracao e ainda assim ter sido linkado por outro
// caminho (ex.: dependencia transitiva de pkg-config); o link map e a prova
// real do que foi incorporado (ver docs/SBOM.md).
//
// Uso (CLI):
//   node scripts/verify-forbidden-components.mjs \
//     --manifest docs/BUILD_MANIFEST.json \
//     --buildconf-file <arquivo com a saida real de 'ffmpeg -buildconf'> \
//     --ffmpeg-link-map <path> --ffprobe-link-map <path>
//
// Exit code 0 = nenhum componente proibido encontrado em nenhuma das tres
// fontes (configure flags, link map do ffmpeg, link map do ffprobe). Exit
// code 1 = qualquer proibicao violada.
//
// As funcoes abaixo tambem sao exportadas para uso direto por
// scripts/verify-forbidden-components.test.mjs (testes de regressao, sem
// nenhum framework externo).

import { readFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export function parseConfigTokens(buildconfText) {
  // `ffmpeg -buildconf` imprime uma linha "configuration: --flag1 --flag2 ...".
  // Se o prefixo "configuration:" estiver presente, so o que vem depois dele
  // e considerado (evita tratar texto de banner/versao como token de flag).
  const marker = "configuration:";
  const idx = buildconfText.indexOf(marker);
  const relevant = idx >= 0 ? buildconfText.slice(idx + marker.length) : buildconfText;
  return relevant
    .split(/\s+/)
    .map((t) => t.trim())
    .filter(Boolean);
}

export function checkForbiddenFlags(tokens, forbiddenConfigureFlags) {
  const tokenSet = new Set(tokens);
  const found = [];
  for (const flag of forbiddenConfigureFlags) {
    if (tokenSet.has(flag)) found.push(flag);
  }
  return found;
}

export function checkForbiddenComponents(tokens, forbiddenComponents) {
  // Um componente proibido "X" so conta como efetivamente HABILITADO se o
  // token EXATO "--enable-X" estiver presente -- "--disable-X" (mesmo
  // contendo a substring "X") nunca e um match, porque a comparacao e
  // contra o token inteiro, nao um regex/substring sobre o texto todo.
  const tokenSet = new Set(tokens);
  const found = [];
  for (const component of forbiddenComponents) {
    const enableToken = `--enable-${component}`;
    if (tokenSet.has(enableToken)) found.push({ component, token: enableToken });
  }
  return found;
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function checkLinkMapForbidden(linkMapText, forbiddenComponents) {
  // Delimitadores nao-alfanumericos nos dois lados (ou inicio/fim de linha)
  // -- evita que um componente proibido curto combine parcialmente com um
  // nome de arquivo/simbolo maior que so contem a substring por acidente.
  const found = [];
  for (const component of forbiddenComponents) {
    const pattern = new RegExp(`(^|[^a-zA-Z0-9_])${escapeRegex(component)}([^a-zA-Z0-9_]|$)`, "i");
    if (pattern.test(linkMapText)) found.push(component);
  }
  return found;
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (token.startsWith("--")) {
      args[token.slice(2)] = argv[i + 1];
      i += 1;
    }
  }
  return args;
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
    fail(`${label} nao foi informado (argumento ausente)`);
    return false;
  }
  if (!existsSync(path)) {
    fail(`${label} nao existe: ${path}`);
    return false;
  }
  return true;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const manifestPath = args["manifest"];
  const buildconfFile = args["buildconf-file"];
  const ffmpegLinkMap = args["ffmpeg-link-map"];
  const ffprobeLinkMap = args["ffprobe-link-map"];

  if (!requireFile(manifestPath, "--manifest")) return;
  if (!requireFile(buildconfFile, "--buildconf-file")) return;
  if (!requireFile(ffmpegLinkMap, "--ffmpeg-link-map")) return;
  if (!requireFile(ffprobeLinkMap, "--ffprobe-link-map")) return;

  const manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  const forbiddenConfigureFlags = manifest?.forbiddenCheck?.forbiddenConfigureFlags;
  const forbiddenComponents = manifest?.forbiddenCheck?.forbiddenComponents;
  if (!Array.isArray(forbiddenConfigureFlags) || !Array.isArray(forbiddenComponents)) {
    fail(
      `${manifestPath} nao tem forbiddenCheck.forbiddenConfigureFlags/forbiddenComponents (arrays) -- fonte unica de verdade ausente ou malformada`,
    );
    return;
  }

  const buildconfText = readFileSync(buildconfFile, "utf8");
  const tokens = parseConfigTokens(buildconfText);
  if (tokens.length === 0) {
    fail(`${buildconfFile} nao contem nenhum token de configuracao reconhecivel`);
    return;
  }

  const badFlags = checkForbiddenFlags(tokens, forbiddenConfigureFlags);
  if (badFlags.length > 0) {
    fail(`flags de configuracao proibidas encontradas (token exato): ${badFlags.join(", ")}`);
  } else {
    ok(`nenhuma das ${forbiddenConfigureFlags.length} flags proibidas encontrada na configuracao (comparacao por token exato)`);
  }

  const badComponents = checkForbiddenComponents(tokens, forbiddenComponents);
  if (badComponents.length > 0) {
    fail(
      `componentes proibidos efetivamente HABILITADOS na configuracao: ${badComponents.map((c) => c.token).join(", ")}`,
    );
  } else {
    ok(`nenhum dos ${forbiddenComponents.length} componentes proibidos habilitado na configuracao (token --enable-<componente> exato)`);
  }

  const ffmpegMapText = readFileSync(ffmpegLinkMap, "utf8");
  const ffprobeMapText = readFileSync(ffprobeLinkMap, "utf8");
  const badInFfmpegMap = checkLinkMapForbidden(ffmpegMapText, forbiddenComponents);
  const badInFfprobeMap = checkLinkMapForbidden(ffprobeMapText, forbiddenComponents);
  if (badInFfmpegMap.length > 0) {
    fail(`componentes proibidos encontrados em ffmpeg-link.map: ${badInFfmpegMap.join(", ")}`);
  } else {
    ok("nenhum componente proibido encontrado em ffmpeg-link.map");
  }
  if (badInFfprobeMap.length > 0) {
    fail(`componentes proibidos encontrados em ffprobe-link.map: ${badInFfprobeMap.join(", ")}`);
  } else {
    ok("nenhum componente proibido encontrado em ffprobe-link.map");
  }

  if (process.exitCode === 1) {
    console.error("\nverify-forbidden-components: FALHOU");
  } else {
    console.log("\nverify-forbidden-components: OK");
  }
}

const isMainModule =
  process.argv[1] &&
  resolve(fileURLToPath(import.meta.url)).toLowerCase() === resolve(process.argv[1]).toLowerCase();
if (isMainModule) {
  main();
}
