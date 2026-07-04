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

# Runtime
FROM debian:bookworm-slim
# Baked-in release tag (from the git tag in CI), surfaced via GET /api/config so
# clients can detect they're older than the server. "dev" for local builds.
ARG APP_VERSION=dev
ENV APP_VERSION=$APP_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/backend /usr/local/bin/backend
# Admin/recovery CLIs (invoked via `docker compose exec|run backend <name> …`).
COPY --from=builder /app/target/release/create_user /usr/local/bin/create_user
COPY --from=builder /app/target/release/reset_password /usr/local/bin/reset_password
COPY --from=builder /app/target/release/migrate /usr/local/bin/migrate
EXPOSE 8080
CMD ["backend"]
