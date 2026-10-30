#!/bin/sh
# Замена IPv4 в сетевых конфигах + перезапуск сети с авто-откатом.
# Запуск: curl -fsSL https://.../change-ip.sh | sh
# TIMEOUT=0 — без авто-отката.

TIMEOUT=${TIMEOUT:-180}
OK_FILE=/root/.ip-change-ok
PATHS="/etc/network/interfaces /etc/network/interfaces.d /etc/netplan
/etc/sysconfig/network-scripts /etc/sysconfig/network /etc/NetworkManager/system-connections
/etc/systemd/network /etc/conf.d/net /etc/hosts"

die() { echo "Ошибка: $*" >&2; exit 1; }
ask() { printf '%s' "$1" >/dev/tty; read -r v </dev/tty; printf '%s' "$v"; }
valid_ip() {
  echo "$1" | awk -F. 'NF==4 { for (i=1;i<=4;i++) if ($i !~ /^[0-9][0-9]?[0-9]?$/ || $i > 255) exit 1; exit 0 } { exit 1 }'
}
# IP целиком, чтобы 1.2.3.4 не цеплял 1.2.3.40 и 11.2.3.4
re() { printf '(^|[^0-9.])%s([^0-9.]|$)' "$(printf '%s' "$1" | sed 's/\./\\./g')"; }
# дважды: соседние вхождения ("ip,ip") делят разделитель
subst() { s="s/$(re "$1")/\\1$2\\2/g"; printf '%s;%s' "$s" "$s"; }

# снять IP с интерфейса (иначе ifupdown оставит старый адрес и маршрут)
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
  # и после netplan: у него может быть renderer NetworkManager с keyfile'ами вне /etc/netplan
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

worker() {
  sleep 2
  date; echo "Применяю $OLD -> $NEW"
  drop_ip "$OLD"; restart_net
  ip -o -4 addr show scope global
  [ "$TIMEOUT" -eq 0 ] && return
  i=0
  while [ "$i" -lt "$TIMEOUT" ]; do
    [ -f "$OK_FILE" ] && { rm -f "$OK_FILE"; echo "Подтверждено"; return; }
    sleep 1; i=$((i + 1))
  done
  echo "Нет подтверждения за ${TIMEOUT}с — откат"
  drop_ip "$NEW"
  tar -C / -xf "$BK/backup.tar"
  restart_net
  ip -o -4 addr show scope global
}

[ "$(id -u)" -eq 0 ] || die "нужен root"
[ -r /dev/tty ] || die "нужен интерактивный терминал"
command -v ip >/dev/null 2>&1 || die "нет утилиты ip (iproute2)"

echo "Текущие адреса:"; ip -o -4 addr show scope global | awk '{ print "  " $2, $4 }'
echo "Шлюз: $(ip -4 route show default | head -n1)"

OLD=$(ask "Какой IP заменить: "); valid_ip "$OLD" || die "неверный IP: $OLD"
NEW=$(ask "На какой IP: ");       valid_ip "$NEW" || die "неверный IP: $NEW"
[ "$OLD" != "$NEW" ] || die "IP совпадают"
OGW=$(ip -4 route show default | awk '{ print $3; exit }')
NGW=$(ask "Новый шлюз [Enter — не менять ${OGW}]: ")
[ -z "$NGW" ] || valid_ip "$NGW" || die "неверный шлюз: $NGW"

PAT=$(re "$OLD"); SED=$(subst "$OLD" "$NEW")
if [ -n "$NGW" ] && [ -n "$OGW" ] && [ "$NGW" != "$OGW" ]; then
  PAT="$PAT|$(re "$OGW")"; SED="$SED;$(subst "$OGW" "$NGW")"
fi

BK=/root/ip-change-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BK" || die "не создать $BK"
grep -rlE "$PAT" $PATHS 2>/dev/null | sort -u > "$BK/files"
[ -s "$BK/files" ] || die "$OLD не найден в сетевых конфигах"

echo; echo "Будут изменены:"
while IFS= read -r f; do echo "== $f"; grep -nE "$PAT" "$f"; done < "$BK/files"
others=$(grep -rlE "$(re "$OLD")" /etc 2>/dev/null | grep -vxF -f "$BK/files")
[ -n "$others" ] && printf '\nIP также есть здесь (НЕ меняю, проверь сервисы):\n%s\n' "$others"
command -v ping >/dev/null 2>&1 && ping -c1 -W1 "$NEW" >/dev/null 2>&1 && echo "ВНИМАНИЕ: $NEW уже отвечает на ping"
[ -d /etc/cloud ] && [ ! -f /etc/cloud/cloud-init.disabled ] &&
  echo "ВНИМАНИЕ: cloud-init может вернуть старую сеть при ребуте"

[ "$(ask "Применить? [y/N]: ")" = y ] || die "отменено"

tar -C / -cf "$BK/backup.tar" -T "$BK/files" 2>/dev/null || die "бэкап не удался"
while IFS= read -r f; do sed -i -E "$SED" "$f"; done < "$BK/files"
rm -f "$OK_FILE"

# ponytail: trap HUP держит воркер после обрыва SSH; при KillUserProcesses=yes нужен systemd-run
( trap '' HUP INT; worker ) > "$BK/log" 2>&1 < /dev/null &

echo
echo "Бэкап и журнал: $BK"
if [ "$TIMEOUT" -gt 0 ]; then
  echo "Сеть перезапускается. За ${TIMEOUT}с зайди по НОВОМУ IP ($NEW) и выполни:"
  echo "  touch $OK_FILE"
  echo "Иначе конфиги и сеть откатятся автоматически."
fi
