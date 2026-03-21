# syntax=docker/dockerfile:1
#
# Target platform: linux/amd64 (Fly.io machines).
# Build with: fly deploy (uses Fly's remote amd64 builder — recommended)
# Local build on Apple Silicon: docker build --platform linux/amd64 . (requires QEMU)

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
# vips: required by the image/vix library at runtime (Alpine package name; libvips on Debian)
# libgcc + libstdc++: required by NIFs compiled with GCC (vix and bcrypt_elixir)
RUN apk add --no-cache \
  vips \
  libgcc \
  libstdc++ \
  openssl \
  ncurses-libs \
  ca-certificates

WORKDIR /app

# Copy the compiled release from builder
COPY --from=builder /app/_build/prod/rel/scientia_cognita ./

ENV PHX_SERVER=true
CMD ["/app/bin/scientia_cognita", "start"]
