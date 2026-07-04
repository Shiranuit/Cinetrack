# ---- Stage 1: build the Flutter WEB bundle -------------------------------
# The backend URL is COMPILED INTO the bundle at build time via the API_BASE arg
# (CI passes ${{ vars.API_BASE }}; the compose passes ${API_BASE} for local builds).
FROM ghcr.io/cirruslabs/flutter:stable AS build
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
