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

## Via qemu guest agent (from the hypervisor)

The guest needs no network and no token: the script is passed through the agent.
Non-interactive mode: `change-ip.sh <old-ip> <new-ip> [gateway]`, gateway defaults to the suggested one, no rollback.

**One line, nothing installed on the hypervisor:** copy `qga-oneliner.txt`, edit `VM= OLD= NEW= GW=` at the start
(empty `GW` = suggested gateway), paste into the hypervisor shell. The script is embedded as base64.
After changing `change-ip.sh`, run `./make-oneliner.sh` to rebuild it.

**Or keep the repo on the hypervisor** (username: anything, password: the token):

```bash
git clone https://github.com/Skolskey/change-ip.git /root/change-ip
```

libvirt / virsh:

```bash
/root/change-ip/qga-change-ip.sh <domain> <old-ip> <new-ip> [gateway]
```

Proxmox:

```bash
qm guest exec <vmid> --pass-stdin 1 -- /bin/sh -s -- <old-ip> <new-ip> [gateway] < /root/change-ip/change-ip.sh
```

RHEL/Alma/Rocky guests block `guest-exec` by default: remove it from the deny list in `/etc/sysconfig/qemu-ga` and restart `qemu-guest-agent`.
