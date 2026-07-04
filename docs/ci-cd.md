# CI / CD (GitHub Actions)

Two workflows live in [`.github/workflows/`](../.github/workflows/).

## `tests.yml` - CI on every push/PR

Runs on pull requests and pushes to `main`/`master`. No secrets or variables required - it
spins up a `postgres:17` service and runs:

- **backend:** `cargo test --locked` (Rust 1.93) against a throwaway test database,
- **frontend:** `flutter analyze` (Flutter 3.44.4).

## `release.yml` - build, publish & deploy on a tag

Triggered by pushing a **`v*` tag** (e.g. `v1.2.3`). `workflow_dispatch` builds the APK and
images without releasing/deploying. Jobs:

1. **apk** - builds and (optionally) signs the Android APK.
2. **image** - builds the backend image → pushes to GHCR.
3. **web-image** - builds the Flutter web + Caddy image → pushes to GHCR.
4. **release** - creates the GitHub Release and attaches the APK.
5. **deploy** - SSHes into your server, pulls the new images, and restarts the stack.

Images are published to `ghcr.io/<your-github-owner>/cinetrack-backend` and
`…/cinetrack-web`, tagged with the release tag and `latest`.

## What a fork must configure

Set these in your repo under **Settings → Secrets and variables → Actions**.

### Secrets

| Secret | Used by | Required? | Purpose |
| --- | --- | --- | --- |
| `KEYSTORE_BASE64` | apk | Optional | Base64 of your Android release keystore (`.jks`). If unset, the APK is **debug-signed** (works, but can't update in place across releases). |
| `KEYSTORE_PASSWORD` | apk | With keystore | Keystore password. |
| `KEY_ALIAS` | apk | With keystore | Signing key alias. |
| `KEY_PASSWORD` | apk | With keystore | Signing key password. |
| `DEDIBOX_HOST` | deploy | For deploy | Server hostname/IP to SSH into. |
| `DEDIBOX_USER` | deploy | For deploy | SSH user (a non-sudo deploy user is recommended). |
| `DEDIBOX_SSH_KEY` | deploy | For deploy | Private SSH key for that user. |

> `GITHUB_TOKEN` is provided automatically and is used to push images to GHCR - no setup
> needed. (The `image`/`web-image` jobs request `packages: write`.)

### Variables

| Variable | Used by | Required? | Default |
| --- | --- | --- | --- |
| `API_BASE` | apk, web-image | Optional | Falls back to `https://api.cine-track.com`. Set it to **your** API URL (e.g. `https://api.your-domain.com`) so the built app talks to your backend. |
| `DEDIBOX_APP_DIR` | deploy | For deploy | _(none)_ - the absolute path on the server to your checkout of this repo (where `.env.production` and the compose file live). |

> The secret/variable names keep the original `DEDIBOX_*` naming (the reference deployment runs
> on a Scaleway Dedibox), but they work for **any** SSH-reachable Linux server.

## The deploy step, in detail

On a tagged release the `deploy` job runs, on your server, roughly:

```bash
cd "$DEDIBOX_APP_DIR"
git fetch --tags --prune
git checkout --force "<tag>"
# persist the deployed tag so admin commands use the same image:
#   IMAGE_TAG=<tag>  written into .env.production
docker compose -f production.docker-compose.yaml --env-file .env.production pull backend web
docker compose -f production.docker-compose.yaml --env-file .env.production up -d --remove-orphans
docker image prune -f
```

So your server needs: this repo checked out at `DEDIBOX_APP_DIR`, a populated
`.env.production` (with `GHCR_OWNER` set to your GitHub owner so it pulls **your** images), and
Docker login to GHCR if your images are private (`docker login ghcr.io`).

## Minimal setup checklist for a fork

- [ ] Enable Actions on the fork.
- [ ] (Optional, for a real APK) add the four `KEYSTORE*`/`KEY*` secrets.
- [ ] Set variable `API_BASE` to your API URL.
- [ ] For auto-deploy: add `DEDIBOX_HOST`/`DEDIBOX_USER`/`DEDIBOX_SSH_KEY` secrets and the
      `DEDIBOX_APP_DIR` variable, and prepare the server per [deployment.md](deployment.md).
- [ ] Push a `v*` tag to cut a release.
