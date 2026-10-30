# change-ip

Replaces an IPv4 address (and gateway) in Linux network configs, restarts networking, rolls back automatically if not confirmed.

```bash
curl -fsSL https://raw.githubusercontent.com/Skolskey/change-ip/main/change-ip.sh | sh
```

Supports ifupdown, netplan, NetworkManager (keyfile and ifcfg), systemd-networkd, wicked, OpenRC.

After the network restarts, press ENTER to keep the new settings or `n` to roll back.
If the session drops, log in via the new IP within 180 s and run `touch /root/.ip-change-ok`, otherwise configs are rolled back.
No rollback: `... | TIMEOUT=0 sh`. Backup and log: `/root/ip-change-<date>/`.

Non-interactive: `... | sh -s -- <old-ip> <new-ip> [gateway]` — no prompts, gateway defaults to the suggested one, no rollback.

raw.githubusercontent.com caches files for ~5 minutes after a push.

## Via qemu guest agent

**Panel "Qemu Agent Command" field (raw agent JSON):**

- `qga-json-git.txt` — short, the guest downloads the script (needs internet). Replace `OLD_IP NEW_IP`;
  `''` is the gateway (empty = suggested).
- `qga-json.txt` — script embedded, guest needs no network, ~10 KB. Edit `"1.2.3.4","5.6.7.8",""` (old, new, gateway).

The reply contains `{"pid":N}`; then send `{"execute":"guest-exec-status","arguments":{"pid":N}}`
(`out-data` is base64). Full log in the guest: `/root/ip-change-<date>/log`.

**Hypervisor shell:**

- libvirt, nothing installed: copy `qga-oneliner.txt`, edit `VM= OLD= NEW= GW=` at the start, paste.
- libvirt with the repo cloned: `qga-change-ip.sh <domain> <old-ip> <new-ip> [gateway]`.
- Proxmox: `qm guest exec <vmid> --pass-stdin 1 -- /bin/sh -s -- <old-ip> <new-ip> < change-ip.sh`

After changing `change-ip.sh`, run `./make-oneliner.sh` to rebuild `qga-json.txt` and `qga-oneliner.txt`.

RHEL/Alma/Rocky guests block `guest-exec` by default: remove it from the deny list in `/etc/sysconfig/qemu-ga` and restart `qemu-guest-agent`.
