#!/usr/bin/env node
// Testes de regressao para scripts/verify-forbidden-components.mjs. Sem
// nenhum framework externo (mesma filosofia zero-dependencia dos outros
// scripts de verificacao) -- so node:assert e as funcoes puras exportadas.
//
// Uso: node scripts/verify-forbidden-components.test.mjs
// Exit code 0 = todos os casos passaram. Exit code 1 = qualquer falha.

import assert from "node:assert/strict";
import {
  parseConfigTokens,
  checkForbiddenFlags,
  checkForbiddenComponents,
  checkLinkMapForbidden,
} from "./verify-forbidden-components.mjs";

const FORBIDDEN_FLAGS = ["--enable-gpl", "--enable-nonfree"];
const FORBIDDEN_COMPONENTS = ["libx264", "libx265", "libvpx", "libaom", "openssl", "gmp"];

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`OK: ${name}`);
  } catch (error) {
    failed += 1;
    console.error(`FAIL: ${name}`);
    console.error(`  ${error.message}`);
  }
}

// --- --enable-gpl rejeitado --------------------------------------------
test("--enable-gpl e rejeitado (token exato presente)", () => {
  const tokens = parseConfigTokens("configuration: --enable-gpl --disable-nonfree --enable-libdav1d");
  const found = checkForbiddenFlags(tokens, FORBIDDEN_FLAGS);
  assert.deepEqual(found, ["--enable-gpl"]);
});

// --- --disable-gpl aceito ------------------------------------------------
test("--disable-gpl e aceito (nao confundido com --enable-gpl)", () => {
  const tokens = parseConfigTokens("configuration: --disable-gpl --disable-nonfree --enable-libdav1d");
  const found = checkForbiddenFlags(tokens, FORBIDDEN_FLAGS);
  assert.deepEqual(found, []);
});

// --- --enable-libx264 rejeitado ------------------------------------------
test("--enable-libx264 e rejeitado (token exato presente)", () => {
  const tokens = parseConfigTokens("configuration: --disable-gpl --enable-libx264 --enable-libdav1d");
  const found = checkForbiddenComponents(tokens, FORBIDDEN_COMPONENTS);
  assert.equal(found.length, 1);
  assert.equal(found[0].component, "libx264");
  assert.equal(found[0].token, "--enable-libx264");
});

// --- --disable-libx264 aceito (a checagem exigida pela meta: nao pode ser
// confundido com --enable-libx264 so por conter a substring "libx264") -----
test("--disable-libx264 e aceito (substring 'libx264' presente, mas nao o token --enable-libx264)", () => {
  const tokens = parseConfigTokens("configuration: --disable-gpl --disable-libx264 --enable-libdav1d");
  const found = checkForbiddenComponents(tokens, FORBIDDEN_COMPONENTS);
  assert.deepEqual(found, []);
});

// --- biblioteca proibida no link map rejeitada ---------------------------
test("biblioteca proibida em texto de link map e rejeitada", () => {
  const fakeLinkMap = `
Archive member included because of file (symbol)

/build/x264-install/lib/libx264.a(common.o)
                              needed by ffmpeg.o
/build/dav1d-install/lib/libdav1d.a(msac.o)
`;
  const found = checkLinkMapForbidden(fakeLinkMap, FORBIDDEN_COMPONENTS);
  assert.deepEqual(found, ["libx264"]);
});

// --- link map sem nenhuma biblioteca proibida e aceito -------------------
test("link map sem componentes proibidos nao produz nenhum match", () => {
  const fakeLinkMap = `
/build/dav1d-install/lib/libdav1d.a(msac.o)
libmingwex.a(fwrite.o)
`;
  const found = checkLinkMapForbidden(fakeLinkMap, FORBIDDEN_COMPONENTS);
  assert.deepEqual(found, []);
});

// --- dav1d aceito (nunca esta na lista de proibidos; nem como flag de
// configuracao, nem no link map) ------------------------------------------
test("dav1d e aceito -- --enable-libdav1d nao e um componente proibido", () => {
  const tokens = parseConfigTokens("configuration: --disable-gpl --disable-nonfree --enable-libdav1d --enable-decoder=libdav1d");
  const foundInFlags = checkForbiddenComponents(tokens, FORBIDDEN_COMPONENTS);
  assert.deepEqual(foundInFlags, []);
  const fakeLinkMap = "/build/dav1d-install/lib/libdav1d.a(msac.o)\n";
  const foundInMap = checkLinkMapForbidden(fakeLinkMap, FORBIDDEN_COMPONENTS);
  assert.deepEqual(foundInMap, []);
});

console.log(`\n${passed} passaram, ${failed} falharam`);
if (failed > 0) {
  process.exitCode = 1;
  console.error("verify-forbidden-components.test: FALHOU");
} else {
  console.log("verify-forbidden-components.test: OK");
}
