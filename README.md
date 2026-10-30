# change-ip

Замена IPv4 (и шлюза) в сетевых конфигах Linux с перезапуском сети и авто-откатом.

```bash
curl -fsSL https://raw.githubusercontent.com/Skolskey/change-ip/main/change-ip.sh | sh
```

Поддерживает ifupdown, netplan, NetworkManager (keyfile и ifcfg), systemd-networkd, wicked, OpenRC.

После применения за 180 с зайди по новому IP и выполни `touch /root/.ip-change-ok`, иначе конфиги откатятся.
Без отката: `curl -fsSL ... | TIMEOUT=0 sh`. Бэкап и журнал — в `/root/ip-change-<дата>/`.
