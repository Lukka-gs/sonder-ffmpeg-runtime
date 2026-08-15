# Relatório de validação do runtime FFmpeg mínimo LGPL + dav1d

Consolida a evidência empírica coletada durante a construção deste build (fontes imutáveis, AV1
por software via dav1d, SBOM com link map, empacotamento de código-fonte determinístico e
autossuficiente).

## 1. Correções aplicadas durante o desenvolvimento

1. **Link maps não isolados**: `ffmpeg-link.map` e `ffprobe-link.map` eram gerados na MESMA
   chamada de `make -j$NPROC` (link paralelo compartilhando o mesmo caminho de `-Wl,-Map=...`) —
   os dois arquivos resultantes eram byte-idênticos (confirmado com `cmp`), cada um contendo tanto
   `fftools/ffmpeg.o` quanto `fftools/ffprobe.o`. Corrigido: cada binário agora é linkado numa
   chamada de `make` isolada e sequencial (`make ffmpeg.exe`, depois `make ffprobe.exe`), com o
   caminho do map acrescentado por cima do `LDFLAGS` real (via uma linha nova em
   `ffbuild/config.mak`, nunca sobrescrito pela linha de comando do `make`, que quebrava o link
   com `cannot find -lavfilter` ao bloquear a linha de `common.mak` que prepende os `-L` internos).
   `build.sh` agora valida fail-high (`exit 1`) que cada mapa contém o objeto-raiz correto e não
   contém o do outro binário, e que os dois nunca são byte-idênticos. Confirmado em execução real:
   `ffmpeg-link.map` contém `fftools/ffmpeg.o` (60x) e zero `fftools/ffprobe.o`; `ffprobe-link.map`
   contém `fftools/ffprobe.o` (32x) e zero `fftools/ffmpeg.o`. Ver `SBOM.md`, seção "Link map".
2. **Pacote de código-fonte incompleto**: montado dentro do container (`build.sh`), só alcançava o
   contexto do Docker — nunca `docs/`/`licenses/` (SBOM, manifesto, instruções de reprodução,
   textos de licença), então não podia ser autossuficiente por construção. Corrigido com
   `package-source.sh`, rodando no host, alcançando os três diretórios; o `Dockerfile` também
   vendoriza as fontes (`COPY sources/ /build/vendored-sources/`) para que o pacote extraído
   consiga reconstruir sem rede para as fontes de FFmpeg/dav1d.
3. **Gate de validação não fail-high de verdade**: uma checagem de disponibilidade do candidato
   usava `.ok()?` para consultar `-encoders`, convertendo qualquer erro (candidato existe como
   arquivo mas não é executável, ou falha ao rodar) num "ausente" silencioso — o mesmo efeito de
   "não configurado". Corrigido para distinguir explicitamente "ausente" (pula) de "presente mas
   quebrado" (falha alto quando o modo de validação formal está ativo).
4. **Ordem do tar sensível a locale**: regenerar o pacote a partir da MESMA árvore em ambientes
   com locale diferente (uma sessão com `C.UTF-8` vs o Git Bash do Windows com `pt_BR.UTF-8`)
   produzia SHA-256 **diferentes**, apesar do conteúdo interno ser idêntico — causa raiz: `sort`
   (usado para fixar a ordem dos arquivos antes de gerar o tar) é sensível ao locale ativo do
   shell, sem `LC_ALL` fixado a ordem de colação podia divergir (`README.md` antes de `docs/` num
   ambiente, o inverso no outro). Corrigido fixando `LC_ALL=C`/`LANG=C`/`TZ=UTC` no topo de
   `package-source.sh` (afeta todo comando do processo) e reforçando `LC_ALL=C` explicitamente na
   própria chamada de `sort`; formato de tar também fixado explicitamente (`--format=gnu`).
   Confirmado com **4 gerações independentes** (2 numa sessão Linux/`C.UTF-8`, 2 via
   `bash.exe` do Git for Windows com `LANG=pt_BR.UTF-8`): mesmo SHA-256 nas 4, mesma ordem em
   `tar -tzf`, mesmo SHA-256 recursivo da árvore extraída nas 4.
5. **Baseline funcional obrigatório rejeitado pelo próprio candidato**: o gate de CI passou a gerar
   uma entrada mínima e determinística (Y4M+WAV, via `scripts/generate-baseline-fixture.mjs`) para
   não depender de nenhum ffmpeg de sistema no runner — mas o candidato real, executado localmente,
   rejeitava essa entrada com `Invalid data found when processing input`. Causa raiz confirmada
   executando o `ffmpeg.exe` real (não só por inspeção do `configure-flags.txt`): `ffmpeg -demuxers`
   só listava `matroska,webm` e `mov,mp4,m4a,3gp,3g2,mj2` — nenhum demuxer capaz de ler `.y4m`/`.wav`
   estava habilitado. Corrigido adicionando `--enable-demuxer=yuv4mpegpipe`,
   `--enable-demuxer=wav` e `--enable-decoder=rawvideo` — todos decode-only, sem biblioteca externa
   nem componente GPL/nonfree (`pcm_s16le`, usado pelo WAV, já estava habilitado). Reconstruído e
   revalidado end-to-end contra os binários reais resultantes: `ffmpeg -demuxers` agora lista `wav`
   e `yuv4mpegpipe`; o gate funcional completo (`scripts/verify-functional.ps1`) passou, incluindo a
   conversão real do baseline para MP4 H.264 (`h264_mf`, log confirma `MFT name: 'H264 Encoder MFT'`
   — encoder de software real, não simulado) + AAC, validada por `ffprobe.exe`.

## 2. Fontes imutáveis

FFmpeg e dav1d são baixados como tarball fixo por URL+SHA256 (`sources.lock.json`), verificados
ANTES de extrair (`build.sh` recusa continuar se o hash não bater) — nunca `git fetch` contra um
remoto móvel. Um pacote determinístico de código-fonte correspondente
(`sonder-ffmpeg-source.tar.gz`, gerado por `package-source.sh` no host, nunca commitado) reúne os
dois tarballs originais, o pipeline de build completo, os dois `changes.diff` (ambos vazios,
provando zero modificação sobre o upstream) e toda a documentação (licenças, SBOM, manifesto,
instruções de reprodução).

## 3. APT fixado por snapshot

O digest da imagem base fixa apenas o filesystem publicado da imagem, nunca o conteúdo do
repositório APT consultado depois por `apt-get update`/`install` (que por padrão aponta para
espelhos móveis). Corrigido: as fontes APT são substituídas por uma única fonte fixa em
`snapshot.debian.org`, timestamp imutável; cada pacote principal é instalado com a versão exata
fixada explicitamente (`apt-get install pacote=versão`). Testado: reconstruir a imagem meses
depois usa exatamente as mesmas versões — falha alto se o snapshot pinado não servir mais a versão
exata.

## 4. AV1 por software via dav1d

**Achado**: o decoder nativo `av1` do próprio FFmpeg nunca teve caminho de decodificação por
software — é hwaccel-only por design upstream (dispatcher exclusivo para D3D11VA/DXVA2/NVDEC/
VAAPI/VDPAU/VideoToolbox/Vulkan/D3D12VA, conforme a plataforma).

**Alternativa descartada**: habilitar hwaccel D3D11VA para o decoder nativo funciona em princípio,
mas depende de GPU/driver — inaceitável como solução geral para um runtime que precisa funcionar
em qualquer máquina Windows x64.

**Solução aplicada**: `dav1d` (BSD-2-Clause) — única biblioteca externa deste build — compilado
estaticamente via meson+ninja (cross-compilado para `x86_64-w64-mingw32`) e linkado ao FFmpeg via
`--enable-libdav1d --enable-decoder=libdav1d` (o decoder nativo `av1` não é habilitado, então só
`libdav1d` responde pelo codec AV1 — a escolha do decoder é automática, sem exigir nenhum
argumento explícito de linha de comando). Decodifica **inteiramente por software, sem GPU**.

Validado numa máquina sem D3D11 utilizável: decodificação de um arquivo AV1 real, reencodado com
sucesso para H.264/AAC.

## 5. Configuração compilada (buildconf real)

`ffmpeg -buildconf` confirma exatamente `configure-flags.txt` — nenhuma flag adicional. Nenhuma
ocorrência de `--enable-gpl`, `--enable-nonfree`, `x264`, `x265`, `xvid`, `fdk`, `openh264`, `lame`,
`openssl`, `gmp`. `-decoders` lista `libdav1d` (não o `av1` nativo) como único decoder AV1;
`-encoders` lista exatamente `h264_mf` e `aac`; `-hwaccels` lista `d3d11va` como método genérico
disponível (necessário só para compilar o encoder `h264_mf`), mas `configure.log` confirma
`Enabled hwaccels:` vazio — nenhum decoder deste build negocia hwaccel.

## 6. SBOM com prova real (link map)

`objdump -p` só prova ausência de DLL **dinâmica** — nunca de biblioteca **estática**. `build.sh`
gera o link map real do linker (`-Wl,-Map=...`) para `ffmpeg.exe`/`ffprobe.exe`, mostrando
exatamente quais `.a`/`.o` foram incorporados: `libavcodec/avformat/avutil/swscale/swresample.a`
(FFmpeg), `libdav1d.a` (a única externa), o runtime MinGW-w64 (`libmingw32/mingwex/moldname`,
`libpthread`=winpthread), o runtime de suporte do GCC (`libgcc/libgcc_eh/libatomic`, cobertos pela
GCC Runtime Library Exception) e stubs de importação do Windows (`libbcrypt`, `libole32` etc., sem
código, só declaração de símbolos). Ver `SBOM.md` para a tabela completa com licença/origem/motivo
de cada item.

## 7. Reprodutibilidade — dois builds byte-idênticos

Ao integrar dav1d, os dois builds pararam de ser byte-idênticos. Causa raiz: o `meson.build` do
dav1d roda `git describe --long --always` contra o repositório git local (criado pelo `build.sh`
como baseline para diff, nunca contatando um remoto) para gerar `include/vcs_version.h`, embutido
no binário. Sem uma data de commit fixa, cada execução criava um commit com hash diferente,
tornando `git describe` (e portanto os binários) NÃO byte-idênticos entre execuções, mesmo com o
mesmo código-fonte. Corrigido fixando `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` em
`SOURCE_DATE_EPOCH`.

```
ffmpeg.exe:        40d012779b85fab5415aa018a501ec405a46cba17392877f882b598c7f0598f6  (build1 == build2)
ffprobe.exe:       3e0074d115a2d7af5cced6125d8e49240c656ec2484ad5973a330438fd265b4b  (build1 == build2)
ffmpeg-link.map:   34b33d53c889addf2832e8c45fe459e66ae96a37a27dea246b4efe9cd68ff989  (build1 == build2, distinto de ffprobe-link.map)
ffprobe-link.map:  e75feecbbc807b4d6859dd9ef01d39b8715665ae65f6b2fe468b23656f9bea9d  (build1 == build2, distinto de ffmpeg-link.map)
```

`cmp` byte a byte confirmou identidade total (nenhuma divergência reportada). Hashes acima
atualizados nesta revisão (Revisão 4: `--enable-demuxer=yuv4mpegpipe`/`wav` +
`--enable-decoder=rawvideo`, ver `BUILD_MANIFEST.json`) e reconfirmados por uma reconstrução Docker
real completa (`docker build` + dois `docker run` independentes) nesta sessão, não apenas
recalculados por inspeção.

**Pacote-fonte (`sonder-ffmpeg-source.tar.gz`) gerado independentemente de `out1` e `out2`**: nesta
revisão, `verify.yml`/`release.yml` foram corrigidos para que a segunda geração leia a evidência do
SEU PRÓPRIO build (`out2/sources/*.tar.gz`, `out2/*-changes.diff`), nunca a mesma evidência de
`out1` duas vezes. SHA-256 do pacote (idêntico entre as duas gerações independentes):
`c8bbd07f7a57bcbef6edac579a37a1592d5dff2d8f6eba05b963a58f5fc492ea`. Confirmado também que
`out1/sources/{ffmpeg,dav1d}.tar.gz` e `out1/{ffmpeg,dav1d}-changes.diff` são byte-idênticos aos
equivalentes de `out2` (`cmp`), provando que os dois builds independentes obtiveram e processaram
exatamente a mesma fonte.

**Nota sobre o hash do pacote-fonte (`sonder-ffmpeg-source.tar.gz`)**: este próprio documento é um
dos arquivos incluídos dentro do pacote — registrar aqui o SHA-256 do `.tar.gz` seria uma
autorreferência (o hash muda toda vez que este texto muda, o que muda o conteúdo do pacote, o que
muda o hash de novo, indefinidamente). Confirmado apenas que **gerações independentes, a partir da
mesma árvore (inclusive em ambientes com locale diferente), produzem SHA-256 idêntico entre si** —
o valor concreto do hash é publicado externamente, nunca dentro do pacote: `package-source.sh`
grava `sonder-ffmpeg-source.tar.gz.sha256` ao lado do `.tar.gz` (mesmo diretório, fora do pacote).

## 8. Matriz de fixtures — 8 codecs × 5 contêineres

Todos os 12 casos de teste (incluindo AV1) transcodificaram com sucesso pelos argumentos reais de
transcodificação (ver `USAGE_MATRIX.md`, seção 2) contra o binário final:

| Fixture                                  | Contêiner | Codec vídeo                   | Codec áudio | Resultado              |
| ----------------------------------------- | --------- | ------------------------------ | ----------- | ----------------------- |
| `h264_aac_1080p.mp4` / `_long.mp4` (45s) | mp4       | H.264                          | AAC         | OK -- h264/aac         |
| `hevc_aac.mkv`                           | mkv       | HEVC                           | AAC         | OK -- h264/aac         |
| `mpeg4_mp3.mov`                          | mov       | MPEG-4 part2                   | MP3         | OK -- h264/aac         |
| `vp8_opus.webm`                          | webm      | VP8                            | Opus        | OK -- h264/aac         |
| `vp9_opus.webm`                          | webm      | VP9                             | Opus        | OK -- h264/aac         |
| `av1_opus.mkv`                           | mkv       | **AV1 (via dav1d, software)** | Opus        | OK -- h264/aac         |
| `prores_pcm.mov`                         | mov       | ProRes                          | PCM s16le   | OK -- h264/aac         |
| `dnxhd_pcm.mov`                          | mov       | DNxHD                           | PCM s16le   | OK -- h264/aac         |
| `no_audio.mp4`                           | mp4       | H.264                           | (nenhum)    | OK -- h264 (sem áudio) |
| `rotated_90.m4v`                         | m4v       | H.264 (rotate=90)               | AAC         | OK -- h264/aac         |
| `fractional_fps.mp4` (23.976fps)         | mp4       | H.264                           | AAC         | OK -- h264/aac         |
| `vfr.mp4` (VFR)                          | mp4       | H.264                           | AAC         | OK -- h264/aac         |

**12/12 — todos os 8 codecs de vídeo, sem nenhuma ressalva de hardware.**

## 9. Referências

- Configuração completa comentada: [`../build/configure-flags.txt`](../build/configure-flags.txt)
- Fontes fixadas: [`../build/sources.lock.json`](../build/sources.lock.json)
- Matriz de capacidades: [`USAGE_MATRIX.md`](USAGE_MATRIX.md)
- SBOM (com link map): [`SBOM.md`](SBOM.md)
- Manifesto estruturado: [`BUILD_MANIFEST.json`](BUILD_MANIFEST.json)
- Instruções de reprodução: [`REPRODUCE.md`](REPRODUCE.md)
