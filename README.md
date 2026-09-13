# Extras do TopoVision

Instaladores e scripts que **não** entram no plugin Grafana. O painel está em
[Luminous-Telecom/TopoVision](https://github.com/Luminous-Telecom/TopoVision).

```bash
git clone https://github.com/Luminous-Telecom/extras-topovision.git
```

Ou **Code → Download ZIP** e extraia.

| Pasta | Para quê | Como instalar |
|-------|----------|---------------|
| [winbox-protocol](winbox-protocol/) | `winbox://` e `winboxnovo://` no Windows | [Instalar](#winbox) |
| [openssh-protocol](openssh-protocol/) | `openssh://` — OpenSSH no CMD, sem PuTTY | [Instalar](#ssh-no-cmd) |
| [terminal-gateway](terminal-gateway/) | Gateway SSH/Telnet no Zabbix server ou proxy | [Instalar](#gateway-do-terminal) |

## Winbox

No **Windows**, uma vez por PC (e de novo depois de atualizar a pasta):

1. Entre em `winbox-protocol`.
2. Copie para essa pasta:
   - `winbox64.exe` → menu **Winbox**
   - `WinBoxNovo.exe` → menu **Winbox Novo**
3. No PowerShell:

```powershell
cd winbox-protocol
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Deve aparecer `Registrado: winbox://` e `Registrado: winboxnovo://`.

Passo a passo: [winbox-protocol/README.md](winbox-protocol/README.md).

## SSH no CMD

No **Windows**, uma vez por PC. O OpenSSH Client precisa estar instalado (`ssh` no CMD).

```powershell
cd openssh-protocol
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Deve aparecer `Registrado: openssh://`.

Passo a passo: [openssh-protocol/README.md](openssh-protocol/README.md).

## Gateway do terminal

No **Zabbix server** e em cada **proxy** (Linux):

```bash
curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
```

Passo a passo: [terminal-gateway/README.md](terminal-gateway/README.md).
