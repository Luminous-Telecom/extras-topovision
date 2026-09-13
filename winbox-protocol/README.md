# Protocolos `winbox://` e `winboxnovo://` (Windows)

| Menu no mapa | Protocolo | Executável |
|--------------|-----------|------------|
| **Winbox** | `winbox://open?h=IP&c=…` | `winbox64.exe` |
| **Winbox Novo** | `winboxnovo://open?h=IP&c=…` | `WinBoxNovo.exe` |

O launcher chama o exe com IP, usuário e senha:

```text
WinBoxNovo.exe "IP" "usuario" "senha"
```

O IP vai em `?h=` (não como host da URI), porque o Chrome transforma `winbox://IP?…` em `winbox://IP/?…` e a `/` aparecia no Connect To.

## Como instalar

Uma vez por PC. Rode de novo depois de atualizar esta pasta.

1. Clone ou baixe o ZIP do [extras-topovision](https://github.com/Luminous-Telecom/extras-topovision) e entre em `winbox-protocol`.
2. Copie para esta pasta:
   - `winbox64.exe` → menu **Winbox**
   - `WinBoxNovo.exe` → menu **Winbox Novo**
3. No PowerShell desta pasta:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Deve aparecer `Registrado: winbox://` e `Registrado: winboxnovo://`.

4. Teste na barra do Chrome/Edge: `winbox://10.0.0.1` — na primeira vez, permita e marque para lembrar.
5. No mapa: clique direito no host → **Ferramentas** → **Winbox** ou **Winbox Novo**.

## Conferir

Após clicar Winbox no mapa, abra `last-launch.txt` — `host=` deve ser só o IP, sem `/`, e `hasPassword=True` se cadastrou senha.

## Remover

```powershell
Remove-Item -Recurse -Force HKCU:\Software\Classes\winbox
Remove-Item -Recurse -Force HKCU:\Software\Classes\winboxnovo
```
