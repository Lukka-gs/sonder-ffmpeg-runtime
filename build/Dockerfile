# D8.3A - Ambiente de build reproduzivel para o FFmpeg minimo LGPL + dav1d,
# cross-compilado no Linux para Windows x86_64 via MinGW-w64.
#
# CORRECAO (revisao pos-auditoria): a versao anterior deste Dockerfile
# afirmava, incorretamente, que fixar a imagem base por DIGEST tambem fixava
# o conteudo do repositorio APT ("o digest acima ja fixa o conteudo do
# repositorio apt no momento em que a imagem foi publicada"). Isso e FALSO --
# o digest da imagem fixa apenas o filesystem da imagem base (glibc, apt,
# dpkg, etc. no estado em que foram publicados), nunca o conteudo do
# repositorio remoto que `apt-get update`/`apt-get install` consultam depois:
# esses continuam apontando para espelhos MOVEIS (`deb.debian.org`) por
# padrao, que mudam de conteudo a cada nova versao de pacote publicada pelo
# Debian -- reconstruir esta imagem em outra data, com os MESMOS comandos,
# podia silenciosamente instalar versoes de pacote diferentes.
#
# CORRIGIDO: as fontes do APT sao reescritas para apontar EXCLUSIVAMENTE para
# um snapshot imutavel do arquivo Debian (snapshot.debian.org), fixado por
# timestamp -- nunca para os espelhos moveis padrao -- e cada pacote
# principal e instalado com a versao exata fixada explicitamente
# (`apt-get install pacote=versao`), nao apenas "o que o snapshot tiver".
# Testado e documentado em docs/REPRODUCE.md que
# reconstruir esta imagem depois (mesmo com o arquivo live do Debian ja
# tendo avancado) usa exatamente estas mesmas versoes -- nao redescoberto a
# cada build.
ARG BASE_IMAGE_DIGEST=debian@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241
FROM ${BASE_IMAGE_DIGEST}

# Timestamp do snapshot Debian usado para TODOS os pacotes deste build.
# Documentado (nao escondido) em BUILD_MANIFEST.json e REPRODUCE.md.
ARG DEBIAN_SNAPSHOT_TIMESTAMP=20260814T082106Z

# 1. Substitui as fontes APT da imagem base (que, na imagem oficial bookworm,
# usam o formato DEB822 em /etc/apt/sources.list.d/debian.sources apontando
# para deb.debian.org, um espelho MOVEL) por uma unica fonte apontando
# exclusivamente para o snapshot imutavel acima. `check-valid-until=no`
# porque um snapshot historico tem `Valid-Until` no passado ao ser
# reconstruido meses depois -- isto NAO reintroduz um espelho movel, o
# conteudo do snapshot em si nunca muda depois de publicado pelo proprio
# snapshot.debian.org. HTTP (nao HTTPS) de proposito: snapshot.debian.org
# aceita ambos, e usar HTTP evita qualquer dependencia circular de
# `ca-certificates` para o boostrap inicial do apt (a integridade real vem
# da assinatura GPG do Release, verificada pelas chaves ja embutidas na
# propria imagem base, nao do TLS).
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf 'deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/%s bookworm main\n' \
        "${DEBIAN_SNAPSHOT_TIMESTAMP}" > /etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update

# 2. Cada pacote principal do toolchain com a VERSAO EXATA fixada
# explicitamente -- capturada do proprio snapshot acima (nao um numero
# hipotetico) e registrada em BUILD_MANIFEST.json. Se o snapshot algum dia
# deixar de servir exatamente esta versao para este timestamp, o
# `apt-get install pacote=versao` falha alto (erro, nao silenciosamente
# resolve outra versao) -- essa e a garantia de reprodutibilidade real.
RUN apt-get -o Acquire::Check-Valid-Until=false install -y --no-install-recommends \
        ca-certificates=20230311+deb12u1 \
        git=1:2.39.5-0+deb12u3 \
        make=4.3-4.1 \
        pkg-config=1.8.1-1 \
        yasm=1.3.0-4 \
        nasm=2.16.01-1 \
        mingw-w64=10.0.0-3 \
        mingw-w64-common=10.0.0-3 \
        mingw-w64-x86-64-dev=10.0.0-3 \
        binutils-mingw-w64-x86-64=2.40-2+10.4 \
        gcc-mingw-w64-x86-64=12.2.0-14+25.2 \
        g++-mingw-w64-x86-64=12.2.0-14+25.2 \
        gcc=4:12.2.0-3 \
        g++=4:12.2.0-3 \
        libc6-dev=2.36-9+deb12u14 \
        meson=1.0.1-5 \
        ninja-build=1.11.1-2~deb12u1 \
        python3=3.11.2-1+b1 \
        python3-minimal=3.11.2-1+b1 \
        curl=7.88.1-10+deb12u15 \
    && rm -rf /var/lib/apt/lists/* \
    # O pacote Debian oferece duas variantes de runtime (posix/win32) via
    # update-alternatives; a ordem de instalacao dos pacotes pode deixar
    # qualquer uma delas ativa por ultimo, o que seria uma fonte de
    # nao-determinismo entre execucoes do MESMO Dockerfile. Fixamos "posix"
    # explicitamente (variante com suporte a std::thread/pthreads completo,
    # a mais comum em builds mingw-w64 do FFmpeg).
    && update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix \
    && update-alternatives --set x86_64-w64-mingw32-g++ /usr/bin/x86_64-w64-mingw32-g++-posix

WORKDIR /build

# Reproduzibilidade: nunca depender de relogio de parede real.
ENV SOURCE_DATE_EPOCH=1700000000
ENV TZ=UTC
ENV LC_ALL=C

COPY build.sh /build/build.sh
COPY configure-flags.txt /build/configure-flags.txt
COPY sources.lock.json /build/sources.lock.json
COPY mingw-w64-x86_64-cross.meson /build/mingw-w64-x86_64-cross.meson

# Fontes vendorizadas (FFmpeg/dav1d), quando presentes no contexto de build --
# `sources/` sempre existe (rastreado via `sources/.gitkeep`), populado com os
# dois tarballs reais ao rodar `docker build` a partir do pacote de
# codigo-fonte extraido (secao "Pacote de codigo-fonte" de REPRODUCE.md) --
# torna esse pacote AUTOSSUFICIENTE (build.sh usa a copia local, sem rede,
# ver "fetch_and_verify" em build.sh). Num `docker build` normal a partir do
# repositorio (build/sources/ so com o placeholder), build.sh cai para `curl`
# contra a URL fixada em sources.lock.json -- mesma verificacao de hash nos
# dois casos.
COPY sources/ /build/vendored-sources/

ENTRYPOINT ["/build/build.sh"]
