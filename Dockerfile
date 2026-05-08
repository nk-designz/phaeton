# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM docker.io/library/elixir:1.15-otp-26-alpine AS builder

# build-base: C compiler for NIFs (exqlite bundles sqlite3 as a NIF)
# git: required by some Mix deps fetched from GitHub (heroicons)
# curl: used by esbuild/tailwind installers
RUN apk add --no-cache build-base git curl openssl-dev

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# Fetch deps first so this layer is cached independently of source changes
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Copy all config (compile-time + runtime)
COPY config config/

# Copy source + assets
COPY lib lib/
COPY priv priv/
COPY assets assets/

RUN mix compile

# esbuild and tailwind are standalone binaries downloaded by Mix — no npm needed
RUN mix assets.deploy

RUN mix release

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM docker.io/library/alpine:3.20 AS runner

# libstdc++/libgcc: required by exqlite NIF
# ncurses-libs: required by BEAM
# openssl/ca-certificates: TLS + cert validation
RUN apk add --no-cache libstdc++ libgcc ncurses-libs openssl ca-certificates

WORKDIR /app

RUN adduser -D -u 1000 phaeton
RUN mkdir -p /data && chown phaeton:phaeton /data

COPY --from=builder --chown=phaeton:phaeton /app/_build/prod/rel/phaeton ./

USER phaeton

# SQLite database — mount a persistent volume here
VOLUME ["/data"]

EXPOSE 4000

ENV HOME=/app
ENV PHX_SERVER=true
ENV DATABASE_PATH=/data/phaeton.db

CMD ["bin/phaeton", "start"]
