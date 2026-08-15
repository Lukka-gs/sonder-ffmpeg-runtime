#!/usr/bin/env node
// Gera a entrada MINIMA e DETERMINISTICA (Y4M + WAV) usada pelo gate
// funcional obrigatorio (scripts/verify-functional.ps1). Nao depende de
// nenhum ffmpeg de sistema no runner -- os dois arquivos sao escritos byte
// a byte por este script, com formulas fixas (nunca Math.random, nunca o
// relogio), entao a saida e identica em toda execucao e em qualquer
// maquina.
//
// Y4M (YUV4MPEG2): container de video cru, sem nenhuma dependencia de
// encoder -- so um cabecalho de texto seguido de quadros brutos em 4:2:0.
// WAV: PCM linear, tambem sem nenhuma dependencia de encoder.
// O candidato ffmpeg.exe deste repositorio le os dois nativamente e os usa
// como entrada real para o teste de conversao obrigatorio.
//
// Uso:
//   node scripts/generate-baseline-fixture.mjs --out-dir <diretorio>
//
// Saida: <diretorio>/baseline.y4m e <diretorio>/baseline.wav
// Exit code 0 = os dois arquivos foram escritos com sucesso. Exit code 1 =
// qualquer falha (ex.: --out-dir ausente) -- nunca falha silenciosamente.

import { writeFileSync, mkdirSync } from "node:fs";
import { join } from "node:path";

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

// Quadro cinza neutro constante (Y=U=V=128) em todos os pixels e todos os
// quadros -- deliberadamente o padrao mais simples possivel que ainda e um
// video 4:2:0 valido, para minimizar qualquer dependencia de comportamento
// especifico de encoder/decoder.
function buildY4m(width, height, fps, frameCount) {
  const header = Buffer.from(
    `YUV4MPEG2 W${width} H${height} F${fps}:1 Ip A1:1 C420jpeg\n`,
    "ascii",
  );
  const ySize = width * height;
  const cSize = (width / 2) * (height / 2);
  const frameSize = ySize + 2 * cSize;
  const parts = [header];
  for (let f = 0; f < frameCount; f += 1) {
    parts.push(Buffer.from("FRAME\n", "ascii"));
    parts.push(Buffer.alloc(frameSize, 128));
  }
  return Buffer.concat(parts);
}

// Onda quadrada fixa (nao silencio, para exercitar o encoder AAC com
// amostras nao-triviais) gerada por uma formula pura -- deterministica.
function buildWav(sampleRate, durationSeconds) {
  const numSamples = Math.round(sampleRate * durationSeconds);
  const bytesPerSample = 2;
  const dataSize = numSamples * bytesPerSample;
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0, "ascii");
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8, "ascii");
  buffer.write("fmt ", 12, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); // PCM
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * bytesPerSample, 28);
  buffer.writeUInt16LE(bytesPerSample, 32);
  buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36, "ascii");
  buffer.writeUInt32LE(dataSize, 40);
  for (let i = 0; i < numSamples; i += 1) {
    const sample = i % 100 < 50 ? 3000 : -3000;
    buffer.writeInt16LE(sample, 44 + i * bytesPerSample);
  }
  return buffer;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const outDir = args["out-dir"];
  if (!outDir) {
    console.error("FAIL: --out-dir nao informado");
    process.exit(1);
  }
  mkdirSync(outDir, { recursive: true });

  const width = 64;
  const height = 64;
  const fps = 25;
  const frameCount = 10; // 0.4s
  const y4m = buildY4m(width, height, fps, frameCount);
  writeFileSync(join(outDir, "baseline.y4m"), y4m);

  const sampleRate = 8000;
  const durationSeconds = frameCount / fps;
  const wav = buildWav(sampleRate, durationSeconds);
  writeFileSync(join(outDir, "baseline.wav"), wav);

  console.log(
    `baseline.y4m: ${y4m.length} bytes (${width}x${height}, ${frameCount} quadros @ ${fps}fps)`,
  );
  console.log(
    `baseline.wav: ${wav.length} bytes (${sampleRate} Hz, ${durationSeconds}s, PCM 16-bit mono)`,
  );
}

main();
