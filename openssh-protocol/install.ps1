# Registra openssh:// no Windows (usuario atual — sem admin).
# Abre o OpenSSH do Windows no CMD — nao o PuTTY (ssh://).
# Uso:
#   cd extras\openssh-protocol
#   powershell -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$vbs = Join-Path $here 'open-openssh.vbs'
$ps1 = Join-Path $here 'open-openssh.ps1'

if (-not (Test-Path $vbs)) {
  Write-Error "Arquivo nao encontrado: $vbs"
}
if (-not (Test-Path $ps1)) {
  Write-Error "Arquivo nao encontrado: $ps1"
}

$vbsEsc = $vbs.Replace('"', '\"')
$command = "wscript.exe //B //Nologo `"$vbsEsc`" `"%1`""

$base = 'HKCU:\Software\Classes\openssh'
New-Item -Path $base -Force | Out-Null
Set-ItemProperty -Path $base -Name '(Default)' -Value 'URL:OpenSSH Protocol'
New-ItemProperty -Path $base -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
New-Item -Path "$base\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$base\DefaultIcon" -Name '(Default)' -Value 'cmd.exe,0'
New-Item -Path "$base\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$base\shell\open\command" -Name '(Default)' -Value $command

Write-Host "Registrado: openssh://"
Write-Host ""
Write-Host "Comando: $command"
Write-Host ""
Write-Host "Teste no CMD:"
Write-Host "  ssh"
Write-Host "Teste no navegador:"
Write-Host "  openssh://open?h=10.0.0.1"
