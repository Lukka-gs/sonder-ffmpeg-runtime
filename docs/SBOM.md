# SBOM do build minimo do FFmpeg + dav1d

Gerado a partir da configure line real (`configure-flags.txt`), da saida real de `./configure`
(`configure.log`/`ffbuild-config.log`) e do **link map real do linker**
(`ffmpeg-link.map`/`ffprobe-link.map`, gerado via `-Wl,-Map=...` no proprio `build.sh`) -- nunca
apenas listado por intencao.

**Nota importante sobre o metodo de prova**: `objdump -p` (que so lista DLLs **dinamicas**
declaradas no cabecalho PE) NAO e prova de "nenhuma biblioteca estatica linkada" -- essas sao
coisas DIFERENTES. `objdump -p` prova a auséncia de dependencias _dinamicas_ alem das do proprio
Windows; nunca prova nada sobre o que foi linkado _estaticamente_ dentro do binario. A prova
correta de "o que foi realmente incorporado" e o link map do proprio linker (secao abaixo) -- e
ele mostra que **dav1d** e, sim, uma biblioteca de terceiros linkada estaticamente, para permitir
decodificar AV1 por software sem depender de D3D11VA/DXVA2. Comparado a um build generico como o
do BtbN (que liga estaticamente dezenas de bibliotecas de terceiros -- GMP, LAME, OpenH264,
libvmaf, OpenSSL/Schannel, AOM, libass, libjxl, libopus, libvpx, libwebp, OpenJPEG, rav1e, SVT-AV1,
SRT), este build liga **apenas uma** biblioteca externa, escolhida e justificada explicitamente.

## Componente principal distribuido

| Campo                      | Valor                                                                                                                                                                                                                                                    |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Componente                 | FFmpeg                                                                                                                                                                                                                                                   |
| Versao/commit              | `9b6c8969e05b4f0b29f0f85cd501be6b3e582e6b`                                                                                                                                                                                                               |
| Origem                     | Tarball fixado por URL+SHA256 em `sources.lock.json` (nunca `git fetch` movel) -- `https://github.com/FFmpeg/FFmpeg/archive/9b6c8969e05b4f0b29f0f85cd501be6b3e582e6b.tar.gz`, SHA-256 `7e779215eae16ad7e93ddad59bd82822bd3d34e4dc61f9996f9481b2c0605bc3` |
| Licenca declarada do build | LGPL-3.0-or-later (`--enable-version3`, sem `--enable-gpl`, sem `--enable-nonfree`)                                                                                                                                                                      |
| Modificacoes               | Nenhuma -- `ffmpeg-changes.diff` gerado por `git diff` contra uma baseline pristina criada logo apos extrair e verificar o tarball (nunca contra um remoto), vazio em toda execucao real                                                                 |
| Motivo de inclusao         | E o proprio software que o produto invoca via `Command` para inspecionar (`ffprobe`) e transcodificar (`ffmpeg`) video -- ver `USAGE_MATRIX.md`                                                                                                          |

## Bibliotecas internas do FFmpeg (mesma licenca, mesmo componente)

| Biblioteca      | Licenca           | Motivo de inclusao                                                                        |
| --------------- | ----------------- | ----------------------------------------------------------------------------------------- |
| `libavformat`   | LGPL-3.0-or-later | Demuxa MOV/MP4/M4V/MKV/WebM na entrada, muxa MP4 na saida -- `USAGE_MATRIX.md` secoes 4-5. Tambem demuxa Y4M/WAV (`USAGE_MATRIX.md` secao 4b), usados SOMENTE pelo baseline funcional obrigatorio do gate de CI, nunca por nenhum caso de uso real. |
| `libavcodec`    | LGPL-3.0-or-later | Decoders/encoders/parsers habilitados -- `USAGE_MATRIX.md` secoes 6-8, 11. Inclui `rawvideo` (decode-only, trivial, sem dependencia), usado so pelo baseline do gate de CI (`USAGE_MATRIX.md` secao 4b). |
| `libavutil`     | LGPL-3.0-or-later | Base obrigatoria de `libavformat`/`libavcodec`                                            |
| `libswscale`    | LGPL-3.0-or-later | Filtro `scale` e conversao automatica de `pix_fmt`                                        |
| `libswresample` | LGPL-3.0-or-later | Conversao automatica de canais/formato de amostra de audio                                |

## Biblioteca externa -- exatamente uma: dav1d

| Campo                      | Valor                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Componente                 | dav1d                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Versao/tag                 | `1.5.4` ('Sonic'), commit `191bdda98ec3c68137754dc97da1db34043d7cd4`                                                                                                                                                                                                                                                                                                                                                                                                                |
| Origem                     | Tarball fixado por URL+SHA256 em `sources.lock.json` -- `https://code.videolan.org/videolan/dav1d/-/archive/1.5.4/dav1d-1.5.4.tar.gz`, SHA-256 `a1d5b63d2d38ec9bd03acf643caa51fa22edd1e89c5a109c4807717216bbec07`                                                                                                                                                                                                                                                                   |
| Licenca                    | BSD-2-Clause                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Copyright                  | © 2018-2025, VideoLAN and dav1d authors (texto exato em `licenses/dav1d/COPYING`)                                                                                                                                                                                                                                                                                                                                                                                                   |
| Modificacoes               | Nenhuma -- `dav1d-changes.diff`, mesmo metodo do FFmpeg acima                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Compilacao                 | `meson`+`ninja`, cross-compilado para `x86_64-w64-mingw32` (`mingw-w64-x86_64-cross.meson`), `--default-library=static`, sem ferramentas/exemplos/testes/docs                                                                                                                                                                                                                                                                                                                       |
| Linkagem                   | Estatica, via `--enable-libdav1d` do FFmpeg apontado (por `PKG_CONFIG_LIBDIR`) exclusivamente para o `.pc` do dav1d recem-compilado, nunca uma copia de sistema                                                                                                                                                                                                                                                                                                                     |
| Motivo de inclusao         | Decodificar AV1 **inteiramente por software**, sem GPU. O decoder nativo `av1` do proprio FFmpeg (`libavcodec/av1dec.c`, commit acima) nunca teve caminho de decodificacao por software -- e um dispatcher hwaccel-only (D3D11VA/DXVA2/NVDEC/etc.), confirmado lendo o proprio codigo-fonte ("Since now the av1 decoder doesn't support native decode"). dav1d e a UNICA biblioteca externa necessaria para atender ao requisito da meta de decode de AV1 sem depender de hardware. |
| Prova de incorporacao real | Ver secao "Link map" abaixo -- `LOAD /build/dav1d-install/lib/libdav1d.a` no link map real, e a string `"dav1d AV1 decoder by VideoLAN"`/`"libdav1d %s"` encontrada por `strings` diretamente no binario compilado                                                                                                                                                                                                                                                                  |

Nenhuma outra biblioteca externa e usada: `libx264`, `libx265`, `libvpx`, `libaom`, `libopus`,
`libmp3lame`, `libfdk-aac`, `OpenH264`, `GMP`, `OpenSSL`, `libvmaf`, `libass`, `libjxl`, `libwebp`,
`OpenJPEG`, `rav1e`, `SVT-AV1`, `SRT` -- nenhuma aparece em `configure-flags.txt` (nenhum
`--enable-lib*` alem de `--enable-libdav1d`), `--disable-autodetect` impede deteccao silenciosa de
qualquer uma que porventura estivesse instalada no container, e o link map (abaixo) confirma que
nenhum `.a`/`.o` de nenhuma delas foi incorporado.

## Link map -- prova real do que foi incorporado (nao so `objdump -p`)

**Nota sobre como os dois link maps sao gerados de forma isolada**: gerar os dois mapas na MESMA
chamada de `make -j$NPROC` (link paralelo de `ffmpeg.exe` e `ffprobe.exe` compartilhando o mesmo
caminho de `-Wl,-Map=...`, vindo de `--extra-ldflags` do `./configure`) produz dois arquivos
BYTE-IDENTICOS (confirmavel com `cmp`), cada um contendo tanto `fftools/ffmpeg.o` quanto
`fftools/ffprobe.o`, o que invalidaria a prova (um mapa "de ffprobe" que na verdade documentaria o
link de ffmpeg tambem). Por isso `build.sh` linka cada binario numa chamada de `make`
SEPARADA e SEQUENCIAL (`make ffmpeg.exe`, depois `make ffprobe.exe`), cada uma pedindo so aquele
arquivo-alvo -- o `-Wl,-Map=...` e adicionado por cima do `LDFLAGS` real gravado pelo `configure`
(nunca sobrescrito pela linha de comando do `make`, que travaria a linha de `ffbuild/common.mak`
que prepende os `-L` de cada biblioteca interna do FFmpeg, quebrando o link com `cannot find
-lavfilter`) acrescentando uma linha nova em `ffbuild/config.mak` antes de cada chamada isolada.
`build.sh` valida (fail-high, `exit 1` se falhar) que `ffmpeg-link.map` contem `fftools/ffmpeg.o` e
NAO contem `fftools/ffprobe.o`, que `ffprobe-link.map` contem `fftools/ffprobe.o` e NAO contem
`fftools/ffmpeg.o`, e que os dois arquivos nunca sao byte-identicos -- confirmado em execucao real:
`ffmpeg-link.map` (3 079 742 bytes, SHA-256 `34b33d53...`) contem 60 ocorrencias de
`fftools/ffmpeg.o` e zero de `fftools/ffprobe.o`; `ffprobe-link.map` (3 034 493 bytes, SHA-256
`e75feecb...`) contem 32 ocorrencias de `fftools/ffprobe.o` e zero de `fftools/ffmpeg.o`. Valores
atualizados na Revisao 4 (`--enable-demuxer=yuv4mpegpipe`/`wav` + `--enable-decoder=rawvideo`) e
reconfirmados por reconstrucao Docker real nesta sessao.

`build.sh` passa `-Wl,-Map=$OUT_DIR/ffmpeg-link.map` (e o equivalente, numa chamada separada, para
`ffprobe-link.map`) para o linker do MinGW-w64 durante o link final -- o proprio GNU ld relata,
arquivo por arquivo, qual objeto/arquivo de biblioteca estatica (`.a`) foi carregado (`LOAD ...`) e
quais membros individuais (`.o` dentro de cada `.a`) foram efetivamente puxados para dentro do
executavel. Arquivos `.a`
carregados no link de `ffmpeg.exe` (extraido do link map real, nao hipotetico):

```
libavcodec.a
libavformat.a
libavutil.a
libswscale.a
libswresample.a
/build/dav1d-install/lib/libdav1d.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/libmingw32.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/libmingwex.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/libmoldname.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/libmsvcrt.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/libpthread.a       (winpthread, variante posix)
/usr/lib/gcc/.../12-posix/libgcc.a
/usr/lib/gcc/.../12-posix/libgcc_eh.a
/usr/lib/gcc/.../12-posix/libatomic.a
/usr/lib/gcc/.../x86_64-w64-mingw32/lib/lib{advapi32,bcrypt,kernel32,m,mfuuid,ole32,psapi,shell32,strmiids,user32}.a
```

Os ultimos (`libadvapi32.a`, `libbcrypt.a`, etc.) sao **stubs de importacao** do MinGW-w64 -- nao
incorporam codigo, so declaram simbolos importados das DLLs correspondentes do proprio Windows
(coerente com `ffmpeg-dll-deps.txt`: `bcrypt.dll`, `KERNEL32.dll`, `msvcrt.dll`, `ole32.dll`,
`SHELL32.dll`). Os demais (`libmingw32.a`, `libmingwex.a`, `libmoldname.a`, `libpthread.a`
[winpthread], `libgcc.a`, `libgcc_eh.a`, `libatomic.a`, `libdav1d.a`) sao codigo REAL estaticamente
incorporado ao binario final -- confirmado por `LOAD` no link map e reconfirmado por `strings`
encontrando simbolos/strings caracteristicos de cada um dentro do `.exe` compilado (ex.: a string
`"dav1d AV1 decoder by VideoLAN"` do dav1d).

## Runtime de build estaticamente incorporado (nunca distribuido separadamente, mas presente no binario)

| Componente                                                       | Licenca                                                                                                                                                                               | Origem                                                                                         | Motivo de inclusao                                                                                                                                                                                                                                                        |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `libmingwex`/`libmingw32`/`libmoldname` (runtime C do MinGW-w64) | Zope Public License (ZPL) 2.1, com partes em Dominio Publico/BSD/LGPL conforme o arquivo -- ver `licenses/MinGW-w64-runtime/`                                                         | Pacote Debian `mingw-w64-x86-64-dev=10.0.0-3` (snapshot.debian.org, ver `BUILD_MANIFEST.json`) | Runtime C padrao exigido por qualquer binario `x86_64-w64-mingw32-gcc`, linkado estaticamente via `-static`                                                                                                                                                               |
| `libwinpthread` (`libpthread.a`, variante posix)                 | MIT-style (ver `COPYING.MinGW-w64-runtime.txt`, secao winpthreads)                                                                                                                    | Mesmo pacote acima, variante `posix` fixada via `update-alternatives`                          | Suporte a threads POSIX exigido pelo FFmpeg (`pthread_*`) e pelo proprio dav1d (`win32_thread.c`)                                                                                                                                                                         |
| `libgcc`/`libgcc_eh`/`libatomic` (runtime de suporte do GCC)     | GPL-3.0-or-later **com a GCC Runtime Library Exception** -- a excecao permite linkagem estatica em binarios proprietarios/sob qualquer licenca sem propagar GPL ao binario resultante | Pacote Debian `gcc-mingw-w64-x86-64=12.2.0-14+25.2`                                            | Helpers de baixo nivel gerados pelo proprio compilador (divisao de inteiros de 64 bits, unwind de excecoes de C++ usado internamente pelo FFmpeg, operacoes atomicas) -- nunca escrito/chamado diretamente pelo codigo do produto, gerado automaticamente pelo compilador |

## Encoders habilitados (unicos dois do build)

| Encoder   | Tipo  | Origem                                                           | Motivo                                                           |
| --------- | ----- | ---------------------------------------------------------------- | ---------------------------------------------------------------- |
| `h264_mf` | Video | Nativo do Windows (Media Foundation), `--enable-mediafoundation` | Unico encoder de video chamado pelo pipeline (`ffmpeg_proxy.rs`) |
| `aac`     | Audio | Nativo do FFmpeg (`libavcodec`)                                  | Unico encoder de audio chamado pelo pipeline                     |

## Toolchain de build (nao distribuido como binario, mas seu runtime estatico E incorporado -- ver secao acima)

| Item                              | Valor                                                                                                                                                                                                                          |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Imagem base                       | `debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241` (`debian:bookworm-slim`) -- fixa o FILESYSTEM da imagem base, nao o conteudo do repositorio APT (ver correcao em `Dockerfile`/`REPRODUCE.md`) |
| Repositorio de pacotes            | `snapshot.debian.org`, timestamp imutavel `20260814T082106Z` -- nunca `deb.debian.org` (espelho movel)                                                                                                                         |
| Cross-compilador                  | `gcc-mingw-w64-x86-64=12.2.0-14+25.2` / `g++-mingw-w64-x86-64=12.2.0-14+25.2`, variante `posix` fixada via `update-alternatives`                                                                                               |
| Build de dav1d                    | `meson=1.0.1-5`, `ninja-build=1.11.1-2~deb12u1`, `python3=3.11.2-1+b1`, `nasm=2.16.01-1`                                                                                                                                       |
| Todas as versoes de pacote exatas | `BUILD_MANIFEST.json`, capturadas do proprio snapshot pinado (nao hipoteticas)                                                                                                                                                 |

## Licencas -- textos completos

- FFmpeg: `licenses/FFmpeg/COPYING.LGPLv3` (e `COPYING.GPLv3`, nao aplicavel a este build)
- dav1d: `licenses/dav1d/COPYING` (BSD-2-Clause, copiado verbatim do repositorio oficial)
- MinGW-w64 runtime: `licenses/MinGW-w64-runtime/COPYING.MinGW-w64-runtime.txt`
- GCC Runtime Library Exception: `licenses/GCC/RUNTIME.LIBRARY.EXCEPTION` (aplica-se a `libgcc`/`libgcc_eh`/`libatomic`)
