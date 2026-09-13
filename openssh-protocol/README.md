# Protocolo `openssh://` (Windows)

O menu **SSH** do mapa abre o **OpenSSH do Windows no CMD**, não o PuTTY.

`ssh://` no Windows costuma estar registrado no PuTTY. Por isso o painel usa `openssh://`.

| Menu no mapa | Protocolo | Comando |
|--------------|-----------|---------|
| **SSH** | `openssh://open?h=IP` | `ssh IP` |
| **SSH** com usuário | `openssh://open?h=IP&u=usuario` | `ssh -l usuario IP` |

A senha **não** vai na URL: o `ssh` pede no prompt do CMD.

## Como instalar

Uma vez por PC.

1. Clone ou baixe o ZIP do [extras-topovision](https://github.com/Luminous-Telecom/extras-topovision) e entre em `openssh-protocol`.
2. Confira o OpenSSH: no CMD, `ssh`. Se não existir: **Configurações → Aplicativos → Recursos opcionais → OpenSSH Client**.
3. No PowerShell desta pasta:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Deve aparecer `Registrado: openssh://`.

4. Teste na barra do Chrome/Edge: `openssh://open?h=10.0.0.1` — deve abrir um CMD com `ssh`.
5. No mapa: clique direito no host → **Ferramentas** → **SSH**.

## Remover

```powershell
Remove-Item -Recurse -Force HKCU:\Software\Classes\openssh
```
