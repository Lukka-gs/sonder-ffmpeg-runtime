# Matriz de capacidades habilitadas

Este documento descreve exatamente o que a configuração deste build mínimo habilita e por quê --
nenhum componente foi habilitado "por garantia" sem uma justificativa concreta registrada aqui.
Este repositório **não contém nenhum aplicativo consumidor** -- é só o runtime `ffmpeg.exe`/
`ffprobe.exe` em si; a matriz abaixo reflete as capacidades do binário, não o uso de nenhuma
aplicação específica.

## 1. `ffprobe` -- inspeção de metadados

```
ffprobe -v error -print_format json -show_format -show_streams <input>
```

Não decodifica nenhum quadro (`-show_frames`/`-count_frames` não são habilitados) -- só precisa que
o **demuxer** exponha os metadados do container/stream, não de decoders completos.

## 2. `ffmpeg` -- transcodificação para H.264/AAC

```
ffmpeg -y -i <input> \
  -map 0:v:0 [-map 0:a:0] \
  -vf scale=<w>:<h> \
  -c:v h264_mf -pix_fmt nv12 -hw_encoding <0|1> \
  -movflags +faststart -f mp4 \
  [-c:a aac -ac 2 -b:a 160k | -an] \
  -nostats -loglevel error -progress pipe:2 \
  <output>.mp4
```

Um único encoder de vídeo (`h264_mf`, Media Foundation nativo do Windows) e um único de áudio
(`aac` nativo, nunca `libfdk_aac`). Sempre muxer `mp4`. Sempre filtro `scale`.

## 3. O que o binário precisa suportar

- `ffmpeg -version` reporta a linha `configuration:`, sem `--enable-gpl`/`--enable-nonfree` nem
  nenhum dos componentes proibidos (ver `BUILD_MANIFEST.json`).
- `ffmpeg -encoders` lista `h264_mf` e `aac`.
- Nenhum protocolo de rede é usado em nenhum caso de uso pretendido: toda entrada/saída é caminho
  de arquivo local, nunca uma URL.

## 4. Contêineres de entrada suportados

| Extensão               | Demuxer FFmpeg necessário               |
| ----------------------- | --------------------------------------- |
| `.mp4`, `.mov`, `.m4v` | `mov` (grupo `mov,mp4,m4a,3gp,3g2,mj2`) |
| `.mkv`, `.webm`        | `matroska` (grupo `matroska,webm`)      |

## 4b. Demuxers adicionais -- só para o gate funcional de CI, nunca para uso real

| Extensão | Demuxer FFmpeg necessário | Decoder necessário | Por quê |
| -------- | -------------------------- | -------------------- | ------- |
| `.y4m`   | `yuv4mpegpipe`             | `rawvideo`            | Entrada de vídeo do baseline funcional obrigatório (ver `scripts/verify-functional.ps1` e `scripts/generate-baseline-fixture.mjs`) -- gerada programaticamente, sem depender de nenhum ffmpeg de sistema no runner de CI. |
| `.wav`   | `wav`                      | `pcm_s16le` (já habilitado pela seção 7) | Entrada de áudio do mesmo baseline. |

Achado real (confirmado executando o `ffmpeg.exe` candidato, não só por inspeção do
`configure-flags.txt`): antes desta revisão, só `mov` e `matroska` estavam habilitados, e o
candidato rejeitava a própria entrada do gate de CI com `Invalid data found when processing
input`. As três flags adicionadas (`--enable-demuxer=yuv4mpegpipe`, `--enable-demuxer=wav`,
`--enable-decoder=rawvideo`) são decode-only e não introduzem nenhuma biblioteca externa nem
componente GPL/nonfree -- `yuv4mpegpipe`/`wav` são demuxers triviais do próprio `libavformat`, e
`rawvideo` é um decoder trivial do próprio `libavcodec`, sem nenhuma dependência. Nenhum caso de
uso real (fora do gate de CI) produz ou consome `.y4m`/`.wav`.

## 5. Contêiner/muxer de saída

Sempre `.mp4` (`-f mp4`, `-movflags +faststart`) → muxer `mp4`. **Achado real durante a
integração**: ao contrário do demuxer (onde `mov` sozinho já cobre mp4/mov/m4v/3gp na leitura), o
FFmpeg registra os nomes de muxer `mov`/`mp4`/`ipod`/`3gp` como entradas SEPARADAS de
`--enable-muxer`, mesmo compartilhando a mesma implementação interna (`movenc.c`) --
`--enable-muxer=mov` sozinho não habilita `-f mp4` (`Requested output format 'mp4' is not known`).
O build precisa de `--enable-muxer=mp4` explicitamente.

## 6. Codecs de vídeo de ENTRADA suportados (decode-only)

| Codec         | Decoder FFmpeg                     | Precisa de lib externa?                                                 |
| ------------- | ----------------------------------- | ----------------------------------------------------------------------- |
| H.264         | `h264` (nativo, LGPL)              | Não -- decode nunca precisa de `libx264` (só o ENCODER `libx264` é GPL) |
| HEVC          | `hevc` (nativo, LGPL)              | Não -- decode nunca precisa de `libx265`                                |
| MPEG-4 part 2 | `mpeg4` (nativo, LGPL)             | Não                                                                     |
| VP8           | `vp8` (nativo, LGPL)                | Não -- FFmpeg tem decoder VP8 próprio, sem `libvpx`                     |
| VP9           | `vp9` (nativo, LGPL)                | Não -- FFmpeg tem decoder VP9 próprio, sem `libvpx`                     |
| AV1           | `libdav1d` (externo, BSD-2-Clause) | **Sim** -- ver nota abaixo                                              |
| ProRes        | `prores` (nativo, LGPL)             | Não                                                                     |
| DNxHD/DNxHR   | `dnxhd` (nativo, LGPL)              | Não                                                                     |

Sete dos oito codecs não exigem nenhuma biblioteca externa: implementação nativa dentro do próprio
`libavcodec` do FFmpeg, mesma licença LGPL. **AV1 é a exceção**: o decoder NATIVO `av1` do próprio
FFmpeg (`libavcodec/av1dec.c`, mesmo commit fixado neste build) nunca teve caminho de decodificação
por software -- é um dispatcher exclusivo para hwaccel (D3D11VA/DXVA2/NVDEC/VAAPI/VDPAU/
VideoToolbox/Vulkan/D3D12VA conforme a plataforma), confirmado lendo o próprio código-fonte
upstream (comentário: _"Since now the av1 decoder doesn't support native decode"_). Habilitar
hwaccel D3D11VA para o decoder nativo funciona em princípio, mas depende de GPU/driver, o que não
é aceitável como solução geral para um runtime que precisa funcionar em qualquer máquina Windows
x64. Por isso este build usa **`dav1d`** (BSD-2-Clause, única biblioteca externa deste build, fonte
fixada por hash em `sources.lock.json`) -- decodifica AV1 inteiramente por software, sem GPU. Ver
`SBOM.md` para o motivo completo de inclusão. `libvpx`, `libaom`, `libx264`, `libx265` continuam
desnecessários -- só seriam usados para **codificar** nesses formatos, e este build nunca codifica
em nenhum deles (sempre reencoda para H.264 via `h264_mf`).

## 7. Codecs de áudio de ENTRADA suportados (decode-only)

| Codec | Decoder FFmpeg                                                                                                                       | Precisa de lib externa?                                    |
| ----- | -------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| AAC   | `aac` (nativo, LGPL)                                                                                                                    | Não                                                          |
| MP3   | `mp3`/`mp3float` (nativo, LGPL)                                                                                                          | Não -- decode nunca precisa de `libmp3lame` (só o encoder) |
| Opus  | `opus` (nativo, LGPL)                                                                                                                    | Não -- FFmpeg tem decoder Opus próprio, sem `libopus`      |
| PCM   | `pcm_s16le`, `pcm_s16be`, `pcm_s24le`, `pcm_s24be`, `pcm_s32le`, `pcm_u8`, `pcm_f32le`, `pcm_alaw`, `pcm_mulaw` (todos nativos) | Não                                                          |

## 8. Codecs de saída (encode-only)

| Fluxo | Encoder        | Habilitação                                             |
| ----- | -------------- | ------------------------------------------------------- |
| Vídeo | `h264_mf`      | `--enable-mediafoundation` + `--enable-encoder=h264_mf` |
| Áudio | `aac` (nativo) | `--enable-encoder=aac`                                  |

Nenhum outro encoder é habilitado neste build.

## 9. Filtros

Só `scale` (`-vf scale=W:H`). A conversão implícita de formato de pixel (decodificado →
`nv12`/`yuv420p`) e de amostragem de áudio (`-ac 2`) é feita pelas bibliotecas internas
`libswscale`/`libswresample`, sempre habilitadas por padrão com qualquer decoder/encoder de
vídeo/áudio -- não são "filtros" adicionais a habilitar via `--enable-filter`.

## 10. Protocolos

`file` para entrada/saída (nunca uma URL) e `pipe` para `-progress pipe:2` (reporta progresso pelo
descritor 2, já aberto pelo processo pai; nunca abre conexão nenhuma, apesar do nome). **Achado
real**: o protocolo `pipe` só foi descoberto como necessário ao rodar o build real contra os
argumentos de transcodificação (a primeira tentativa falhou com `Protocol not found` para
`pipe:2`) -- corrigido em `configure-flags.txt`. Rede completamente desabilitada
(`--disable-network`) -- este runtime nunca baixa nada em tempo de execução.

## 11. Parsers

Um parser por decoder de vídeo/áudio comprimido habilitado (permite remuxagem/rechunking correto
de pacotes antes de entregar ao decoder): `h264`, `hevc`, `mpeg4video`, `vp8`, `vp9`, `av1`, `aac`,
`mpegaudio` (MP3), `opus`.

## 12. Resumo -- nada habilitado "por garantia"

Toda linha das tabelas acima corresponde a um caso de uso real e testado (seções 1-3) ou a suporte
explícito a formatos profissionais de entrada (seções 6-7). Exatamente **uma** biblioteca externa é
necessária (`dav1d`, para decodificar AV1 por software -- ver seção 6 e `SBOM.md`); nenhuma outra
(`libx264`, `libx265`, `libvpx`, `libaom`, `libopus`, `libmp3lame`, `libfdk-aac`, `OpenH264`, `GMP`,
`OpenSSL`, `libvmaf`, `libass`, `libjxl`, `libwebp`, `OpenJPEG`, `rav1e`, `SVT-AV1`, `SRT` etc.) é
necessária para nenhum item desta matriz -- todos os outros decoders/encoders têm implementação
nativa dentro do próprio FFmpeg (`libavcodec`), diferente de builds genéricos que embutem dezenas
de bibliotecas de terceiros nunca usadas por este caso de uso.
