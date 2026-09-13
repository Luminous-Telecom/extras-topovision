#!/usr/bin/env bash
# Instala o gateway SSH/Telnet no Zabbix server ou proxy: binário, token, systemd e
# (se achar a vhost) o location /console/ no nginx.
#
#   curl -fsSL https://raw.githubusercontent.com/Luminous-Telecom/extras-topovision/main/terminal-gateway/install.sh | sudo bash
#   sudo bash terminal-gateway/install.sh
set -euo pipefail

EXTRAS_REPO="${TOPOVISION_EXTRAS_REPO:-Luminous-Telecom/extras-topovision}"
PLUGIN_REPO="${TOPOVISION_REPO:-Luminous-Telecom/topology-panel}"
BIN_DIR=/usr/local/bin
ENV_FILE=/etc/topovision-terminal.env
UNIT_FILE=/etc/systemd/system/topovision-terminal.service
NGINX_SNIPPET=/etc/nginx/snippets/topovision-console.conf
NGINX_MAP=/etc/nginx/conf.d/00-topovision-console-map.conf
NGINX_BACKENDS=/etc/nginx/topovision-console.backends
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

github_curl() {
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if [[ -n "$token" ]]; then
    curl -fsSL -H "Authorization: Bearer ${token}" -H "Accept: application/vnd.github+json" "$@"
  else
    curl -fsSL "$@"
  fi
}

is_elf() {
  python3 -c "import sys; sys.exit(0 if open(sys.argv[1], 'rb').read(4) == b'\\x7fELF' else 1)" "$1" 2>/dev/null && return 0
  local hex
  hex="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
  [[ "$hex" == "7f454c46" ]]
}

is_zip() {
  local hex
  hex="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')"
  [[ "$hex" == "504b0304" || "$hex" == "504b0506" ]]
}

stage_bin() {
  local staged
  staged="$(mktemp)"
  cp "$1" "$staged"
  echo "$staged"
}

extract_zip_bin() {
  local zip="$1" out="$2" name="$3"
  mkdir -p "$out"
  if command -v unzip >/dev/null 2>&1; then
    unzip -qo "$zip" -d "$out"
  else
    python3 - "$zip" "$out" <<'PY'
import sys, zipfile
from pathlib import Path
Path(sys.argv[2]).mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sys.argv[1]) as z:
    z.extractall(sys.argv[2])
PY
  fi
  local found
  found="$(find "$out" -name "$name" -type f | head -n 1)"
  [[ -n "$found" ]] || die "O ZIP não tem $name."
  stage_bin "$found"
}

try_url() {
  local url="$1" dest="$2" name="$3" out="$4"
  echo "==> baixando $url" >&2
  github_curl "$url" -o "$dest" 2>/dev/null || return 1
  if is_elf "$dest"; then
    stage_bin "$dest"
    return 0
  fi
  if is_zip "$dest"; then
    extract_zip_bin "$dest" "$out" "$name"
    return 0
  fi
  return 1
}

download_release_bin() {
  command -v curl >/dev/null 2>&1 || die "Instale curl."
  local name="gpx_topology_$(arch_suffix)"
  local tmp dest url
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  dest="$tmp/dl"

  if [[ -n "${TOPOVISION_RELEASE_URL:-}" ]]; then
    try_url "$TOPOVISION_RELEASE_URL" "$dest" "$name" "$tmp/out" && return 0
    die "TOPOVISION_RELEASE_URL não devolveu $name (ELF ou ZIP do plugin)."
  fi

  for url in \
    "https://raw.githubusercontent.com/${EXTRAS_REPO}/main/terminal-gateway/${name}" \
    "https://github.com/${EXTRAS_REPO}/releases/latest/download/${name}"; do
    try_url "$url" "$dest" "$name" "$tmp/out" && return 0
  done

  url="$(github_curl "https://api.github.com/repos/${PLUGIN_REPO}/releases/latest" 2>/dev/null \
    | sed -n 's/.*"browser_download_url": *"\([^"]*topovision-panel-[^"]*\.zip\)".*/\1/p' \
    | head -n 1 || true)"
  if [[ -n "$url" ]]; then
    try_url "$url" "$dest" "$name" "$tmp/out" && return 0
  fi

  die "Não achei ${name}. Copie da pasta do plugin no Grafana e rode: sudo TOPOVISION_BIN=/caminho/${name} bash install.sh"
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

is_zabbix_proxy() {
  [[ -f /etc/zabbix/zabbix_proxy.conf ]] || command -v zabbix_proxy >/dev/null 2>&1
}

is_zabbix_web() {
  command -v nginx >/dev/null 2>&1 || return 1
  [[ -f /etc/zabbix/zabbix_server.conf || -f /etc/zabbix/web/zabbix.conf.php || -d /usr/share/zabbix ]] && return 0
  command -v zabbix_server >/dev/null 2>&1
}

ensure_token() {
  umask 077
  local listen="127.0.0.1:9100"
  if is_zabbix_proxy && ! is_zabbix_web; then
    listen="0.0.0.0:9100"
  fi
  if [[ -f "$ENV_FILE" ]] && grep -q '^TOPOVISION_TERMINAL_TOKEN=.\+' "$ENV_FILE"; then
    echo "==> token já existe em $ENV_FILE"
    if is_zabbix_proxy && ! is_zabbix_web; then
      if grep -q '^TOPOVISION_TERMINAL_LISTEN=' "$ENV_FILE"; then
        sed -i 's/^TOPOVISION_TERMINAL_LISTEN=.*/TOPOVISION_TERMINAL_LISTEN=0.0.0.0:9100/' "$ENV_FILE"
      else
        echo "TOPOVISION_TERMINAL_LISTEN=0.0.0.0:9100" >>"$ENV_FILE"
      fi
      echo "==> proxy: escuta em 0.0.0.0:9100 (o server precisa alcançar)."
    fi
    return 0
  fi
  local token
  token="$(openssl rand -hex 24 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(24))')"
  cat >"$ENV_FILE" <<EOF
TOPOVISION_TERMINAL_TOKEN=${token}
TOPOVISION_TERMINAL_LISTEN=${listen}
EOF
  chmod 600 "$ENV_FILE"
  echo "==> token novo em $ENV_FILE — cole o mesmo valor no painel (Acesso remoto)."
}

nginx_resolver() {
  local ns
  ns="$(awk '/^nameserver[ \t]+/ { print $2; exit }' /etc/resolv.conf 2>/dev/null || true)"
  if [[ -n "$ns" ]]; then
    echo "$ns"
    return 0
  fi
  echo "127.0.0.53 127.0.0.1"
}

write_nginx_map() {
  mkdir -p "$(dirname "$NGINX_MAP")"
  cat >"$NGINX_MAP" <<EOF
map \$uri \$topovision_console_slug {
    default "";
    "~^/console/([A-Za-z0-9._-]+)"  \$1;
}

map \$topovision_console_slug \$topovision_console_pass {
    default \$topovision_console_slug:9100;
    local   127.0.0.1:9100;
    include ${NGINX_BACKENDS};
}
EOF
  if [[ ! -f "$NGINX_BACKENDS" ]]; then
    cat >"$NGINX_BACKENDS" <<'EOF'
# slug  ip:9100;
EOF
  fi
  fill_backends_from_zabbix
}

fill_backends_from_zabbix() {
  python3 - "$NGINX_BACKENDS" <<'PY' || true
import os, pathlib, re, socket, subprocess, sys

dest = pathlib.Path(sys.argv[1])

def slugify(name: str) -> str:
    import unicodedata
    ascii_name = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
    slug = re.sub(r"[^a-z0-9._]+", "-", ascii_name.strip().lower())
    slug = re.sub(r"^[._-]+|[._-]+$", "", slug)[:64]
    slug = re.sub(r"[._-]+$", "", slug)
    return slug if re.match(r"^[a-z0-9][a-z0-9._-]{0,63}$", slug) else ""

def ipv4(raw: str) -> str:
    raw = (raw or "").strip().split("/")[0]
    if re.match(r"^\d{1,3}(\.\d{1,3}){3}$", raw):
        return raw
    return ""

def resolve(name: str) -> str:
    try:
        return ipv4(socket.getaddrinfo(name, None, socket.AF_INET)[0][4][0])
    except OSError:
        return ""

def parse_server_conf(path):
    out = {}
    if not path.is_file():
        return out
    for line in path.read_text(errors="replace").splitlines():
        line = line.split("#", 1)[0].strip()
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        out[key.strip()] = val.strip()
    return out

def parse_php_db(path):
    out = {}
    if not path.is_file():
        return out
    text = path.read_text(errors="replace")
    for key, dest in (
        ("SERVER", "host"),
        ("PORT", "port"),
        ("DATABASE", "name"),
        ("USER", "user"),
        ("PASSWORD", "password"),
    ):
        m = re.search(rf"\$DB\[\s*'{key}'\s*\]\s*=\s*'((?:\\'|[^'])*)'", text)
        if m:
            out[dest] = m.group(1).replace("\\'", "'")
    return out

def mysql_rows(cfg, sql):
    host = cfg.get("host") or cfg.get("DBHost") or "localhost"
    name = cfg.get("name") or cfg.get("DBName") or "zabbix"
    user = cfg.get("user") or cfg.get("DBUser") or "zabbix"
    password = cfg.get("password") or cfg.get("DBPassword") or ""
    port = cfg.get("port") or cfg.get("DBPort") or ""
    cmd = ["mysql", "-N", "-B", "-u", user, name, "-e", sql]
    if host and host not in ("localhost", "127.0.0.1"):
        cmd[3:3] = ["-h", host]
    if port:
        cmd[3:3] = ["-P", port]
    env = os.environ.copy()
    if password:
        env["MYSQL_PWD"] = password
    try:
        proc = subprocess.run(cmd, check=False, capture_output=True, text=True, env=env)
    except FileNotFoundError:
        return []
    if proc.returncode != 0:
        return []
    rows = []
    for line in proc.stdout.splitlines():
        parts = line.split("\t")
        if len(parts) >= 2:
            rows.append((parts[0], parts[1]))
        elif parts:
            rows.append((parts[0], ""))
    return rows

cfg = parse_server_conf(pathlib.Path("/etc/zabbix/zabbix_server.conf"))
php = parse_php_db(pathlib.Path("/etc/zabbix/web/zabbix.conf.php"))
if php:
    cfg = {
        "DBHost": php.get("host", cfg.get("DBHost", "localhost")),
        "DBPort": php.get("port", cfg.get("DBPort", "")),
        "DBName": php.get("name", cfg.get("DBName", "zabbix")),
        "DBUser": php.get("user", cfg.get("DBUser", "zabbix")),
        "DBPassword": php.get("password", cfg.get("DBPassword", "")),
        "host": php.get("host", ""),
        "port": php.get("port", ""),
        "name": php.get("name", ""),
        "user": php.get("user", ""),
        "password": php.get("password", ""),
    }

rows = mysql_rows(cfg, "SELECT name, address FROM proxy")
if not rows:
    rows = mysql_rows(
        cfg,
        "SELECT COALESCE(name, host), '' FROM hosts WHERE status IN (5, 6)",
    )

existing = dest.read_text() if dest.is_file() else ""
lines = [ln for ln in existing.splitlines() if ln.strip()]
have = {ln.split()[0] for ln in lines if ln.strip() and not ln.lstrip().startswith("#") and ln.split()}
added = 0
for name, address in rows:
    slug = slugify(name)
    if not slug or slug in have:
        continue
    ip = ipv4(address) or resolve(slug) or resolve(name.strip())
    if not ip:
        continue
    lines.append(f"{slug}  {ip}:9100;")
    have.add(slug)
    added += 1
if added:
    dest.write_text("\n".join(lines) + "\n")
    print(f"==> nginx: {added} proxy(s) em {dest}", file=sys.stderr)
PY
}

write_nginx_snippet() {
  mkdir -p "$(dirname "$NGINX_SNIPPET")"
  local resolvers
  resolvers="$(nginx_resolver)"
  cat >"$NGINX_SNIPPET" <<EOF
location ~ ^/console/([A-Za-z0-9._-]+)(/.*)\$ {
    resolver ${resolvers} ipv6=off valid=30s;
    set \$tv_backend \$topovision_console_pass;
    rewrite ^/console/[^/]+(/.*)\$ \$1 break;
    proxy_pass http://\$tv_backend;
    proxy_http_version 1.1;
    proxy_read_timeout 60s;
    proxy_set_header Authorization \$http_authorization;
}
EOF
}

zabbix_vhosts() {
  local f
  for f in \
    /etc/nginx/conf.d/zabbix.conf \
    /etc/zabbix/nginx.conf \
    /etc/nginx/sites-enabled/zabbix \
    /etc/nginx/sites-available/zabbix \
    /etc/nginx/conf.d/*.conf \
    /etc/nginx/sites-enabled/*; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == 00-topovision-console-map.conf ]] && continue
    if grep -Eq 'zabbix|php-fpm|fastcgi_pass' "$f"; then
      echo "$f"
    fi
  done | awk '!seen[$0]++'
}

patch_vhost() {
  python3 - "$1" "$NGINX_SNIPPET" <<'PY'
import pathlib, re, shutil, sys
path = pathlib.Path(sys.argv[1])
include = sys.argv[2]
text = path.read_text()
if "topovision-console" in text and f"include {include}" in text:
    raise SystemExit(0)
cleaned = re.sub(r"\n[ \t]*location /console/ \{.*?\n[ \t]*\}\n", "\n", text, count=1, flags=re.S)
if "topovision-console" not in cleaned:
    idx = cleaned.rstrip().rfind("}")
    if idx < 0:
        raise SystemExit(1)
    shutil.copy2(path, str(path) + ".bak-topovision")
    block = f"    # topovision-console\n    include {include};\n"
    path.write_text(cleaned[:idx] + block + cleaned[idx:])
    raise SystemExit(0)
if cleaned != text:
    shutil.copy2(path, str(path) + ".bak-topovision")
    path.write_text(cleaned)
PY
}

try_nginx() {
  if is_zabbix_proxy && ! is_zabbix_web; then
    echo "==> proxy: nginx da web fica no Zabbix server — rode o mesmo instalador lá."
    return 0
  fi
  command -v nginx >/dev/null 2>&1 || {
    echo "==> nginx não encontrado. No Zabbix server o instalador grava o map e a location."
    return 0
  }
  write_nginx_map
  write_nginx_snippet
  local f patched=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if patch_vhost "$f"; then
      if nginx -t >/dev/null 2>&1; then
        patched=1
        echo "==> nginx: console em $f"
        break
      fi
      if [[ -f "${f}.bak-topovision" ]]; then
        mv "${f}.bak-topovision" "$f"
      fi
      echo "==> nginx -t falhou em $f — include revertido."
    fi
  done < <(zabbix_vhosts)
  if nginx -t; then
    systemctl reload nginx
    if [[ "$patched" -eq 1 ]]; then
      return 0
    fi
  fi
  echo "==> não achei a vhost do Zabbix. No server {}, inclua:"
  echo "    include ${NGINX_SNIPPET};"
  echo "    e o map em http {}: ${NGINX_MAP}"
}

print_token() {
  local token listen
  token="$(sed -n 's/^TOPOVISION_TERMINAL_TOKEN=//p' "$ENV_FILE" | head -n 1)"
  listen="$(sed -n 's/^TOPOVISION_TERMINAL_LISTEN=//p' "$ENV_FILE" | head -n 1)"
  echo
  echo "Pronto. Gateway em ${listen:-127.0.0.1:9100}"
  echo "Token (Acesso remoto no painel): ${token}"
  echo "Saúde: curl -sS http://127.0.0.1:9100/health"
  if is_zabbix_proxy && ! is_zabbix_web; then
    echo "Este host é proxy. Rode o mesmo instalador no Zabbix server (nginx + map)."
  fi
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
