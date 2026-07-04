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
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/backend /usr/local/bin/backend
# Admin/recovery CLIs (invoked via `docker compose exec backend <name> …`).
COPY --from=builder /app/target/release/create_user /usr/local/bin/create_user
COPY --from=builder /app/target/release/reset_password /usr/local/bin/reset_password
EXPOSE 8080
CMD ["backend"]
