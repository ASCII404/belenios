# =============================================================================
# Belenios – Production Docker Image
# Source: https://github.com/glondu/belenios
#
# IMPORTANT BUILD NOTE:
#   opam-bootstrap.sh uses bubblewrap sandboxing which requires user namespaces.
#   Docker build disables namespaces by default, so we patch the bootstrap
#   script to pass --disable-sandboxing to opam init.
#
#   Build:
#     docker build --build-arg BELENIOS_VERSION=master -t belenios:latest .
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: builder
# Installs all OCaml/OPAM deps and compiles Belenios from source.
# ~30 min / ~3.3 GB on first run – heavily cached on rebuilds.
# -----------------------------------------------------------------------------
FROM debian:12 AS builder

ARG BELENIOS_VERSION=master
ARG BELENIOS_REPO=https://github.com/glondu/belenios.git

ENV DEBIAN_FRONTEND=noninteractive
ENV BELENIOS_SYSROOT=/root/.belenios

# System build dependencies (from upstream INSTALL.md)
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    bubblewrap \
    build-essential \
    ca-certificates \
    cracklib-runtime \
    git \
    jq \
    libgd-securityimage-perl \
    libgmp-dev \
    libncurses-dev \
    libsodium-dev \
    libsqlite3-dev \
    libssl-dev \
    m4 \
    npm \
    pkg-config \
    rsync \
    unzip \
    wget \
    zip \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Clone at requested version
# Use local source code
WORKDIR /src/belenios
COPY . .
RUN git init && git add . && \
    git -c user.email="build@local" -c user.name="Build" commit -m "local build" && \
    git tag 3.1

WORKDIR /src/belenios

# Patch opam-bootstrap.sh: disable opam sandboxing (bubblewrap namespaces are
# blocked inside docker build). Fix documented in github.com/glondu/belenios/issues/35
RUN sed -i 's/opam init \(.*\)--bare/opam init \1--disable-sandboxing --bare/' opam-bootstrap.sh

# Bootstrap self-contained OCaml + OPAM + all OCaml library deps
RUN ./opam-bootstrap.sh

# Build the release web server → output lands in _run/usr/
RUN . ${BELENIOS_SYSROOT}/env.sh && make build-release-server

# Create source tarball required by AGPL §13 (referenced in ocsigenserver.conf)
RUN . ${BELENIOS_SYSROOT}/env.sh && make archive || true

# -----------------------------------------------------------------------------
# Stage 2: runtime
# Minimal image – only compiled binaries + runtime shared libs.
# -----------------------------------------------------------------------------
FROM debian:12-slim AS runtime

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    ca-certificates \
    libgmp10 \
    libsodium23 \
    libsqlite3-0 \
    libssl3 \
    netcat-openbsd \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Non-root service user
RUN groupadd --gid 1000 belenios && \
    useradd --uid 1000 --gid belenios --shell /bin/sh --create-home belenios

# Compiled server installation
COPY --from=builder /src/belenios/_run/usr          /opt/belenios/usr
COPY --from=builder /src/belenios/demo              /opt/belenios/demo
# AGPL source tarball (served at /static/source.tar.gz by ocsigenserver)
COPY --from=builder /src/belenios/belenios.tar.gz   /opt/belenios/belenios.tar.gz

# Runtime data dirs (spool, logs, uploads, lib/ocsidb)
RUN mkdir -p /data/spool /data/log /data/upload /data/lib /data/config && \
    chown -R belenios:belenios /data /opt/belenios

ENV PATH="/opt/belenios/usr/bin:${PATH}"

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER belenios
WORKDIR /data

# ocsigenserver default port
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD nc -z localhost 8001 || exit 1

ENTRYPOINT ["/entrypoint.sh"]
