# change-ip

Замена IPv4 (и шлюза) в сетевых конфигах Linux с перезапуском сети и авто-откатом.

Репозиторий приватный, скачивание — по read-only токену:

```bash
read -rs T; curl -fsSL -H "Authorization: Bearer $T" -H "Accept: application/vnd.github.raw" https://api.github.com/repos/Skolskey/change-ip/contents/change-ip.sh | sh
```

`read -rs T` — вставь токен (не виден и не попадёт в history).

Поддерживает ifupdown, netplan, NetworkManager (keyfile и ifcfg), systemd-networkd, wicked, OpenRC.

После применения за 180 с зайди по новому IP и выполни `touch /root/.ip-change-ok`, иначе конфиги откатятся.
Без отката: `... | TIMEOUT=0 sh`. Бэкап и журнал — в `/root/ip-change-<дата>/`.
