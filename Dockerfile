# syntax=docker/dockerfile:1

# ---- Stage 1: Build ----
FROM elixir:1.15-otp-26-alpine AS builder

# Build-time packages
# vips-dev and friends are needed to compile the vix NIF from source (PLATFORM_PROVIDED_LIBVIPS mode)
RUN apk add --no-cache \
  git \
  make \
  gcc \
  musl-dev \
  nodejs \
  npm \
  vips-dev \
  glib-dev \
  expat-dev \
  libpng-dev \
  libjpeg-turbo-dev \
  libwebp-dev

WORKDIR /app

# Use PLATFORM_PROVIDED_LIBVIPS so vix compiles against system libvips (musl-safe)
# rather than the bundled glibc precompiled NIF, which cannot load on Alpine
ENV VIX_COMPILATION_MODE=PLATFORM_PROVIDED_LIBVIPS
ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Fetch and compile dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy config, priv (Gettext reads priv/gettext at compile time), and lib, then compile
COPY config config/
COPY priv priv/
COPY lib lib/
RUN mix compile

# Copy assets and build for production (assets.deploy writes digested files into priv/static)
COPY assets assets/
RUN mix assets.deploy

# Build the release
RUN mix release

# ---- Stage 2: Runtime ----
FROM alpine:3.19 AS runner

# Runtime packages
# libvips: required by the image/vix library at runtime
# libgcc: required by the vix NIF compiled against GCC (Alpine musl build)
# fuse3: required by LiteFS for the FUSE filesystem
RUN apk add --no-cache \
  libvips \
  libgcc \
  fuse3 \
  openssl \
  ncurses-libs \
  ca-certificates

WORKDIR /app

# Copy the compiled release from builder
COPY --from=builder /app/_build/prod/rel/scientia_cognita ./

# Install LiteFS binary (pinned to v0.5.11)
ARG LITEFS_SHA256=3800856259f55ce0a47db30183fd840ec85d45ce998a3eb4e6a45b9ee5adf3b0
RUN wget -qO /tmp/litefs.tar.gz \
  https://github.com/superfly/litefs/releases/download/v0.5.11/litefs-v0.5.11-linux-amd64.tar.gz \
  && echo "${LITEFS_SHA256}  /tmp/litefs.tar.gz" | sha256sum -c - \
  && tar -xzf /tmp/litefs.tar.gz -C /tmp \
  && mv /tmp/litefs /usr/local/bin/litefs \
  && chmod +x /usr/local/bin/litefs \
  && rm /tmp/litefs.tar.gz

# Copy LiteFS config
COPY litefs.yml /etc/litefs.yml

# LiteFS is PID 1; it mounts the FUSE filesystem and then starts the app via exec
ENTRYPOINT ["litefs", "mount"]
