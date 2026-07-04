# ---- Stage 1: build the Flutter WEB bundle -------------------------------
# The backend URL is COMPILED INTO the bundle at build time via the API_BASE arg
# (CI passes ${{ vars.API_BASE }}; the compose passes ${API_BASE} for local builds).
#
# Flutter is installed from git at the EXACT dev version (FLUTTER_VERSION) instead of
# the cirruslabs image: cirruslabs doesn't publish every patch release, and a version
# mismatch vs the pubspec.lock (resolved on the dev machine) breaks `pub get`. Bump
# FLUTTER_VERSION when you upgrade Flutter locally (`flutter --version`).
FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.44.4
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends \
      bash git curl ca-certificates unzip xz-utils && \
    rm -rf /var/lib/apt/lists/* && \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter && \
    git config --global --add safe.directory /opt/flutter && \
    flutter --version && \
    flutter precache --web
WORKDIR /app

# All three are baked into the bundle at build time (defaults are dev-only).
ARG API_BASE=http://localhost:8080
ARG APP_VERSION=dev
ARG GITHUB_REPO=Shiranuit/Cinetrack

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release \
      --dart-define=API_BASE=${API_BASE} \
      --dart-define=APP_VERSION=${APP_VERSION} \
      --dart-define=GITHUB_REPO=${GITHUB_REPO}

# ---- Stage 2: serve the SPA + reverse-proxy the API, with automatic HTTPS -
FROM caddy:2-alpine
COPY --from=build /app/build/web /srv
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80 443
