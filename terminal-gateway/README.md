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

## Instalador

O binário sai deste repositório (GitHub). **Não** precisa de Grafana na máquina — no proxy
remoto só o Zabbix server alcança o equipamento; o Grafana fala com a **web do Zabbix server**.

```bash
curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
```

Ou, com este repositório / o binário já na máquina:

```bash
sudo bash terminal-gateway/install.sh
```

No fim o script imprime o token — o mesmo valor em **Acesso remoto → Token do console remoto**.

### No proxy (outra rede)

1. Rode o instalador **no proxy** (internet só para baixar o binário; se não tiver, copie do
   server — não do Grafana).
2. O serviço sobe em `127.0.0.1:9100`. O server **não** entra aí. Em
   `/etc/topovision-terminal.env`:

```bash
TOPOVISION_TERMINAL_LISTEN=0.0.0.0:9100
```

`systemctl restart topovision-terminal`. Libere a porta **9100 só do Zabbix server**.

3. No **nginx da web do Zabbix server** (não no proxy), um `location` com o slug do nome do
   proxy (`Proxy A` → `proxy-a`) apontando para o IP do proxy na rede do server. Veja
   `nginx.conf.example`.

4. O mesmo token no painel. Hosts desse proxy saem por `/console/{slug}/`.

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
Gateway no próprio server: `proxy_pass` para `127.0.0.1:9100`. Gateway no proxy: `proxy_pass`
para o IP:9100 dessa máquina. `proxy_pass` com barra no fim. Veja `nginx.conf.example`.

No painel: **Acesso remoto → Token do console remoto** = o mesmo `TOPOVISION_TERMINAL_TOKEN`.
