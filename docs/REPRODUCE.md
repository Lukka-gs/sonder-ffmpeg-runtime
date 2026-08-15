# Como reproduzir o build

Pré-requisito: Docker (usado como o ambiente Linux/container -- MinGW-w64 cross-compila para
Windows x86_64 dentro dele; nada é instalado globalmente na máquina host).

**Nada neste pipeline depende de "latest" nem de espelhos móveis**: a imagem base é fixada por
digest (integridade do filesystem base), o repositório APT é fixado por um snapshot imutável de
`snapshot.debian.org` (integridade e disponibilidade contínua dos pacotes do toolchain -- o digest
da imagem, sozinho, NÃO garante isso, ver nota abaixo), e as fontes de FFmpeg/dav1d são tarballs
fixos por URL+SHA256 (`build/sources.lock.json`), nunca `git fetch` contra um remoto móvel.

```bash
cd build

# 1. Constrói a imagem de build. O Dockerfile:
#    - fixa a imagem base por DIGEST (nunca por tag movel);
#    - substitui as fontes APT padrao por snapshot.debian.org, timestamp
#      imutavel (ver ARG DEBIAN_SNAPSHOT_TIMESTAMP no proprio Dockerfile);
#    - instala cada pacote do toolchain com a VERSAO EXATA fixada
#      (apt-get install pacote=versao), nao "o que o snapshot tiver".
docker build -t sonder-ffmpeg-runtime:build .

# 2. Roda o build de verdade. Nenhuma variavel de ambiente de commit e
#    necessaria -- as fontes (FFmpeg e dav1d) vem de sources.lock.json,
#    verificadas por SHA-256 pelo proprio build.sh antes de extrair.
mkdir -p out
docker run --rm -v "$(pwd)/out:/out" sonder-ffmpeg-runtime:build

# 3. Resultado em ./out/:
ls out/
#   ffmpeg.exe  ffprobe.exe  SHA256SUMS.txt
#   configure.log  ffbuild-config.log
#   ffmpeg-changes.diff  dav1d-changes.diff
#   ffmpeg-link.map  ffprobe-link.map  ffmpeg-static-members.txt  ffprobe-static-members.txt
#   ffmpeg-dll-deps.txt  ffprobe-dll-deps.txt  LINKMAP-SHA256SUMS.txt
#   dav1d-meson-setup.log  dav1d-ninja-build.log  dav1d-ninja-install.log  dav1d.pc.txt
#   sources/{ffmpeg,dav1d}.tar.gz + SHA256SUMS.txt -- as duas fontes, ja
#     verificadas por SHA-256 pelo proprio build.sh, copiadas para fora do
#     container -- e o que `package-source.sh` (passo seguinte) consome

# 4. Monta o pacote deterministico de codigo-fonte correspondente --
#    SEPARADO de build.sh de proposito (ver secao abaixo). Funciona logo
#    apos um `git clone` limpo, sem precisar de nenhum arquivo local
#    pre-existente -- consome os tarballs de out/sources/ (passo 3 acima).
./package-source.sh out/sonder-ffmpeg-source.tar.gz out
```

O fluxo completo -- `git clone` → `docker build` → `docker run` → `./package-source.sh` -- funciona
do zero, sem depender de nenhum arquivo local deixado por uma sessão anterior (testado extraindo o
repositório para um diretório limpo, sem `build/sources/*.tar.gz` pré-existente).

## Sobre o digest da imagem NÃO fixar o repositório APT

Uma revisão anterior deste Dockerfile presumia, incorretamente, que fixar a imagem base por digest
também fixava o conteúdo do repositório APT consultado por `apt-get update`/`install`. Isso é
**falso** -- o digest fixa só o filesystem publicado da imagem; os espelhos padrão (`deb.debian.org`)
continuam móveis, podendo servir versões de pacote diferentes em datas diferentes mesmo com a MESMA
imagem base e o MESMO Dockerfile. Corrigido: as fontes APT são substituídas por uma única fonte
apontando para `snapshot.debian.org` num timestamp fixo, e cada pacote principal é instalado com a
versão exata (capturada do próprio snapshot, registrada em `BUILD_MANIFEST.json`). Testado
reconstruindo a imagem meses depois de identificar o timestamp: mesmas versões, sem precisar
redescobrir nada -- se o snapshot pinado algum dia parar de servir exatamente essa versão, o build
falha alto (`apt-get install` recusa uma versão diferente), nunca resolve silenciosamente outra.

## Para provar reprodutibilidade (duas compilações limpas)

```bash
docker run --rm -v "$(pwd)/out1:/out" sonder-ffmpeg-runtime:build
docker run --rm -v "$(pwd)/out2:/out" sonder-ffmpeg-runtime:build
diff <(awk '{print $1}' out1/SHA256SUMS.txt) <(awk '{print $1}' out2/SHA256SUMS.txt) \
  && echo "IDENTICO" || echo "DIVERGENTE -- investigar"
cmp out1/ffmpeg.exe out2/ffmpeg.exe && echo "ffmpeg.exe byte-identico"
cmp out1/ffprobe.exe out2/ffprobe.exe && echo "ffprobe.exe byte-identico"
```

`build.sh` sempre extrai as fontes de um tarball fresco e roda `git init`/`commit` com uma data
FIXA (`SOURCE_DATE_EPOCH`, nunca o relógio real) só para poder gerar `changes.diff` -- achado real:
o `meson.build` do dav1d roda `git describe` contra esse repositório local para embutir uma string
de versão no binário; sem a data fixa, cada execução criava um commit com hash diferente, tornando
os binários NÃO byte-identicos mesmo com fonte idêntica. Corrigido fixando
`GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` em `SOURCE_DATE_EPOCH`.

Os link maps (`ffmpeg-link.map`/`ffprobe-link.map`, ver `SBOM.md`) também são reproduzíveis entre
`out1`/`out2` -- confirme com `cmp out1/ffmpeg-link.map out2/ffmpeg-link.map` e o equivalente para
`ffprobe`.

## Pacote de código-fonte correspondente (determinístico e autossuficiente)

O gerador é **`package-source.sh`** — não `build.sh` (que só compila e verifica as fontes; nunca
monta o pacote). `package-source.sh` roda no **host** (nunca dentro do container) porque precisa
alcançar `build/`, `docs/` e `licenses/` -- Docker não permite `COPY` de fora do contexto de
build, então montar o pacote dentro de `build.sh` geraria um pacote incompleto (sem
licenças/SBOM/manifesto) por construção.

```bash
cd build
./package-source.sh out/sonder-ffmpeg-source.tar.gz out
```

**Funciona a partir de um clone limpo**: os tarballs de fonte vêm de
`out/sources/{ffmpeg,dav1d}.tar.gz` (copiados ali por `build.sh` DEPOIS de verificar o SHA-256 --
nunca de `build/sources/` local, que só existe se alguém baixou manualmente antes). Se
`out/sources/` não tiver os tarballs por qualquer motivo, `package-source.sh` os baixa direto das
URLs fixadas em `sources.lock.json` e verifica o SHA-256 de novo antes de empacotar -- nunca confia
cegamente num arquivo só porque o nome sugere que já foi conferido.

**Staging fora do repositório**: usa `mktemp -d` (nunca um diretório persistente dentro de
`build/`) com `trap cleanup EXIT INT TERM` -- o staging temporário é removido em qualquer saída do
script (sucesso, erro ou interrupção). Depois de rodar, `git status --short` não mostra nenhum
artefato de empacotamento.

**Determinístico**: `LC_ALL=C`/`LANG=C`/`TZ=UTC` fixados no topo do script (locale afeta a ordem
de `sort`), ordem fixa (`find | LC_ALL=C sort`), formato de tar fixado explicitamente
(`--format=gnu`), `mtime` fixo (`--mtime=@1700000000`), owner/group normalizados
(`--owner=0 --group=0 --numeric-owner`), gzip sem timestamp embutido (`gzip -n`). Rodar o script
duas vezes -- inclusive em ambientes com locale diferente -- produz o **mesmo SHA-256**
(confirmado em múltiplas gerações, incluindo entre uma sessão Linux e o Git Bash do Windows):

```bash
./package-source.sh /tmp/a.tar.gz out && ./package-source.sh /tmp/b.tar.gz out
cmp /tmp/a.tar.gz /tmp/b.tar.gz && echo "PACOTE IDENTICO"
```

**Autossuficiente**: o pacote extraído contém seus próprios `Dockerfile`/`build.sh`/
`configure-flags.txt`/`sources.lock.json`/`mingw-w64-x86_64-cross.meson`/`package-source.sh`, as
fontes de FFmpeg/dav1d já vendorizadas (`build/sources/{ffmpeg,dav1d}.tar.gz`, verificadas por
SHA-256 antes de empacotar), toda a documentação (`docs/`, `licenses/`) e o `README.md`/`LICENSE`/
`THIRD_PARTY_NOTICES.md` do próprio repositório -- reproduzir a partir dele não depende de nenhum
outro arquivo do repositório original.

**Checksum externo, nunca dentro do pacote**: `package-source.sh` grava
`sonder-ffmpeg-source.tar.gz.sha256` ao lado do `.tar.gz` (nunca dentro dele) -- registrar o hash
do próprio pacote em algum arquivo incluído dentro dele mesmo (ex.: `BUILD_MANIFEST.json`) seria
uma autorreferência: atualizar o hash muda o conteúdo do arquivo, que muda o conteúdo do pacote,
que muda o hash de novo, indefinidamente.

## Onde os binários resultantes NÃO vão

Este repositório nunca copia `out/ffmpeg.exe`/`out/ffprobe.exe` para nenhum outro projeto --
integrar este runtime a uma aplicação é uma decisão explícita de quem consome este repositório,
fora do escopo deste projeto.

## Validação funcional

`h264_mf` depende da API real do Windows Media Foundation -- não roda dentro do container Linux.
Depois de gerar `out/ffmpeg.exe`/`out/ffprobe.exe`, valide numa máquina Windows real:

```powershell
.\ffmpeg.exe -hide_banner -buildconf
.\ffmpeg.exe -hide_banner -encoders   # confirmar h264_mf e aac presentes
.\ffprobe.exe -version
```

Ver `docs/VALIDATION_REPORT.md` e `docs/USAGE_MATRIX.md` para a matriz completa de formatos e
codecs validados.
