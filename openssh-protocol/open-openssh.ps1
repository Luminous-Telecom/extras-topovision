# Abre o OpenSSH do Windows no CMD.
#   openssh://open?h=10.0.0.1
#   openssh://open?h=10.0.0.1&u=operador
# Legado:
#   openssh://10.0.0.1

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Uri
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$ipv4 = '^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$'
$userRe = '^[A-Za-z0-9._@+-]+$'

function Decode-Query([string]$Query) {
  $map = @{}
  if (-not $Query) { return $map }
  foreach ($pair in ($Query.TrimStart('?') -split '&')) {
    if (-not $pair) { continue }
    $kv = $pair -split '=', 2
    $k = [uri]::UnescapeDataString($kv[0])
    $v = if ($kv.Count -gt 1) { [uri]::UnescapeDataString($kv[1]) } else { '' }
    $map[$k] = $v
  }
  return $map
}

function Find-Ssh {
  $cmd = Get-Command ssh.exe -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source) { return $cmd.Source }
  $p = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe'
  if (Test-Path -LiteralPath $p) { return $p }
  return $null
}

function Write-LaunchError([string]$Text) {
  $log = Join-Path $here 'openssh-launcher-error.txt'
  @"
$Text
URI: $Uri
"@ | Set-Content -LiteralPath $log -Encoding UTF8
}

$uriTrim = $Uri.Trim()
$raw = $uriTrim -replace '^(?i)openssh://', '' -replace '^(?i)openssh:', ''

$query = ''
$pathPart = $raw
if ($raw.Contains('?')) {
  $qi = $raw.IndexOf('?')
  $pathPart = $raw.Substring(0, $qi).TrimEnd('/')
  $query = $raw.Substring($qi)
}

$q = Decode-Query $query
$hostPart = $null
$user = $null

if ($q.ContainsKey('h') -and $q['h']) {
  $hostPart = ($q['h']).Trim().TrimEnd('/')
  if ($q.ContainsKey('u') -and $q['u']) {
    $user = ($q['u']).Trim()
  }
}
elseif ($pathPart -and $pathPart -ne 'open') {
  $hostPart = $pathPart.Trim().TrimEnd('/')
}

if (-not $hostPart -or $hostPart -notmatch $ipv4) {
  Write-LaunchError 'IP invalido.'
  exit 1
}
if ($user -and $user -notmatch $userRe) {
  $user = $null
}

$ssh = Find-Ssh
if (-not $ssh) {
  Write-LaunchError 'ssh.exe nao encontrado. Instale o OpenSSH do Windows (Configuracoes → Aplicativos → Recursos opcionais).'
  exit 1
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $env:ComSpec
$psi.UseShellExecute = $true
if ($user) {
  $psi.Arguments = '/k "' + $ssh + '" -l ' + $user + ' ' + $hostPart
} else {
  $psi.Arguments = '/k "' + $ssh + '" ' + $hostPart
}
[void][System.Diagnostics.Process]::Start($psi)
