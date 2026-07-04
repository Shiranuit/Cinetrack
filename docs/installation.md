# Installation (development)

This guide gets Cinetrack running locally for development. For a production deployment on a
server, see **[deployment.md](deployment.md)**.

## Prerequisites

| Tool | Version | Needed for |
| --- | --- | --- |
| **Docker + Docker Compose** | recent | Postgres, Garage (S3), Mailpit, and optionally the backend |
| **A TheTVDB API key** | v4 | Metadata. Get one at <https://thetvdb.com/api-information> (free under a revenue threshold). |
| **Rust** | 1.93+ | Only if you build/run the backend on the host instead of in Docker |
| **Flutter** | 3.44.4 | Running the frontend (web/mobile) |

## 1. Clone & configure

```bash
git clone https://github.com/Shiranuit/Cinetrack.git
cd Cinetrack
cp .env.example .env
```

Docker Compose only auto-loads a file literally named `.env`. Edit it and set, at minimum:

- `THETVDB_API_KEY` - your TheTVDB v4 key.
- `JWT_SECRET` - session signing secret. Generate with `openssl rand -hex 32`.
- `GARAGE_RPC_SECRET`, `GARAGE_ADMIN_TOKEN` - each `openssl rand -hex 32`.

Everything is documented inline in `.env.example` and in **[configuration.md](configuration.md)**.

> If you prefer to keep secrets in `.env.local`, symlink it: `ln -sf .env.local .env`.

## 2. Start the datastores

```bash
docker compose up -d postgres garage
```

This starts:

- **postgres** on `localhost:5432` (dev database),
- **garage** on `localhost:3900` (S3-compatible object storage for avatars/covers).

Mailpit (a local mail catcher) is also available; start it with `docker compose up -d mailpit`
and read captured password-reset / invite emails at <http://localhost:8025>.

## 3. Bootstrap object storage

```bash
./scripts/garage-init.sh
```

This creates the Garage layout, an `artwork` bucket, and an S3 access key. **It prints an
access key and secret** - paste them into `.env` as `S3_ACCESS_KEY` / `S3_SECRET_KEY`.

## 4. Start the backend

```bash
docker compose up -d --build backend
```

The backend applies database migrations automatically on boot. Verify:

```bash
curl localhost:8080/health          # {"status":"ok"}
curl localhost:8080/api/series/74796 # fetched from TheTVDB on first hit, cached after
```

### Alternative: run the backend on the host

Keep the datastores in Docker but run the Rust backend directly (faster iteration). The
`.env.local` URLs use the compose service names (`postgres`, `garage`), which don't resolve
from the host - `scripts/run-local.sh` rewrites them to `localhost`:

```bash
scripts/run-local.sh                        # API server on :8080
BIN=sync   scripts/run-local.sh             # one /updates sync pass
BIN=mirror scripts/run-local.sh             # fill the local mirror
BIN=import scripts/run-local.sh export.zip  # import a TV Time GDPR export
```

(Or set `DATABASE_URL=postgres://…@localhost:5432/tvshow` yourself and run
`cargo run --manifest-path backend/Cargo.toml`.)

## 5. Run the Flutter app

```bash
cd frontend
flutter pub get
flutter run -d chrome            # web; add other devices with `flutter devices`
```

By default the app talks to `http://localhost:8080`. To point elsewhere, pass
`--dart-define=API_BASE=http://your-host:8080`.

## 6. Create your first user

Public sign-up is **disabled by default** (invite-only). Either set
`ALLOW_PUBLIC_REGISTRATION=true` in `.env` and restart the backend, or create a user directly:

```bash
docker compose exec backend create_user you@example.com 'a-strong-password' 'Your Name'
```

## 7. (Optional) Import your TV Time history

If you have your TV Time **GDPR export** zip:

```bash
BIN=import scripts/run-local.sh /path/to/tvtime-export.zip
# or, in Docker:
docker compose run --rm backend import /path/to/tvtime-export.zip
```

It's idempotent - safe to re-run.

## Building for release

**Web:**

```bash
cd frontend
flutter build web --release \
  --dart-define=API_BASE=https://api.your-domain.com \
  --dart-define=APP_VERSION=v1.0.0 \
  --dart-define=GITHUB_REPO=YourOrg/YourRepo
```

**Android APK:**

```bash
flutter build apk --release --dart-define=API_BASE=https://api.your-domain.com
```

In CI these are built and signed for you - see **[ci-cd.md](ci-cd.md)**.

## Running the tests

```bash
# Backend (needs the throwaway test DB on port 5433):
docker compose up -d postgres-test
cd backend && cargo test          # skips DB tests if TEST_DATABASE_URL is unset

# Frontend:
cd frontend && flutter analyze
```
