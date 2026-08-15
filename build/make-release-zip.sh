#!/usr/bin/env bash
# Monta um .zip deterministico a partir de um diretorio de entrada ja
# preparado com o conteudo final -- usado por release.yml para provar que o
# ZIP e reproduzivel: chamado DUAS VEZES, em diretorios independentes, com o
# MESMO conteudo de entrada, produz dois arquivos byte a byte IDENTICOS.
#
# Este script so decide COMO compactar (locale/timezone/timestamps/
# permissoes normalizados, ordem fixa de arquivos) -- nunca QUAIS arquivos
# entram; isso e responsabilidade de quem monta o diretorio de entrada.
#
# Uso:
#   ./make-release-zip.sh <saida.zip> <diretorio-de-entrada>
#
# Nao gera nenhum sidecar de hash -- isso e feito pelo chamador, DEPOIS que
# o ZIP retornado por este script ja esta fechado (nunca antes, e nunca
# dentro do proprio ZIP).
set -euo pipefail

# Mesma justificativa de determinismo de locale/timezone usada em
# package-source.sh: `sort` e sensivel ao locale ativo do shell, e um zip
# gerado com timestamps reais (em vez de um SOURCE_DATE_EPOCH fixo) nunca
# seria reproduzivel entre execucoes.
export LC_ALL=C
export LANG=C
export TZ=UTC

OUTPUT="${1:?uso: make-release-zip.sh <saida.zip> <diretorio-de-entrada>}"
INPUT_DIR="${2:?uso: make-release-zip.sh <saida.zip> <diretorio-de-entrada>}"
EPOCH="${SOURCE_DATE_EPOCH:-1700000000}"

if [ ! -d "$INPUT_DIR" ]; then
  echo "ERRO: diretorio de entrada nao existe: $INPUT_DIR" >&2
  exit 1
fi

# Resolve o caminho de saida para ABSOLUTO antes de mudar de diretorio --
# o comando `zip` roda com `cd "$INPUT_DIR"` para que os caminhos internos
# do arquivo fiquem relativos (sem o prefixo do diretorio de staging, que
# poderia variar entre as duas geracoes independentes).
case "$OUTPUT" in
  /*) OUTPUT_ABS="$OUTPUT" ;;
  *) OUTPUT_ABS="$(pwd)/$OUTPUT" ;;
esac
mkdir -p "$(dirname "$OUTPUT_ABS")"
rm -f "$OUTPUT_ABS"

# Normaliza timestamps (mtime fixo = SOURCE_DATE_EPOCH) e permissoes (644
# para todo arquivo) de TODA entrada ANTES de compactar -- o formato ZIP
# embute mtime e atributos de permissao POR ARQUIVO, entao sem isso o mesmo
# conteudo lógico produziria bytes diferentes dependendo de QUANDO/COMO cada
# arquivo foi copiado para o diretorio de staging.
TOUCH_DATE="$(date -u -d "@${EPOCH}" +'%Y%m%d%H%M.%S' 2>/dev/null || date -u -r "${EPOCH}" +'%Y%m%d%H%M.%S')"
find "$INPUT_DIR" -type f -exec chmod 644 {} \;
find "$INPUT_DIR" -type f -exec touch -t "$TOUCH_DATE" {} \;

(
  cd "$INPUT_DIR"
  # -X: sem informacao extra de timestamp/UID/GID alem do mtime ja
  # normalizado acima. Ordem de entrada fixada explicitamente por
  # `LC_ALL=C sort` (nunca a ordem de iteracao do filesystem, que nao e
  # garantida estavel entre execucoes/maquinas).
  find . -type f | LC_ALL=C sort | sed 's#^\./##' | zip -X -q "$OUTPUT_ABS" -@
)

echo "-- ZIP deterministico gerado: $OUTPUT_ABS"
