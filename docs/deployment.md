# Deployment

Cinetrack ships a **production Docker Compose stack**
([`production.docker-compose.yaml`](../production.docker-compose.yaml)) that runs the entire
application on a **single Linux server**, behind **Cloudflare**, with **no external managed
services**.

## Philosophy & trade-offs (read this first)

This setup is deliberately **low-cost and self-contained**, not industrial-grade:

- ✅ Everything - API, web app, database, object storage, and email - runs in containers on
  **one box**. Cheap (a single small VPS/dedicated server) and simple to operate.
- ✅ **No third-party dependencies** required to function: you don't need managed Postgres, a
  cloud object store, or an email SaaS. Just a server, a domain, and Cloudflare (free tier).
- ⚠️ It **does not scale horizontally** and has **no high availability**. One Postgres, one
  backend, one node of object storage. If the box goes down, the app is down.
- ⚠️ It's a great fit for **personal or small-community** use. For large-scale or
  business-critical use you'd want managed/replicated datastores, multiple backend replicas,
  a real load balancer, and offloaded email - which this stack intentionally doesn't provide.

Think of it as "self-host the whole thing on a $10-20/month server" rather than a
production-hardened, auto-scaling platform.

## What runs

All services attach to one internal Docker network. **Only the web container publishes ports**
(80/443); Postgres, Garage, the backend, and the mailer are internal-only.

| Service | Image | Ports | Role |
| --- | --- | --- | --- |
| `web` | `ghcr.io/<owner>/cinetrack-web` | 80, 443, 443/udp | Caddy - serves the Flutter web app and reverse-proxies the API. The only internet-facing service. |
| `backend` | `ghcr.io/<owner>/cinetrack-backend` | internal | The Rust API. Runs DB migrations on boot. |
| `postgres` | `postgres:17-alpine` | internal | Database. Tuned for a ~32 GB box. |
| `garage` | `dxflrs/garage` | internal | S3-compatible object storage (avatars/covers). |
| `mailer` | `boky/postfix` | internal (needs host outbound :25) | Optional send-only DKIM-signing SMTP relay. |

Persistent data lives in **bind mounts under `./data`** (`data/postgres`, `data/garage`,
`data/caddy`, `data/postfix`), so `docker compose down -v` does **not** delete it.

## Prerequisites

1. A Linux server with Docker + Docker Compose.
2. A domain (the examples use `cine-track.com`) with DNS on **Cloudflare**.
3. Three subdomains, proxied through Cloudflare (orange cloud):
   - `app.<domain>` → the web app,
   - `api.<domain>` → the API,
   - (optional) `mail.<domain>` → the mail relay (DNS-only / grey cloud).
4. A **[Cloudflare Origin Certificate](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)**
   for your domain, with Cloudflare SSL/TLS mode **Full (strict)**.

## Steps

### 1. Get the code and configure

```bash
git clone https://github.com/Shiranuit/Cinetrack.git
cd Cinetrack
cp .env.production.example .env.production
```

Edit `.env.production`. Key values:

- `GHCR_OWNER` - the GitHub owner the images were pushed under (defaults to `shiranuit`;
  set to **your** org/user if you build your own images - see [ci-cd.md](ci-cd.md)).
- `IMAGE_TAG` - the release tag to run (e.g. `v1.0.0`). The deploy workflow keeps this in sync.
- `DATABASE_URL`, `JWT_SECRET` (≥32 chars), `THETVDB_API_KEY` - required.
- `WEB_DOMAIN=app.<domain>`, `API_DOMAIN=api.<domain>`, `PUBLIC_BASE_URL=https://api.<domain>`,
  `WEB_BASE_URL=https://app.<domain>`.
- Garage `S3_ACCESS_KEY` / `S3_SECRET_KEY` (filled after step 3).

The production defaults lean toward a full offline mirror: `CATALOG_MODE=hybrid`,
`MIRROR_SCOPE=full`, `SYNC_INTERVAL_SECS=300`, `ENRICH_INTERVAL_SECS=30`,
`ENRICH_CONCURRENCY=64`, `THETVDB_MAX_RPS=200`, `DB_MAX_CONNECTIONS=100`. See
[configuration.md](configuration.md).

### 2. Install the Cloudflare Origin Certificate

Create the cert/key in the Cloudflare dashboard and place them where Caddy expects:

```bash
mkdir -p data/caddy/origin
# paste the certificate and key:
#   data/caddy/origin/tls.crt
#   data/caddy/origin/tls.key
```

### 3. Bring it up & bootstrap storage

```bash
docker compose -f production.docker-compose.yaml --env-file .env.production up -d

# First boot only: create the Garage layout + bucket + S3 key.
COMPOSE_FILE=production.docker-compose.yaml ./scripts/garage-init.sh
# Paste the printed keys into .env.production (S3_ACCESS_KEY / S3_SECRET_KEY), then:
docker compose -f production.docker-compose.yaml --env-file .env.production up -d backend
```

### 4. Lock the firewall to Cloudflare

Because Caddy trusts Cloudflare's `CF-Connecting-IP` header for the real client IP, the box
must only accept 80/443 from Cloudflare's edge. Install the firewall (Docker bypasses `ufw`,
so this uses the `DOCKER-USER` iptables chain + an ipset, refreshed weekly):

```bash
sudo ./scripts/firewall-cloudflare.sh
# Persist + auto-refresh via systemd (see deploy/README.md):
sudo cp deploy/cloudflare-firewall.* /etc/systemd/system/
sudo systemctl enable --now cloudflare-firewall.timer
```

### 5. Create the first user

Public sign-up is off by default (invite-only). Create yourself an account:

```bash
DC="docker compose -f production.docker-compose.yaml --env-file .env.production"
$DC exec backend create_user you@example.com 'a-strong-password' 'Your Name'
```

## Email

You have two options. **Using an external transactional-email provider is strongly recommended.**

### Recommended: external SMTP provider

Self-hosting outbound email deliverability is genuinely hard - SPF, DKIM, DMARC, reverse DNS,
IP reputation, and provider blocklists all conspire against a fresh server, and your reset/
invite mails will often land in spam or be rejected. Use a provider
(e.g. [Scaleway TEM](https://www.scaleway.com/en/transactional-email-tem/),
[Mailgun](https://www.mailgun.com/), [SendGrid](https://sendgrid.com/), [Postmark](https://postmarkapp.com/)):

```bash
# in .env.production - overrides the internal mailer:
SMTP_HOST=smtp.your-provider.com
SMTP_PORT=587
SMTP_TLS=starttls
SMTP_USER=...
SMTP_PASS=...
MAIL_FROM=Cinetrack <no-reply@your-domain.com>
```

You can then drop the `mailer` service entirely.

### Self-contained: the bundled `mailer`

For a truly dependency-free box, the stack includes a `boky/postfix` relay that DKIM-signs
outbound mail. The backend defaults to it (`SMTP_HOST=mailer`, `SMTP_TLS=none`). To use it you
must own the DNS and the server's reverse DNS:

1. Set `MAIL_DOMAIN` and `MAIL_HOSTNAME` (e.g. `mail.<domain>`) in `.env.production`.
2. On first boot, print the generated DKIM record and add it to DNS:
   ```bash
   COMPOSE_FILE=production.docker-compose.yaml ./scripts/mail-dkim.sh
   ```
   It also prints suggested SPF and DMARC records.
3. Add an SPF record authorizing your server IP, a DMARC record, and set **reverse DNS (PTR)**
   for the server IP to `mail.<domain>`.
4. Ensure the host can make **outbound connections on port 25** (some providers block it).

Even done correctly, expect deliverability to lag a managed provider. Prefer external SMTP
unless full self-containment is a hard requirement.

### Hardening DMARC (none -> quarantine -> reject)

Start DMARC in monitor mode (`p=none`) so nothing legitimate is blocked while you confirm your
mail authenticates. The `rua=` address receives daily aggregate reports (XML, one per reporter);
each lists every source that sent as your domain and whether it passed SPF/DKIM/DMARC. Once your
own server consistently shows `dkim=pass` + `spf=pass` aligned to your domain, tighten the
`_dmarc.<domain>` TXT record in two steps, watching the reports between each:

```
# Phase 0 - monitor (start here)
v=DMARC1; p=none; rua=mailto:you@example.com

# Phase 1 - quarantine (failing mail -> spam). Hold ~1-2 weeks, verify no legit source fails.
v=DMARC1; p=quarantine; sp=quarantine; adkim=r; aspf=r; pct=100; rua=mailto:you@example.com

# Phase 2 - reject (spoofed mail refused). Full protection.
v=DMARC1; p=reject; sp=reject; np=reject; adkim=r; aspf=r; rua=mailto:you@example.com
```

- `sp=` applies the policy to subdomains; `np=reject` refuses mail from non-existent subdomains
  (a common spoofing trick). Keep alignment relaxed (`adkim=r`/`aspf=r`) unless you have a reason not to.
- **Before `reject`, authorize every legitimate sender** (SPF `ip4:`/`include:` + its DKIM key):
  your own server, plus any transactional-email provider, newsletter tool, or Google Workspace
  mailboxes you later add. `reject` bounces anything from your domain that isn't authorized.
- Optionally switch SPF's `~all` (softfail) to `-all` (hardfail) once you are confident.

## Updating / releasing

Tagging a `v*` release on GitHub builds the images, publishes them to GHCR, attaches the APK to
the release, and deploys to your server over SSH - see **[ci-cd.md](ci-cd.md)**. To deploy
manually:

```bash
DC="docker compose -f production.docker-compose.yaml --env-file .env.production"
git fetch --tags && git checkout --force v1.2.3
echo "IMAGE_TAG=v1.2.3" >> .env.production   # or edit the existing line
$DC pull backend web && $DC up -d --remove-orphans
```

## Operations

- **Backups:** `scripts/db-dump.sh` writes a gzipped `pg_dump` of the whole database. Also back
  up `data/garage` (avatars/covers).
- **Migrations offline:** `scripts/db-migrate.sh` applies migrations without starting the server.
- **Seeding:** `scripts/db-seed.sh <file.sql|.sql.gz>` loads a dump (e.g. a pre-built catalog).
- See **[cli.md](cli.md)** for the full toolbox.
