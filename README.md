# change-ip

Replaces an IPv4 address (and gateway) in Linux network configs, restarts networking, rolls back automatically if not confirmed.

Private repo, download with a read-only token:

```bash
read -rs T; curl -fsSL -H "Authorization: Bearer $T" -H "Accept: application/vnd.github.raw" https://api.github.com/repos/Skolskey/change-ip/contents/change-ip.sh | sh
```

`read -rs T` — paste the token (hidden, not saved to history).

Supports ifupdown, netplan, NetworkManager (keyfile and ifcfg), systemd-networkd, wicked, OpenRC.

After the network restarts, press ENTER to keep the new settings or `n` to roll back.
If the session drops, log in via the new IP within 180 s and run `touch /root/.ip-change-ok`, otherwise configs are rolled back.
No rollback: `... | TIMEOUT=0 sh`. Backup and log: `/root/ip-change-<date>/`.
