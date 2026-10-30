#!/bin/sh
# Replace an IPv4 address (and gateway) in network configs, restart networking, auto-rollback.
# Usage: curl -fsSL https://raw.githubusercontent.com/Skolskey/change-ip/main/change-ip.sh | sh
# TIMEOUT=0 disables rollback.
# Non-interactive (e.g. via qemu guest agent): change-ip.sh <old-ip> <new-ip> [gateway]
#   no prompts, gateway defaults to the suggested one, rollback off unless TIMEOUT is set.

PATH=$PATH:/usr/sbin:/sbin
BATCH=; [ $# -ge 2 ] && BATCH=1
[ -n "$BATCH" ] && TIMEOUT=${TIMEOUT:-0}
TIMEOUT=${TIMEOUT:-180}
OK_FILE=/root/.ip-change-ok
PATHS="/etc/network/interfaces /etc/network/interfaces.d /etc/netplan
/etc/sysconfig/network-scripts /etc/sysconfig/network /etc/NetworkManager/system-connections
/etc/systemd/network /etc/conf.d/net /etc/hosts"

die() { echo "Error: $*" >&2; exit 1; }
ask() { printf '%s' "$1" >/dev/tty; read -r v </dev/tty; printf '%s' "$v"; }
lc() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
valid_ip() {
  echo "$1" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9][0-9]?[0-9]?$/ || $i > 255) exit 1; exit 0 } { exit 1 }'
}
# network address of $1/$2 plus offset $3 (0 = network, 1 = first host)
subnet() {
  echo "$1 $2 $3" | awk '{ split($1, o, "."); n = ((o[1]*256 + o[2])*256 + o[3])*256 + o[4]
    b = 2 ^ (32 - $2); n = int(n / b) * b + $3
    printf "%d.%d.%d.%d", int(n/16777216), int(n/65536) % 256, int(n/256) % 256, n % 256 }'
}
# whole IP only, so 1.2.3.4 doesn't match 1.2.3.40 or 11.2.3.4
re() { printf '(^|[^0-9.])%s([^0-9.]|$)' "$(printf '%s' "$1" | sed 's/\./\\./g')"; }
# applied twice: adjacent matches ("ip,ip") share the separator
subst() { s="s/$(re "$1")/\\1$2\\2/g"; printf '%s;%s' "$s" "$s"; }

# remove IP from its interface (otherwise ifupdown keeps the old address and route)
drop_ip() {
  ip -o -4 addr show | awk -v ip="$1" '{ split($4, a, "/"); sub(/@.*/, "", $2) } a[1] == ip { print $2, $4 }' |
  while read -r dev cidr; do
    echo 1 > "/proc/sys/net/ipv4/conf/$dev/promote_secondaries" 2>/dev/null
    ip addr del "$cidr" dev "$dev"
  done
}

restart_net() {
  if command -v netplan >/dev/null 2>&1 && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    netplan apply
  fi
  # also after netplan: its NetworkManager renderer may use keyfiles outside /etc/netplan
  if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    nmcli connection reload
    nmcli -g UUID connection show --active | while read -r c; do nmcli connection up "$c"; done
  elif command -v netplan >/dev/null 2>&1 && ls /etc/netplan/*.yaml >/dev/null 2>&1; then
    :
  elif systemctl is-active --quiet systemd-networkd 2>/dev/null; then
    networkctl reload; networkctl reconfigure $(ls /sys/class/net)
  elif command -v wicked >/dev/null 2>&1; then
    wicked ifreload all
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service networking restart
  elif [ -f /etc/network/interfaces ]; then
    systemctl restart networking
  else
    systemctl restart network
  fi
}

# runs detached; talks to the foreground via files in $BK: applied, revert, done
worker() {
  sleep 2
  date; echo "Applying $OLD -> $NEW"
  drop_ip "$OLD"; restart_net
  ip -o -4 addr show scope global
  touch "$BK/applied"
  [ "$TIMEOUT" -eq 0 ] && { echo "applied, rollback disabled" > "$BK/done"; return; }
  i=0
  while [ "$i" -lt "$TIMEOUT" ] && [ ! -f "$BK/revert" ]; do
    [ -f "$OK_FILE" ] && { rm -f "$OK_FILE"; echo "Confirmed, new settings kept" | tee "$BK/done"; return; }
    sleep 1; i=$((i + 1))
  done
  echo "Rolling back"
  drop_ip "$NEW"
  tar -C / -xf "$BK/backup.tar"
  restart_net
  ip -o -4 addr show scope global
  echo "Rolled back to $OLD" | tee "$BK/done"
}

[ "$(id -u)" -eq 0 ] || die "must be run as root"
[ -n "$BATCH" ] || ( : </dev/tty ) 2>/dev/null ||
  die "interactive terminal required (or pass: <old-ip> <new-ip> [gateway])"
command -v ip >/dev/null 2>&1 || die "'ip' command not found (install iproute2)"

echo "Current addresses:"; ip -o -4 addr show scope global | awk '{ print "  " $2, $4 }'
echo "Default route: $(ip -4 route show default | head -n1)"

OLD=${1:-$(ask "IP to replace: ")}; valid_ip "$OLD" || die "invalid IP: $OLD"
NEW=${2:-$(ask "New IP: ")};        valid_ip "$NEW" || die "invalid IP: $NEW"
[ "$OLD" != "$NEW" ] || die "IPs are the same"

# suggest a gateway: same subnet -> keep current, otherwise first host of the new subnet
OGW=$(ip -4 route show default | awk '{ print $3; exit }')
PFX=$(ip -o -4 addr show | awk -v ip="$OLD" '{ split($4, a, "/") } a[1] == ip { print a[2]; exit }')
PFX=${PFX:-24}
if [ "$PFX" -ge 31 ] || [ "$(subnet "$OLD" "$PFX" 0)" = "$(subnet "$NEW" "$PFX" 0)" ]; then
  SGW=$OGW
else
  SGW=$(subnet "$NEW" "$PFX" 1)
fi
if [ -n "$BATCH" ]; then NGW=${3:-$SGW}; else NGW=$(ask "New gateway [${SGW:-none}]: "); NGW=${NGW:-$SGW}; fi
[ -z "$NGW" ] || valid_ip "$NGW" || die "invalid gateway: $NGW"
[ -n "$NGW" ] && [ -z "$OGW" ] && echo "WARNING: no current default route, gateway won't be changed"

PAT=$(re "$OLD"); SED=$(subst "$OLD" "$NEW")
if [ -n "$NGW" ] && [ -n "$OGW" ] && [ "$NGW" != "$OGW" ]; then
  PAT="$PAT|$(re "$OGW")"; SED="$SED;$(subst "$OGW" "$NGW")"
fi

BK=/root/ip-change-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK" || die "cannot create $BK"
grep -rlE "$PAT" $PATHS 2>/dev/null | sort -u > "$BK/files"
[ -s "$BK/files" ] || die "$OLD not found in network configs"

echo; echo "Files to change:"
while IFS= read -r f; do echo "== $f"; grep -nE "$PAT" "$f"; done < "$BK/files"
others=$(grep -rlE "$(re "$OLD")" /etc 2>/dev/null | grep -vxF -f "$BK/files")
[ -n "$others" ] && printf '\nIP also found here (NOT changed, check these services):\n%s\n' "$others"
command -v ping >/dev/null 2>&1 && ping -c1 -W1 "$NEW" >/dev/null 2>&1 && echo "WARNING: $NEW already answers ping"
[ -d /etc/cloud ] && [ ! -f /etc/cloud/cloud-init.disabled ] &&
  echo "WARNING: cloud-init may restore the old network config on reboot"

[ -n "$BATCH" ] || case $(lc "$(ask "Apply? [y/N]: ")") in y|yes) ;; *) die "cancelled" ;; esac

tar -C / -cf "$BK/backup.tar" -T "$BK/files" 2>/dev/null || die "backup failed"
while IFS= read -r f; do
  sed -i -E "$SED" "$f"
  # NEW may already be a secondary address: drop the duplicate netplan list entry
  case $f in /etc/netplan/*)
    awk -v ip="$NEW" '!(index($0, ip) && /^[[:space:]]*-/ && seen[$0]++)' "$f" > "$f.tmp" &&
      cat "$f.tmp" > "$f"; rm -f "$f.tmp" ;;
  esac
done < "$BK/files"
rm -f "$OK_FILE"

# ponytail: trap HUP keeps the worker alive after SSH drops; KillUserProcesses=yes would need systemd-run
( trap '' HUP INT; worker ) > "$BK/log" 2>&1 < /dev/null &

echo
echo "Backup and log: $BK"
if [ "$TIMEOUT" -gt 0 ]; then
  echo "If this session drops: log in via $NEW within ${TIMEOUT}s and run: touch $OK_FILE"
fi
echo "Restarting network..."
while [ ! -f "$BK/applied" ]; do sleep 1; done
ip -o -4 addr show scope global | awk '{ print "  " $2, $4 }'
[ "$TIMEOUT" -eq 0 ] && exit 0
[ -n "$BATCH" ] && { echo "Confirm within ${TIMEOUT}s: touch $OK_FILE"; exit 0; }

echo "Auto-rollback in ${TIMEOUT}s. From another session (e.g. via $NEW) you can also confirm with: touch $OK_FILE"
while :; do
  ans=$(lc "$(ask "Keep new settings? [Y/n]: ")")
  [ -f "$BK/done" ] && { echo "Too late: $(cat "$BK/done")"; exit 1; }
  case $ans in
    ""|y|yes) touch "$OK_FILE"; break ;;
    n|no) touch "$BK/revert"; break ;;
  esac
done
while [ ! -f "$BK/done" ]; do sleep 1; done
cat "$BK/done"
