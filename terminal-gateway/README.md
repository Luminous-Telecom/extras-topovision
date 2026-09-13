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

## Instalador (Zabbix server ou proxy)

Um comando: baixa o binário desta pasta no GitHub (ou reusa o da pasta do plugin), gera o
token, sobe o systemd e tenta incluir `/console/` na vhost nginx do Zabbix.

```bash
curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
```

Ou, com este repositório / o binário já na máquina:

```bash
sudo bash terminal-gateway/install.sh
```

No fim o script imprime o token — o mesmo valor em **Acesso remoto → Token do console remoto**.
Repita no proxy se o host só for alcançável de lá.

## Binário (na mão)

É o **mesmo** `gpx_topology_linux_amd64` do plugin. Os arquivos linux desta pasta acompanham
a versão do painel. **Não** pare o Grafana: o instalador baixa daqui. Sem o argumento
`terminal` o binário vira plugin, não gateway. Se o download falhar:

```bash
# no Grafana
scp /var/lib/grafana/plugins/topovision-panel/gpx_topology_linux_amd64 root@proxy:/tmp/
# no proxy
sudo TOPOVISION_BIN=/tmp/gpx_topology_linux_amd64 bash install.sh
```

```bash
# no Grafana, ou no ZIP descompactado
install -m 0755 gpx_topology_linux_amd64 /usr/local/bin/gpx_topology_linux_amd64

# teste na mão (Ctrl+C para sair)
export TOPOVISION_TERMINAL_TOKEN='um-token-longo'
/usr/local/bin/gpx_topology_linux_amd64 terminal
```

Escuta `127.0.0.1:9100`. `TOPOVISION_TERMINAL_LISTEN` só muda o endereço **depois** do
subcomando `terminal`. Sem token, qualquer processo nesta máquina abre sessão.
`/health` não exige token: `curl -sS http://127.0.0.1:9100/health`

Para ficar no ar depois do reboot, nesta pasta:

```bash
cp topovision-terminal.env.example /etc/topovision-terminal.env
# edite o token
cp topovision-terminal.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now topovision-terminal
```

Repita no proxy (binário + unit + o mesmo token, ou um token por máquina se o nginx apontar
para aquele gateway).

## Nginx (vhost da web do Zabbix)

Veja `nginx.conf.example`. `proxy_pass` com barra no fim para o gateway receber
`/terminal/open`.

No painel: **Acesso remoto → Token do console remoto** = o mesmo `TOPOVISION_TERMINAL_TOKEN`.
A URL do console o painel monta sozinho (URL do frontend no Zabbix ou a do datasource, pasta
`/console`). O Grafana precisa alcançar essa web.
