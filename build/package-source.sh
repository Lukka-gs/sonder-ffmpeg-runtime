#!/usr/bin/env bash
# Monta o pacote deterministico de codigo-fonte correspondente
# (LGPL "corresponding source" + auditabilidade completa), rodando no
# HOST (nunca dentro do container de build) porque precisa alcancar tanto
# build/ (contexto do Docker) quanto docs/ e licenses/ (SBOM, manifesto,
# instrucoes de reproducao, textos de licenca) -- os tres nao cabem no
# MESMO contexto de `docker build` (Docker nunca alcanca fora do
# diretorio de contexto), entao montar isso DENTRO do container geraria
# um pacote incompleto por construcao.
#
# Uso:
#   ./package-source.sh <arquivo-de-saida.tar.gz> [OUT_DIR-com-changes.diff]
#
# Os tarballs de fonte vem de `$SRC_OUT_DIR/sources/` (populado por
# `build.sh`, que os copia para `$OUT_DIR/sources/` DEPOIS de verificar o
# SHA-256 -- ver build.sh) -- ou, se ausentes ali, este script os baixa
# diretamente das URLs fixadas em `sources.lock.json`, verificando o
# SHA-256 de novo antes de empacotar (defesa em profundidade: nunca confia
# em nenhum arquivo sem reconferir o hash, mesmo um que ja foi verificado
# por `build.sh`).
#
# O pacote extraido e AUTOSSUFICIENTE: contem os dois tarballs de fonte
# originais (FFmpeg/dav1d, verificados por SHA-256), o Dockerfile, o
# build.sh, configure-flags.txt, sources.lock.json, o cross-file do meson,
# os dois changes.diff, licencas, SBOM, BUILD_MANIFEST.json, REPRODUCE.md,
# README.md, LICENSE e THIRD_PARTY_NOTICES.md -- rodar `docker build .`
# dentro da pasta extraida `build/` reproduz o build sem precisar de mais
# nada do repositorio original (o Dockerfile ali dentro usa a copia
# vendorizada de sources/, sem precisar de rede para as fontes).
set -euo pipefail

# Regenerar o pacote em ambientes com locale diferente (ex.: uma sessao
# com C.UTF-8 vs o Git Bash do Windows com pt_BR.UTF-8) produzia hashes
# DIFERENTES apesar do conteudo interno ser identico -- a ORDEM dos
# membros dentro do `.tar.gz` divergia, porque `sort` (usado para fixar a
# ordem dos arquivos antes de gerar o tar) e sensivel ao locale ativo do
# shell. Corrigido fixando `LC_ALL=C`/`LANG=C` no topo do script (afeta
# TODO comando do processo, inclusive `sort`/`find`/`tar`) e reforcando
# explicitamente na propria chamada de `sort` abaixo (defesa em
# profundidade). `TZ=UTC` fixado pelo mesmo motivo de determinismo ja
# aplicado em `build.sh` (nunca depender do fuso horario real da maquina).
export LC_ALL=C
export LANG=C
export TZ=UTC

OUTPUT="${1:?uso: package-source.sh <saida.tar.gz> [out_dir]}"
SRC_OUT_DIR="${2:-$(dirname "$0")/out1}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
LICENSES_DIR="$REPO_ROOT/licenses"
LOCK_FILE="$SCRIPT_DIR/sources.lock.json"
EPOCH=1700000000

json_field() {
  # $1 = componente ("ffmpeg"/"dav1d"), $2 = campo ("url"/"sha256"/...).
  # Parser deliberadamente feito so com sed/grep (nunca python3) -- este
  # script roda no HOST (nao dentro do container, que e o unico lugar
  # garantido a ter python3 instalado); exigir python3 no host adiciona
  # uma dependencia desnecessaria e fragil (ex.: em Windows, `python3` no
  # PATH pode resolver para o shim quebrado da Microsoft Store em vez de
  # uma instalacao real). `sources.lock.json` tem um formato simples e
  # estavel (um campo por linha, sem aninhamento alem do objeto do
  # componente), entao extrair com sed e confiavel e portatil.
  sed -n "/\"$1\": {/,/^  }/p" "$LOCK_FILE" \
    | grep "\"$2\":" \
    | head -1 \
    | sed -E "s/.*\"$2\":[[:space:]]*\"([^\"]*)\".*/\1/"
}

verify_sha256() {
  local file="$1" expected="$2" label="$3"
  local actual
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERRO: SHA-256 de $label ($file) nao bate. esperado=$expected obtido=$actual" >&2
    exit 1
  fi
  echo "-- SHA-256 de $label conferido: $actual"
}

# ---------------------------------------------------------------------------
# 0. Staging FORA do repositorio (nunca um diretorio persistente dentro de
# build/). `mktemp -d` cria um diretorio temporario garantidamente novo no
# diretorio temporario do sistema; o `trap` remove esse staging em
# QUALQUER saida do script -- sucesso, erro (`set -e`) ou interrupcao
# (Ctrl-C/SIGTERM) -- nunca deixando lixo para tras.
# ---------------------------------------------------------------------------
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sonder-ffmpeg-runtime-source-package.XXXXXXXX")"
cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT INT TERM

mkdir -p "$STAGE_DIR/build/sources"
mkdir -p "$STAGE_DIR/docs"
mkdir -p "$STAGE_DIR/licenses"

# --- 1. Tarballs de fonte: preferir os ja verificados por build.sh em
# $SRC_OUT_DIR/sources/ (copiados la DEPOIS de conferir o SHA-256 -- ver
# build.sh); se ausentes, baixar diretamente das URLs fixadas em
# sources.lock.json. De qualquer forma, o SHA-256 e reconferido AQUI antes
# de empacotar -- nunca confia cegamente num arquivo so porque o nome
# sugere que ja foi verificado antes.
# -----------------------------------------------------------------------
FFMPEG_SHA256="$(json_field ffmpeg sha256)"
DAV1D_SHA256="$(json_field dav1d sha256)"
FFMPEG_TARBALL_DEST="$STAGE_DIR/build/sources/ffmpeg.tar.gz"
DAV1D_TARBALL_DEST="$STAGE_DIR/build/sources/dav1d.tar.gz"

obtain_source_tarball() {
  local component="$1" expected_sha256="$2" dest="$3"
  local from_build="$SRC_OUT_DIR/sources/${component}.tar.gz"
  if [ -f "$from_build" ]; then
    echo "-- ${component}: usando tarball ja verificado por build.sh (${from_build})"
    cp "$from_build" "$dest"
  else
    local url
    url="$(json_field "$component" url)"
    echo "-- ${component}: nao encontrado em ${from_build} -- baixando de ${url}"
    curl -fsSL -o "$dest" "$url"
  fi
  verify_sha256 "$dest" "$expected_sha256" "$component"
}

obtain_source_tarball ffmpeg "$FFMPEG_SHA256" "$FFMPEG_TARBALL_DEST"
obtain_source_tarball dav1d "$DAV1D_SHA256" "$DAV1D_TARBALL_DEST"

# --- 2. Entradas de build (contexto Docker completo) -----------------------
cp "$SCRIPT_DIR/Dockerfile" "$STAGE_DIR/build/Dockerfile"
cp "$SCRIPT_DIR/build.sh" "$STAGE_DIR/build/build.sh"
cp "$SCRIPT_DIR/configure-flags.txt" "$STAGE_DIR/build/configure-flags.txt"
cp "$LOCK_FILE" "$STAGE_DIR/build/sources.lock.json"
cp "$SCRIPT_DIR/mingw-w64-x86_64-cross.meson" "$STAGE_DIR/build/mingw-w64-x86_64-cross.meson"
cp "$SCRIPT_DIR/package-source.sh" "$STAGE_DIR/build/package-source.sh"

# --- 3. Evidencia real do ultimo build (nunca reescrita a mao) -------------
for diff_file in ffmpeg-changes.diff dav1d-changes.diff; do
  if [ ! -f "$SRC_OUT_DIR/$diff_file" ]; then
    echo "ERRO: $SRC_OUT_DIR/$diff_file nao existe -- rode o build real (docker run ... build.sh) antes de empacotar" >&2
    exit 1
  fi
  cp "$SRC_OUT_DIR/$diff_file" "$STAGE_DIR/build/$diff_file"
done

# --- 4. Documentacao, SBOM, manifesto, licencas, instrucoes de reproducao --
cp "$DOCS_DIR/SBOM.md" "$STAGE_DIR/docs/SBOM.md"
cp "$DOCS_DIR/BUILD_MANIFEST.json" "$STAGE_DIR/docs/BUILD_MANIFEST.json"
cp "$DOCS_DIR/REPRODUCE.md" "$STAGE_DIR/docs/REPRODUCE.md"
cp "$DOCS_DIR/USAGE_MATRIX.md" "$STAGE_DIR/docs/USAGE_MATRIX.md"
cp "$DOCS_DIR/VALIDATION_REPORT.md" "$STAGE_DIR/docs/VALIDATION_REPORT.md"
cp -r "$LICENSES_DIR" "$STAGE_DIR/licenses"

# --- 5. Metadados do repositorio (README, LICENSE, avisos de terceiros) ---
cp "$REPO_ROOT/README.md" "$STAGE_DIR/README.md"
cp "$REPO_ROOT/LICENSE" "$STAGE_DIR/LICENSE"
cp "$REPO_ROOT/THIRD_PARTY_NOTICES.md" "$STAGE_DIR/THIRD_PARTY_NOTICES.md"

# --- 6. Tar deterministico: ordem fixa (LC_ALL=C explicito, nunca so a
# variavel de ambiente global), mtime fixo, owner/group normalizados,
# formato de tar fixado explicitamente (--format=gnu -- nunca o formato
# "padrao da plataforma", que pode divergir entre distribuicoes/versoes do
# GNU tar), gzip sem timestamp embutido --------------------------------
build_deterministic_tar() {
  local output_file="$1"
  (
    cd "$STAGE_DIR"
    find . -type f -print0 | LC_ALL=C sort -z | sed -z 's#^\./##' \
      | tar --format=gnu \
            --numeric-owner --owner=0 --group=0 --mode=go=rX,u+rw \
            --mtime="@${EPOCH}" \
            --null -T - -cf - \
      | gzip -n -9
  ) > "$output_file"
}

build_deterministic_tar "$OUTPUT"

# ---------------------------------------------------------------------------
# 7. Checksum publicado EXTERNAMENTE, ao lado do pacote -- NUNCA dentro
# dele. Registrar o SHA-256 do proprio pacote dentro de um arquivo que e,
# ele mesmo, incluido DENTRO do pacote (ex.: BUILD_MANIFEST.json) e uma
# autorreferencia: atualizar o hash muda o conteudo do arquivo, que muda o
# conteudo do .tar.gz, que muda o hash de novo, indefinidamente (nunca
# converge). Por isso nenhum arquivo empacotado registra o hash do proprio
# pacote -- o checksum real fica so neste sidecar, gerado DEPOIS que o
# .tar.gz ja esta fechado, e nunca copiado para dentro do STAGE_DIR/pacote.
# ---------------------------------------------------------------------------
# Gere o registro a partir do diretorio do artefato para que o nome salvo no
# sidecar seja portavel. Um consumidor que baixar o .tar.gz e o .sha256 na
# mesma pasta deve conseguir executar `sha256sum -c` sem recriar um caminho
# interno do CI como `out1/`.
OUTPUT_DIR="$(dirname "$OUTPUT")"
OUTPUT_BASENAME="$(basename "$OUTPUT")"
(cd "$OUTPUT_DIR" && sha256sum "$OUTPUT_BASENAME") | tee "${OUTPUT}.sha256"
