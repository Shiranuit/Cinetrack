#!/usr/bin/env bash
# Restrict the Docker-published web ports (80/443) to Cloudflare's edge only, at the
# network layer — defence-in-depth alongside Caddy's `cloudflare_only` guard.
#
# Docker bypasses ufw for published container ports, so we insert rules into the
# DOCKER-USER chain (which Docker evaluates first) + an ipset of Cloudflare ranges,
# refreshed from cloudflare.com on every run. Idempotent: re-running re-applies cleanly.
#
# Run as ROOT (NOT the deploy user):   sudo scripts/firewall-cloudflare.sh
# Leaves SSH (22) and everything else untouched — only 80/443 are filtered.
set -euo pipefail

PORTS="80,443"
# The public NIC. We only filter traffic ARRIVING on it (inbound from the internet),
# so container OUTBOUND connections to :80/:443 (backend -> TheTVDB, etc.) are never
# dropped. Override with EXT_IF=... if auto-detection picks the wrong interface.
EXT_IF="${EXT_IF:-$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')}"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
command -v ipset >/dev/null || { echo "install ipset: apt-get install -y ipset" >&2; exit 1; }
[ -n "$EXT_IF" ] || { echo "could not detect the external interface; set EXT_IF=<iface>" >&2; exit 1; }

# Refresh an ipset atomically from a Cloudflare IP list.
refresh() { # <ipset> <family> <url>
  local set="$1" fam="$2" url="$3" tmp="${1}_new"
  ipset create "$set" hash:net family "$fam" -exist
  ipset create "$tmp" hash:net family "$fam" -exist
  ipset flush "$tmp"
  curl -fsS --max-time 15 "$url" | while read -r n; do [ -n "$n" ] && ipset add "$tmp" "$n" -exist; done
  ipset swap "$tmp" "$set"
  ipset destroy "$tmp"
}

# Install the allow-Cloudflare / drop-rest rules into a DOCKER-USER chain.
apply() { # <iptables-cmd> <ipset>
  local ipt="$1" set="$2"
  $ipt -L DOCKER-USER -n >/dev/null 2>&1 || { echo "  ($ipt) DOCKER-USER missing — is Docker running?" >&2; return 0; }
  $ipt -F DOCKER-USER
  # Responses to already-open connections (incl. containers' own outbound) pass.
  $ipt -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
  # Only NEW connections INBOUND on the public NIC to 80/443 are filtered — allow
  # Cloudflare, drop the rest. `-i $EXT_IF` keeps container outbound (which arrives
  # on the docker bridge, not $EXT_IF) untouched.
  $ipt -A DOCKER-USER -i "$EXT_IF" -m set --match-set "$set" src -p tcp -m multiport --dports "$PORTS" -j RETURN
  $ipt -A DOCKER-USER -i "$EXT_IF" -p tcp -m multiport --dports "$PORTS" -j DROP
  $ipt -A DOCKER-USER -j RETURN
  echo "  ($ipt) inbound 80/443 on $EXT_IF restricted to $set"
}

echo "==> Refreshing Cloudflare ranges..."
refresh cf4 inet https://www.cloudflare.com/ips-v4
apply iptables cf4

# IPv6 only if the host/Docker actually has it (DOCKER-USER exists for ip6tables).
if command -v ip6tables >/dev/null && ip6tables -L DOCKER-USER -n >/dev/null 2>&1; then
  refresh cf6 inet6 https://www.cloudflare.com/ips-v6
  apply ip6tables cf6
fi

echo "==> Done. Only Cloudflare's edge can reach ports $PORTS."
