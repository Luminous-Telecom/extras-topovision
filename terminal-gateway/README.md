# Gateway do terminal (SSH / Telnet)

O Grafana externo não precisa de rota até o CPE. O plugin reencaminha para a **mesma origem da
web do Zabbix**, só mudando a pasta:

| Pasta | Quem disca o equipamento |
|-------|--------------------------|
| `/console/local/` | gateway no **Zabbix server** (hosts sem proxy) |
| `/console/{slug}/` | gateway no **proxy** cujo nome no Zabbix vira esse slug |

O plugin lê `proxyid` / `proxy_hostid` no `host.get` e o nome no `proxy.get`. A pasta **não**
faz o Zabbix rotear SSH. Host só alcançável pelo proxy falha se o gateway daquela pasta não
estiver no ar.

Slug: nome do proxy em minúsculas, sem acento (`Proxy A` → `proxy-a`).

## Como instalar

O binário sai deste repositório (GitHub). **Não** precisa de Grafana na máquina — no proxy
remoto só o Zabbix server alcança o equipamento; o Grafana fala com a **web do Zabbix server**.

O **mesmo** comando no Zabbix server **e** em cada proxy:

```bash
curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
```

| Onde | O que o instalador faz |
|------|------------------------|
| **Zabbix server** (nginx da web) | binário, token, systemd, map + **uma** location `/console/{slug}/`, backends a partir da base Zabbix (`proxy.address` ou DNS do nome) |
| **Proxy** | binário, token, systemd, escuta `0.0.0.0:9100` — **não** mexe no nginx da web |

O token impresso é o mesmo em **Acesso remoto → Token do console remoto** (o mesmo valor no server e nos proxies, ou um por máquina se o nginx apontar só àquele gateway).

Libere a porta **9100 só do Zabbix server** em cada proxy. Sem `location` manual por proxy.

## Binário (na mão)

É o **mesmo** `gpx_topology_linux_amd64` do plugin. Sem o argumento `terminal` o binário vira
plugin, não gateway. Se o proxy não alcança o GitHub, baixe no server e copie:

```bash
# no Zabbix server (ou outra máquina com internet)
curl -fsSL -o /tmp/gpx_topology_linux_amd64 \
  https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/gpx_topology_linux_amd64
scp /tmp/gpx_topology_linux_amd64 root@proxy:/tmp/

# no proxy
curl -fsSL -o /tmp/tv-gw.sh \
  https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh
sudo TOPOVISION_BIN=/tmp/gpx_topology_linux_amd64 bash /tmp/tv-gw.sh
```

```bash
# teste na mão (Ctrl+C para sair)
export TOPOVISION_TERMINAL_TOKEN='um-token-longo'
/usr/local/bin/gpx_topology_linux_amd64 terminal
```

Escuta `127.0.0.1:9100`. `TOPOVISION_TERMINAL_LISTEN` só muda o endereço **depois** do
subcomando `terminal`. Sem token, qualquer processo nesta máquina abre sessão.
`/health` não exige token: `curl -sS http://127.0.0.1:9100/health`

## Nginx (vhost da web do Zabbix)

A pasta `/console/` mora na **web do Zabbix server** — é essa URL que o Grafana alcança.
Uma location cobre todos os proxies; o `map` escolhe o `:9100` (`local` ou o slug). Veja
`nginx.conf.example` e `console.map.conf`.

No painel: **Acesso remoto → Token do console remoto** = o mesmo `TOPOVISION_TERMINAL_TOKEN`.
