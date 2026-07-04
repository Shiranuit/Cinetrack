#!/usr/bin/env bash
# Print the DKIM DNS record(s) to publish, reassembled into a single pasteable line.
#
# The mailer's <selector>.txt splits the record across quoted chunks (DNS's 255-char
# limit), so copying it by hand from a wrapped terminal loses the p= prefix / the
# start of the key. This rebuilds the full value straight from the running container.
#
# Run from the repo dir on the box, pointing compose at the prod stack:
#   COMPOSE_FILE=production.docker-compose.yaml scripts/mail-dkim.sh
# or override the compose command entirely:
#   DC="docker compose -f production.docker-compose.yaml" scripts/mail-dkim.sh
set -euo pipefail

DC="${DC:-docker compose}"
SVC="${MAIL_SVC:-mailer}"

mapfile -t files < <($DC exec -T "$SVC" sh -c 'find /etc/opendkim/keys -name "*.txt" 2>/dev/null' | tr -d '\r' || true)

if [ "${#files[@]}" -eq 0 ] || [ -z "${files[0]}" ]; then
  echo "No DKIM key files found. Is the '$SVC' container running?" >&2
  echo "  $DC up -d $SVC" >&2
  exit 1
fi

for f in "${files[@]}"; do
  [ -n "$f" ] || continue
  content="$($DC exec -T "$SVC" cat "$f" | tr -d '\r')"
  # Record name is the first token (e.g. `mail._domainkey`); value is every quoted
  # chunk joined (yields `v=DKIM1; ...; p=MIG...`).
  name="$(printf '%s\n' "$content" | awk 'NF{print $1; exit}')"
  value="$(printf '%s' "$content" | grep -o '"[^"]*"' | tr -d '"\n')"
  domain="$(printf '%s' "$f" | awk -F/ '{print $(NF-1)}')"

  echo "──────────────────────────────────────────────────────────────"
  echo "DKIM for $domain — add this TXT record:"
  echo "  Name:  $name"
  echo "  Type:  TXT"
  echo "  Value: $value"
  echo "──────────────────────────────────────────────────────────────"
done

cat <<EOF

Also publish (once) for the sending domain:
  TXT  @        v=spf1 ip4:<your-server-ip> -all
  TXT  _dmarc   v=DMARC1; p=none; rua=mailto:you@example.com
And set the 'mail' A record (grey/DNS-only) + the Dedibox reverse DNS to your mail host.
EOF
