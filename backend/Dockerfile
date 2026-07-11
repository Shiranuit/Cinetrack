# Build
FROM rust:1.93-slim AS builder
WORKDIR /app
# Cache deps
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs && cargo build --release && rm -rf src
# Build for real
COPY src ./src
COPY migrations ./migrations
RUN touch src/main.rs && cargo build --release
# Gather the server + every CLI (src/bin/*) into one dir so new binaries ship
# automatically — no need to list each below. Top-level executables only, which
# skips deps/, build/, *.d and the other build artifacts under target/release.
RUN mkdir -p /out && find target/release -maxdepth 1 -type f -executable -exec cp -t /out {} +

# Runtime
FROM debian:bookworm-slim
# Baked-in release tag (from the git tag in CI), surfaced via GET /api/config so
# clients can detect they're older than the server. "dev" for local builds.
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
# The server (CMD below) plus every admin/recovery/backfill CLI, each invokable via
# `docker compose exec|run backend <name> …`. Copied wholesale from the build stage,
# so adding a src/bin/*.rs ships automatically with no change here.
COPY --from=builder /out/ /usr/local/bin/
EXPOSE 8080
CMD ["backend"]
