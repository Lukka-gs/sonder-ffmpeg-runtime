#!/usr/bin/env bash
# Script reproduzivel de build do FFmpeg minimo LGPL + dav1d para
# Windows x86_64, rodado dentro do container definido por Dockerfile (APT
# fixado por snapshot.debian.org, nunca por espelho movel -- ver Dockerfile).
#
# Ambas as fontes (FFmpeg e dav1d) sao arquivos .tar.gz baixados de uma URL
# fixa e conferidos por SHA-256 ANTES de extrair (`sources.lock.json` e a
# unica fonte de verdade das duas URLs/hashes) -- nunca `git fetch` contra um
# remoto movel. O script recusa continuar (`exit 1`) se o hash nao bater.
set -euo pipefail

OUT_DIR="${OUT_DIR:-/out}"
LOCK_FILE="/build/sources.lock.json"
FFMPEG_SRC_DIR="/build/ffmpeg-src"
DAV1D_SRC_DIR="/build/dav1d-src"
DAV1D_INSTALL_DIR="/build/dav1d-install"

mkdir -p "$OUT_DIR"

FFMPEG_URL="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['ffmpeg']['url'])")"
FFMPEG_SHA256="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['ffmpeg']['sha256'])")"
FFMPEG_COMMIT="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['ffmpeg']['commit'])")"
DAV1D_URL="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['dav1d']['url'])")"
DAV1D_SHA256="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['dav1d']['sha256'])")"
DAV1D_TAG="$(python3 -c "import json;print(json.load(open('$LOCK_FILE'))['dav1d']['tag'])")"

echo "== build reproduzivel (FFmpeg + dav1d, fontes fixadas por hash) =="
echo "FFmpeg commit fixado: ${FFMPEG_COMMIT}"
echo "dav1d tag fixada:     ${DAV1D_TAG}"
echo "SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-nao definido}"

# ---------------------------------------------------------------------------
# 1. Verifica e obtem as duas fontes por SHA-256 ANTES de extrair qualquer
# coisa -- nunca confia no nome do arquivo nem no tamanho, so no hash.
#
# Prefere uma copia ja VENDORIZADA localmente (`/build/vendored-sources/`,
# populada pelo Dockerfile a partir de `build/sources/`
# quando presente) -- isto e o que torna o pacote de codigo-fonte
# determinístico (secao 5 abaixo) verdadeiramente AUTOSSUFICIENTE: extraido
# em outra maquina, sem acesso a rede nenhum, ainda consegue reproduzir o
# build inteiro, porque as fontes ja estao dentro do proprio pacote/imagem.
# Se a copia local nao existir (ex.: build normal fora do teste de
# autossuficiencia), cai para `curl` contra a URL fixada -- mesma verificacao
# de hash em ambos os caminhos, nunca pulada.
# ---------------------------------------------------------------------------
fetch_and_verify() {
  local url="$1" expected_sha256="$2" dest="$3" vendored="$4"
  if [ -f "$vendored" ]; then
    echo "-- usando copia vendorizada local: ${vendored} (sem rede)"
    cp "$vendored" "$dest"
  else
    echo "-- baixando ${url}"
    curl -fsSL -o "$dest" "$url"
  fi
  local actual_sha256
  actual_sha256="$(sha256sum "$dest" | awk '{print $1}')"
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    echo "ERRO: SHA-256 de $dest nao bate. esperado=$expected_sha256 obtido=$actual_sha256" >&2
    exit 1
  fi
  echo "-- SHA-256 conferido: $actual_sha256"
}

mkdir -p /build/sources
fetch_and_verify "$FFMPEG_URL" "$FFMPEG_SHA256" "/build/sources/ffmpeg.tar.gz" "/build/vendored-sources/ffmpeg.tar.gz"
fetch_and_verify "$DAV1D_URL" "$DAV1D_SHA256" "/build/sources/dav1d.tar.gz" "/build/vendored-sources/dav1d.tar.gz"

# CORRECAO (achado real: package-source.sh nao funcionava a partir de um
# clone limpo -- dependia de build/sources/*.tar.gz
# ja terem sido baixados manualmente numa sessao anterior, algo que nunca
# existe logo apos `git clone`, ja que sources/ e gitignored). CORRIGIDO:
# os DOIS tarballs, ja verificados por SHA-256 acima (linha ou vendorizados,
# ou baixados agora), sao copiados para `$OUT_DIR/sources/` -- que E
# bind-mounted para o host (`-v .../out1:/out`) -- entao, logo apos
# `docker run`, o host tem uma copia VERIFICADA e pronta para
# `package-source.sh` consumir, sem precisar rebaixar nem confiar em
# arquivo nenhum pre-existente no repositorio.
mkdir -p "$OUT_DIR/sources"
cp /build/sources/ffmpeg.tar.gz "$OUT_DIR/sources/ffmpeg.tar.gz"
cp /build/sources/dav1d.tar.gz "$OUT_DIR/sources/dav1d.tar.gz"
sha256sum "$OUT_DIR/sources/ffmpeg.tar.gz" "$OUT_DIR/sources/dav1d.tar.gz" | tee "$OUT_DIR/sources/SHA256SUMS.txt"

rm -rf "$FFMPEG_SRC_DIR" "$DAV1D_SRC_DIR" "$DAV1D_INSTALL_DIR"
mkdir -p "$FFMPEG_SRC_DIR" "$DAV1D_SRC_DIR"
tar -xzf /build/sources/ffmpeg.tar.gz -C "$FFMPEG_SRC_DIR" --strip-components=1
tar -xzf /build/sources/dav1d.tar.gz -C "$DAV1D_SRC_DIR" --strip-components=1

# Baseline git local (nunca contatando nenhum remoto) so para poder provar,
# por `git diff`, que nada no codigo extraido foi alterado antes/durante o
# build -- so arquivos NOVOS de build (config.h, *.o, build/, etc.) aparecem
# depois, nunca como modificacao de um arquivo ja rastreado nesta baseline.
# CORRECAO (achado real de nao-determinismo, nao hipotetico): o proprio
# meson.build do dav1d roda `git describe --long --always` contra este
# repositorio git local para gerar `include/vcs_version.h`
# (`DAV1D_VERSION "@VCS_TAG@"`), embutido na biblioteca final. Sem uma data
# de commit fixa, cada execucao deste script cria um commit "pristine" com
# hash DIFERENTE (autor/committer usam o relogio real por padrao) -- o que
# fazia `git describe` devolver um hash abreviado diferente a cada build,
# tornando ffmpeg.exe/ffprobe.exe NAO byte-identicos entre execucoes mesmo
# com o mesmo codigo-fonte. Corrigido fixando `GIT_AUTHOR_DATE`/
# `GIT_COMMITTER_DATE` em `SOURCE_DATE_EPOCH` (a mesma epoch ja usada para
# reprodutibilidade em outros pontos do build) -- com a mesma arvore de
# arquivos (fonte fixada por hash) e a mesma data, o commit resultante tem
# SEMPRE o mesmo hash, entao `git describe` tambem sempre devolve o mesmo
# valor.
export GIT_AUTHOR_NAME="sonder-ffmpeg-runtime build"
export GIT_AUTHOR_EMAIL="build@sonder-ffmpeg-runtime.invalid"
export GIT_COMMITTER_NAME="sonder-ffmpeg-runtime build"
export GIT_COMMITTER_EMAIL="build@sonder-ffmpeg-runtime.invalid"
export GIT_AUTHOR_DATE="@${SOURCE_DATE_EPOCH:-1700000000} +0000"
export GIT_COMMITTER_DATE="@${SOURCE_DATE_EPOCH:-1700000000} +0000"
for src_dir in "$FFMPEG_SRC_DIR" "$DAV1D_SRC_DIR"; do
  git -C "$src_dir" init -q
  git -C "$src_dir" config user.email "build@sonder-ffmpeg-runtime.invalid"
  git -C "$src_dir" config user.name "sonder-ffmpeg-runtime build"
  git -C "$src_dir" add -A
  git -C "$src_dir" commit -q -m "pristine snapshot (hash-verified tarball, sem git remoto)"
done

# ---------------------------------------------------------------------------
# 2. Compila dav1d (unica biblioteca externa de codec deste build) estatico
# para o alvo MinGW-w64 x86_64, via meson + ninja (cross-file versionado).
# ---------------------------------------------------------------------------
echo "== Compilando dav1d (decode de AV1 por software) =="
cd "$DAV1D_SRC_DIR"
meson setup build \
  --cross-file /build/mingw-w64-x86_64-cross.meson \
  --prefix="$DAV1D_INSTALL_DIR" \
  --default-library=static \
  --buildtype=release \
  -Denable_tools=false \
  -Denable_examples=false \
  -Denable_tests=false \
  -Denable_docs=false \
  2>&1 | tee "$OUT_DIR/dav1d-meson-setup.log"
ninja -C build 2>&1 | tee "$OUT_DIR/dav1d-ninja-build.log"
ninja -C build install 2>&1 | tee "$OUT_DIR/dav1d-ninja-install.log"

find "$DAV1D_INSTALL_DIR" -name '*.pc' -exec cat {} \; > "$OUT_DIR/dav1d.pc.txt"

# ---------------------------------------------------------------------------
# 3. Configura e compila o FFmpeg, apontando o pkg-config EXCLUSIVAMENTE
# para o dav1d recem-instalado (nunca uma copia do sistema, que nao
# existiria de qualquer forma neste container minimo).
# ---------------------------------------------------------------------------
cd "$FFMPEG_SRC_DIR"

CONFIGURE_ARGS=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(echo -n "$line" | sed -e 's/[[:space:]]*$//')"
  [ -z "$line" ] && continue
  CONFIGURE_ARGS+=("$line")
done < /build/configure-flags.txt

# `--no-insert-timestamp`: o linker do MinGW (GNU ld) grava por padrao o
# instante de build no cabecalho COFF/PE (`TimeDateStamp`) -- a causa mais
# comum de dois builds identicos em codigo-fonte nao serem identicos byte a
# byte no Windows. `-static` evita depender de libgcc/libwinpthread/libstdc++
# do MinGW em runtime (nenhuma DLL alem das do proprio Windows).
#
# CORRECAO (achado real, nao hipotetico): uma revisao anterior deste script
# passava `-Wl,-Map=...` UMA UNICA VEZ via `--extra-ldflags` no `./configure`
# (baked em `LDFLAGS` de `ffbuild/config.mak`), o que faz TODO binario final
# (`ffmpeg.exe` E `ffprobe.exe`) ser linkado usando o MESMO caminho de map --
# nao existe isolamento por binario nessa flag. A tentativa de "recuperar" um
# mapa por-binario rodando `make ffprobe.exe EXTRA_LDFLAGS=...` depois nao
# funcionava: `EXTRA_LDFLAGS` NAO E uma variavel reconhecida pelo Makefile do
# FFmpeg (confirmado lendo `Makefile` real: a regra de link usa somente
# `$(LDFLAGS)`, nunca `$(EXTRA_LDFLAGS)`) -- a atribuicao era silenciosamente
# ignorada pelo `make`, entao as duas compilacoes linkavam com o MESMO
# `LDFLAGS` (mesmo caminho de map) vindo do `config.mak`, e o `ffprobe-link.map`
# resultante era uma copia BYTE-A-BYTE do `ffmpeg-link.map` (confirmado com
# `cmp`: identicos; ambos continham `fftools/ffmpeg.o` E `fftools/ffprobe.o`).
#
# CORRIGIDO: `./configure` NUNCA embute `-Wl,-Map=...` (so `-static
# -Wl,--no-insert-timestamp`, sem caminho de map nenhum). Cada binario final e
# linkado numa chamada de `make` SEPARADA e SEQUENCIAL (nunca concorrente),
# pedindo explicitamente so aquele arquivo-alvo (`make ffmpeg.exe` / `make
# ffprobe.exe` -- o proprio GNU Make so relinka o que foi pedido, nunca o
# outro binario, ja que nenhum depende do outro), com `LDFLAGS` reconstruido a
# partir do valor REAL gravado por `./configure` em `ffbuild/config.mak` (nao
# reescrito a mao) mais `-Wl,-Map=<caminho especifico deste binario>`
# concatenado por cima -- uma sobrescrita de variavel via linha de comando do
# GNU Make, que tem precedencia sobre a atribuicao do proprio `config.mak`
# (confirmado: `config.mak` usa atribuicao simples `LDFLAGS=...`, nunca
# `override`). Como cada chamada de `make` so constroi UM binario final por
# vez, nunca ha dois processos `ld` escrevendo no mesmo arquivo de map ao
# mesmo tempo -- a corrida de make paralelo (`-j`) continua acelerando a
# compilacao dos objetos/bibliotecas internas COMPARTILHADAS (libavcodec.a
# etc., que nao tem map nenhum), so a etapa final de LINK de cada executavel
# e que roda isolada.
export PKG_CONFIG_LIBDIR="$DAV1D_INSTALL_DIR/lib/pkgconfig:$DAV1D_INSTALL_DIR/lib/x86_64-linux-gnu/pkgconfig"
export PKG_CONFIG_PATH=""

echo "== Configure (FFmpeg + libdav1d) =="
./configure \
  "${CONFIGURE_ARGS[@]}" \
  --extra-ldflags="-static -Wl,--no-insert-timestamp" \
  --extra-ldexeflags="-static" \
  --pkg-config-flags="--static" \
  2>&1 | tee "$OUT_DIR/configure.log"

cp ffbuild/config.log "$OUT_DIR/ffbuild-config.log" 2>/dev/null || cp config.log "$OUT_DIR/ffbuild-config.log" 2>/dev/null || true

echo "== Configure line completa (ffmpeg -version ira reportar isto em 'configuration:') =="
grep -m1 '^FFMPEG_CONFIGURATION' ffbuild/config.mak || grep -m1 '^FFMPEG_CONFIGURATION' config.mak

NPROC="$(nproc)"

# CORRECAO (segundo achado real, descoberto rodando o build de verdade):
# a primeira tentativa de isolar o map por binario passava `LDFLAGS=...` na
# LINHA DE COMANDO do `make` -- isso FALHA porque uma atribuicao de variavel
# na linha de comando do GNU Make trava aquela variavel contra QUALQUER
# reatribuicao feita pelos proprios Makefiles depois (mesmo com `:=`/`+=`),
# e `ffbuild/common.mak` (incluido DEPOIS de `ffbuild/config.mak`) faz
# exatamente isso: `LDFLAGS := $(ALLFFLIBS:%=$(LD_PATH)lib%) $(LDFLAGS)`,
# que PREPENDE os `-L` de cada biblioteca interna (`-Llibavcodec` etc.) --
# sem essa linha rodar, o linker nao acha `-lavfilter`/`-lavcodec`/etc.
# (confirmado: "cannot find -lavfilter: No such file or directory" na
# primeira tentativa). CORRIGIDO: em vez de sobrescrever `LDFLAGS` pela
# linha de comando, ACRESCENTAMOS uma linha nova em `ffbuild/config.mak`
# (`LDFLAGS := $(LDFLAGS) -Wl,-Map=...`, expansao imediata do valor atual)
# antes de cada `make` isolado -- isto preserva o mecanismo normal de
# resolucao de variaveis do Make (a linha de `common.mak` continua rodando
# normalmente, prependendo os `-L` corretos), so adiciona o caminho do map
# por cima. Restauramos o `config.mak` original entre uma chamada e outra.
CONFIG_MAK="ffbuild/config.mak"
cp "$CONFIG_MAK" "${CONFIG_MAK}.orig"

link_one_binary() {
  local target="$1" map_path="$2"
  cp "${CONFIG_MAK}.orig" "$CONFIG_MAK"
  echo "LDFLAGS := \$(LDFLAGS) -Wl,-Map=${map_path}" >> "$CONFIG_MAK"
  echo "== Link isolado de ${target} (map dedicado: ${map_path}) =="
  make -j"${NPROC}" "$target"
}

link_one_binary "ffmpeg.exe" "${OUT_DIR}/ffmpeg-link.map"
link_one_binary "ffprobe.exe" "${OUT_DIR}/ffprobe-link.map"
cp "${CONFIG_MAK}.orig" "$CONFIG_MAK"
rm -f "${CONFIG_MAK}.orig"

# ---------------------------------------------------------------------------
# Validacao fail-high dos link maps: cada um PRECISA conter o objeto-raiz do
# SEU proprio binario e PRECISA NAO conter o objeto-raiz do OUTRO -- prova de
# que os dois mapas sao realmente distintos e corretos, nunca uma copia
# cruzada. Falha o build inteiro (`exit 1`) se qualquer condicao nao bater --
# nunca um aviso silencioso.
# ---------------------------------------------------------------------------
validate_link_map() {
  local map_file="$1" must_contain="$2" must_not_contain="$3" label="$4"
  if [ ! -s "$map_file" ]; then
    echo "ERRO: $label ($map_file) esta vazio ou nao existe -- link map invalido" >&2
    exit 1
  fi
  if ! grep -qF "$must_contain" "$map_file"; then
    echo "ERRO: $label ($map_file) NAO contem '$must_contain' -- objeto-raiz esperado ausente" >&2
    exit 1
  fi
  if grep -qF "$must_not_contain" "$map_file"; then
    echo "ERRO: $label ($map_file) contem '$must_not_contain' -- vazamento entre binarios, os dois link maps nao estao isolados" >&2
    exit 1
  fi
  echo "OK: $label contem '$must_contain' e NAO contem '$must_not_contain'"
}
echo "== Validacao fail-high dos link maps (objeto-raiz correto, nenhuma contaminacao cruzada) =="
validate_link_map "$OUT_DIR/ffmpeg-link.map" "fftools/ffmpeg.o" "fftools/ffprobe.o" "ffmpeg-link.map"
validate_link_map "$OUT_DIR/ffprobe-link.map" "fftools/ffprobe.o" "fftools/ffmpeg.o" "ffprobe-link.map"

# Prova adicional, nao apenas grep de texto: os dois arquivos de map NUNCA
# podem ser byte-identicos (se forem, e a mesma prova reciclada, nao dois
# mapas reais e distintos).
if cmp -s "$OUT_DIR/ffmpeg-link.map" "$OUT_DIR/ffprobe-link.map"; then
  echo "ERRO: ffmpeg-link.map e ffprobe-link.map sao byte-identicos -- nao sao mapas isolados de verdade" >&2
  exit 1
fi
echo "OK: ffmpeg-link.map e ffprobe-link.map sao arquivos distintos (cmp confirma divergencia)"

cp ffmpeg.exe "$OUT_DIR/ffmpeg.exe"
cp ffprobe.exe "$OUT_DIR/ffprobe.exe"

sha256sum "$OUT_DIR/ffmpeg.exe" "$OUT_DIR/ffprobe.exe" | tee "$OUT_DIR/SHA256SUMS.txt"
sha256sum "$OUT_DIR/ffmpeg-link.map" "$OUT_DIR/ffprobe-link.map" | tee "$OUT_DIR/LINKMAP-SHA256SUMS.txt"

echo "== Dependencias declaradas no PE (objdump -p -- so prova DLLs, nunca ausencia de estatico) =="
x86_64-w64-mingw32-objdump -p "$OUT_DIR/ffmpeg.exe" | grep -A2 "DLL Name" | tee "$OUT_DIR/ffmpeg-dll-deps.txt" || true
x86_64-w64-mingw32-objdump -p "$OUT_DIR/ffprobe.exe" | grep -A2 "DLL Name" | tee "$OUT_DIR/ffprobe-dll-deps.txt" || true

echo "== Arquivos de objeto/biblioteca estatica realmente incorporados (link map, por binario) =="
grep -E '^(LOAD |\.a\(|.*\.o\))' "$OUT_DIR/ffmpeg-link.map" | grep -iE 'dav1d|libwinpthread|libmingw|libgcc|libmoldname|libmsvcrt|libpthread' | sort -u | tee "$OUT_DIR/ffmpeg-static-members.txt" || true
grep -E '^(LOAD |\.a\(|.*\.o\))' "$OUT_DIR/ffprobe-link.map" | grep -iE 'dav1d|libwinpthread|libmingw|libgcc|libmoldname|libmsvcrt|libpthread' | sort -u | tee "$OUT_DIR/ffprobe-static-members.txt" || true

# ---------------------------------------------------------------------------
# 4. changes.diff -- comparado contra a baseline pristina criada logo apos
# extrair o tarball (secao 1 acima), nunca contra um remoto. `make` gera
# arquivos NOVOS (config.h, *.o, ffbuild/, build/) dentro da propria arvore
# de fontes -- esses aparecem como "untracked" (nao rastreados), nunca como
# "modified", entao um `git diff` (sem --stat de untracked) so mostraria
# algo se um arquivo ORIGINAL do tarball tivesse sido alterado.
# ---------------------------------------------------------------------------
git -C "$FFMPEG_SRC_DIR" diff --patch HEAD -- . ':!*.o' ':!*.d' > "$OUT_DIR/ffmpeg-changes.diff" || true
git -C "$DAV1D_SRC_DIR" diff --patch HEAD -- . ':!build' > "$OUT_DIR/dav1d-changes.diff" || true

# ---------------------------------------------------------------------------
# 5. O pacote deterministico de codigo-fonte correspondente e montado FORA
# deste container, pelo script `package-source.sh` (roda no host) --
# CORRECAO (achado real): este script so tem acesso ao contexto de build do
# Docker (`build/`), nunca a `docs/`
# (licencas, SBOM, BUILD_MANIFEST.json, REPRODUCE.md, avisos de terceiros --
# um diretorio IRMAO, fora do contexto do `docker build`) -- um pacote
# "autossuficiente" pedido pela meta precisa desses arquivos tambem, entao
# montar dentro do container geraria um pacote incompleto por construcao.
# `package-source.sh` copia os dois `changes.diff` gerados acima (via
# $OUT_DIR, que E bind-mounted) e tudo mais do host.
echo "== Concluido (ffmpeg.exe, ffprobe.exe, link maps validados, changes.diff em ${OUT_DIR}) =="
