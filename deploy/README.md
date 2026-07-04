# Deploy — host systemd units

Config that lives on the Dedibox host (not in a container). Install as **root**
(the `deploy` user has no sudo — that's intentional).

## Cloudflare-only firewall

Restricts the Docker-published web ports (80/443) to Cloudflare's edge, at the
network layer — defence-in-depth with Caddy's `cloudflare_only` guard. Because
Docker bypasses `ufw` for published ports, the rules go in the `DOCKER-USER`
iptables chain, keyed off an ipset of Cloudflare's ranges. **SSH (22) is untouched**
— the rules only match 80/443, and `sshd` doesn't traverse `DOCKER-USER` anyway.

The logic is in [`scripts/firewall-cloudflare.sh`](../scripts/firewall-cloudflare.sh);
these units run it at boot and refresh it weekly. Running at boot is important:
it re-populates the ipset **before** the rules, so a reboot never leaves an empty
set that would drop all web traffic.

### Install (as root)

```bash
sudo apt-get install -y ipset

# One-off: apply now (keep a second SSH session open, just in case)
sudo /home/deploy/cinetrack/scripts/firewall-cloudflare.sh

# Persist across reboots + weekly range refresh
sudo cp /home/deploy/cinetrack/deploy/cloudflare-firewall.service /etc/systemd/system/
sudo cp /home/deploy/cinetrack/deploy/cloudflare-firewall.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflare-firewall.service   # apply at boot
sudo systemctl enable --now cloudflare-firewall.timer     # weekly refresh
```

### Notes
- If your checkout isn't at `/home/deploy/cinetrack`, edit `ExecStart=` in the
  `.service` to match.
- **Hardening (optional):** the unit runs a script from a `deploy`-writable path as
  root. To avoid that, install the script to a root-owned path and point the unit
  there:
  ```bash
  sudo install -m 0755 scripts/firewall-cloudflare.sh /usr/local/sbin/firewall-cloudflare.sh
  # then set ExecStart=/usr/local/sbin/firewall-cloudflare.sh in the .service
  ```
- Verify: `sudo iptables -L DOCKER-USER -n -v` (you should see the CF-set RETURN
  and the 80/443 DROP). Check the timer: `systemctl list-timers cloudflare-firewall.timer`.
- Re-apply manually any time: `sudo systemctl start cloudflare-firewall.service`.
