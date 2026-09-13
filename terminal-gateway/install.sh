#!/usr/bin/env bash
# Instala o gateway SSH/Telnet no Zabbix server ou proxy: binário, token, systemd e
# (se achar a vhost) o location /console/ no nginx.
#
#   curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
#   sudo bash terminal-gateway/install.sh
set -euo pipefail

REPO="${TOPOVISION_REPO:-Luminous-Telecom/topology-panel}"
BIN_DIR=/usr/local/bin
ENV_FILE=/etc/topovision-terminal.env
UNIT_FILE=/etc/systemd/system/topovision-terminal.service
NGINX_SNIPPET=/etc/nginx/snippets/topovision-console.conf
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)"

die() { echo "$*" >&2; exit 1; }

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Rode como root (sudo)."
  fi
}

arch_suffix() {
  case "$(uname -m)" in
    x86_64 | amd64) echo linux_amd64 ;;
    aarch64 | arm64) echo linux_arm64 ;;
    *) die "Arquitetura não suportada: $(uname -m)" ;;
  esac
}

find_local_bin() {
  local name="gpx_topology_$(arch_suffix)"
  local cand
  for cand in \
    "${TOPOVISION_BIN:-}" \
    "${HERE:+$HERE/$name}" \
    "/var/lib/grafana/plugins/topovision-panel/$name"; do
    if [[ -n "$cand" && -f "$cand" ]]; then
      echo "$cand"
      return 0
    fi
  done
  return 1
}

download_release_bin() {
  command -v curl >/dev/null 2>&1 || die "Instale curl."
  local name="gpx_topology_$(arch_suffix)"
  local tmp zip url
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  url="${TOPOVISION_RELEASE_URL:-}"
  if [[ -z "$url" ]]; then
    url="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
      | sed -n 's/.*"browser_download_url": *"\([^"]*topovision-panel-[^"]*\.zip\)".*/\1/p' \
      | head -n 1)"
  fi
  [[ -n "$url" ]] || die "Não achei o ZIP da release. Passe TOPOVISION_RELEASE_URL ou copie o binário."
  echo "==> baixando $url"
  curl -fsSL "$url" -o "$tmp/plugin.zip"
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$tmp/plugin.zip" -d "$tmp/out"
  else
    python3 - "$tmp/plugin.zip" "$tmp/out" <<'PY'
import sys, zipfile
from pathlib import Path
Path(sys.argv[2]).mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
  fi
  local found
  found="$(find "$tmp/out" -name "$name" -type f | head -n 1)"
  [[ -n "$found" ]] || die "O ZIP não tem $name."
  local staged
  staged="$(mktemp)"
  cp "$found" "$staged"
  echo "$staged"
}

write_unit() {
  cat >"$UNIT_FILE" <<EOF
[Unit]
Description=TopoVision terminal gateway (SSH/Telnet)
After=network.target

[Service]
Type=simple
EnvironmentFile=-${ENV_FILE}
ExecStart=${BIN_DIR}/gpx_topology_$(arch_suffix) terminal
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

ensure_token() {
  umask 077
  if [[ -f "$ENV_FILE" ]] && grep -q '^TOPOVISION_TERMINAL_TOKEN=.\+' "$ENV_FILE"; then
    echo "==> token já existe em $ENV_FILE"
    return 0
  fi
  local token
  token="$(openssl rand -hex 24 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(24))')"
  cat >"$ENV_FILE" <<EOF
TOPOVISION_TERMINAL_TOKEN=${token}
# TOPOVISION_TERMINAL_LISTEN=127.0.0.1:9100
EOF
  chmod 600 "$ENV_FILE"
  echo "==> token novo em $ENV_FILE — cole o mesmo valor no painel (Acesso remoto)."
}

write_nginx_snippet() {
  mkdir -p "$(dirname "$NGINX_SNIPPET")"
  cat >"$NGINX_SNIPPET" <<'EOF'
# Uma pasta: o gateway aceita /local/terminal e /{slug}/terminal nesta máquina.
location /console/ {
    proxy_pass http://127.0.0.1:9100/;
    proxy_http_version 1.1;
    proxy_read_timeout 60s;
    proxy_set_header Authorization $http_authorization;
}
EOF
}

try_nginx() {
  command -v nginx >/dev/null 2>&1 || {
    echo "==> nginx não encontrado — inclua $NGINX_SNIPPET na vhost da web do Zabbix."
    return 0
  }
  write_nginx_snippet
  local f
  for f in \
    /etc/nginx/conf.d/zabbix.conf \
    /etc/zabbix/nginx.conf \
    /etc/nginx/sites-enabled/zabbix \
    /etc/nginx/sites-available/zabbix; do
    [[ -f "$f" ]] || continue
    if grep -q topovision-console "$f"; then
      echo "==> nginx já inclui o console em $f"
      nginx -t && systemctl reload nginx
      return 0
    fi
    python3 - "$f" "$NGINX_SNIPPET" <<'PY' || continue
import pathlib, shutil, sys
path = pathlib.Path(sys.argv[1])
include = sys.argv[2]
text = path.read_text()
if "topovision-console" in text or "location /console/" in text:
    raise SystemExit(0)
idx = text.rstrip().rfind("}")
if idx < 0:
    raise SystemExit(1)
shutil.copy2(path, str(path) + ".bak-topovision")
block = f"    # topovision-console\n    include {include};\n"
path.write_text(text[:idx] + block + text[idx:])
PY
    if nginx -t; then
      systemctl reload nginx
      echo "==> nginx: include em $f (backup ${f}.bak-topovision)"
      return 0
    fi
    if [[ -f "${f}.bak-topovision" ]]; then
      mv "${f}.bak-topovision" "$f"
    fi
    echo "==> nginx -t falhou em $f — include revertido."
    return 0
  done
  echo "==> não achei a vhost do Zabbix. Inclua na server {}:"
  echo "    include ${NGINX_SNIPPET};"
}

print_token() {
  local token
  token="$(sed -n 's/^TOPOVISION_TERMINAL_TOKEN=//p' "$ENV_FILE" | head -n 1)"
  echo
  echo "Pronto. Gateway em 127.0.0.1:9100"
  echo "Token (Acesso remoto no painel): ${token}"
  echo "Saúde: curl -sS http://127.0.0.1:9100/health"
}

need_root
name="gpx_topology_$(arch_suffix)"
src="$(find_local_bin || true)"
if [[ -z "${src:-}" ]]; then
  src="$(download_release_bin)"
fi
echo "==> binário: $src"
install -m 0755 "$src" "${BIN_DIR}/${name}"
if [[ "$src" == /tmp/* ]]; then
  rm -f "$src"
fi
ensure_token
write_unit
systemctl daemon-reload
systemctl enable --now topovision-terminal
sleep 0.4
if ! curl -fsS http://127.0.0.1:9100/health >/dev/null; then
  die "O serviço subiu, mas /health não respondeu. journalctl -u topovision-terminal"
fi
try_nginx
print_token
