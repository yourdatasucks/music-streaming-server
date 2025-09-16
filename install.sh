#!/usr/bin/env bash
set -euo pipefail

# ---------- helpers ----------
die(){ echo "Error: $*" >&2; exit 1; }
yn(){ local cur="${1:-false}" ans; read -r ans || ans=""; if [[ -z "$ans" ]]; then echo "$cur"; return; fi; case "$ans" in [Yy]|[Yy][Ee][Ss]) echo "true";; [Nn]|[Nn][Oo]) echo "false";; *) echo "$cur";; esac; }
prompt(){ local q="$1" def="${2-}"; read -r -p "$q [${def}]: " a || true; echo "${a:-$def}"; }
prompt_hidden(){ local q="$1"; read -rs -p "$q " a || true; echo; echo "${a:-}"; }
randpass(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 18; echo; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"
REPO_FIXED="/opt/streamingserver"   # canonical path used by systemd unit

[[ $EUID -eq 0 ]] || die "Run as root (sudo)."

# ---------- auto-generate configs if missing ----------
echo "Setting up configuration files..."
for f in paths web tailscale autorip; do
  if [[ ! -f "$REPO_DIR/config/${f}.env" ]]; then
    echo "Creating config/${f}.env from example..."
    cp "$REPO_DIR/config/${f}.env.example" "$REPO_DIR/config/${f}.env"
  fi
done

# ---------- load configs as defaults ----------
set -a
. "$REPO_DIR/config/paths.env"
. "$REPO_DIR/config/web.env"
. "$REPO_DIR/config/tailscale.env"
. "$REPO_DIR/config/autorip.env"
set +a

echo "== ${REPO_NAME} installer =="
echo
echo "This will install a complete music streaming server with:"
echo "  • Navidrome (web-based music player)"
echo "  • File upload interface"
echo "  • Automatic SSL certificates"
echo "  • Optional: Tailscale (secure remote access)"
echo "  • Optional: Autorip (automatic CD ripping)"
echo

echo "=== Configuration Options ==="
echo -n "Enable upload Basic Auth? (protects /upload with username/password) [y/n, Enter=yes]: "
UPLOAD_BASIC_AUTH_ENABLE="$(yn "${UPLOAD_BASIC_AUTH_ENABLE:-true}")"
echo -n "Enable Tailscale? (secure VPN for remote access) [y/n, Enter=yes]: "
TAILSCALE_ENABLE="$(yn "${TAILSCALE_ENABLE:-true}")"
echo -n "Enable Autorip? (auto-rip CDs when inserted) [y/n, Enter=no]: "
AUTORIP_ENABLE="$(yn "${AUTORIP_ENABLE:-false}")"

echo
echo "=== DuckDNS Configuration ==="
echo "DuckDNS provides free dynamic DNS for your server."
echo "1. Go to https://www.duckdns.org and create a free account"
echo "2. Create a subdomain (e.g., 'mymusic')"
echo "3. Copy your token from the DuckDNS control panel"
echo

DUCKDNS_DOMAIN="${DUCKDNS_DOMAIN:-}"
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"

# Prompt for domain if not set
if [[ -z "$DUCKDNS_DOMAIN" ]]; then
  echo "Choose a subdomain name for your server (e.g., 'mymusic' for mymusic.duckdns.org)"
  DUCKDNS_DOMAIN="$(prompt 'Enter your DuckDNS subdomain' '')"
  [[ -n "$DUCKDNS_DOMAIN" ]] || die "DuckDNS subdomain is required"
fi

# Prompt for token if not set
if [[ -z "$DUCKDNS_TOKEN" ]]; then
  echo "Your server will be accessible at: https://${DUCKDNS_DOMAIN}.duckdns.org"
  DUCKDNS_TOKEN="$(prompt 'Enter your DuckDNS token' '')"
  [[ -n "$DUCKDNS_TOKEN" ]] || die "DuckDNS token is required for external access"
fi
if [[ "${UPLOAD_BASIC_AUTH_ENABLE}" == "true" ]]; then
  UPLOAD_USER="${UPLOAD_USER:-admin}"
  echo "(Upload auth) username is '${UPLOAD_USER}'. Change in config/web.env if needed."
fi
if [[ "${TAILSCALE_ENABLE}" == "true" && -z "${TAILSCALE_AUTHKEY:-}" ]]; then
  echo
  echo "=== Tailscale Setup ==="
  echo "Tailscale will be installed but needs manual approval on first run."
  echo "After installation, run: tailscale up"
  echo "Then visit the URL shown to approve this device."
  echo "This provides secure remote access to your streaming server."
fi

# ---------- persist toggles back to config ----------
sed -i "s|^UPLOAD_BASIC_AUTH_ENABLE=.*|UPLOAD_BASIC_AUTH_ENABLE=\"${UPLOAD_BASIC_AUTH_ENABLE}\"|" "$REPO_DIR/config/web.env"
sed -i "s|^DUCKDNS_DOMAIN=.*|DUCKDNS_DOMAIN=\"${DUCKDNS_DOMAIN}\"|" "$REPO_DIR/config/web.env"
sed -i "s|^DUCKDNS_TOKEN=.*|DUCKDNS_TOKEN=\"${DUCKDNS_TOKEN}\"|" "$REPO_DIR/config/web.env"
sed -i "s|^TAILSCALE_ENABLE=.*|TAILSCALE_ENABLE=\"${TAILSCALE_ENABLE}\"|" "$REPO_DIR/config/tailscale.env"
sed -i "s|^AUTORIP_ENABLE=.*|AUTORIP_ENABLE=\"${AUTORIP_ENABLE}\"|" "$REPO_DIR/config/autorip.env"

# ---------- base OS deps ----------
timedatectl set-timezone America/New_York || true
apt-get update
apt-get -y install git avahi-daemon curl gnupg lsb-release ufw
systemctl enable --now avahi-daemon
ufw allow OpenSSH || true; ufw allow 80/tcp || true; ufw allow 443/tcp || true; ufw --force enable || true

# ---------- Docker (official) ----------
apt-get remove -y docker docker-engine docker.io containerd runc || true
install -m 0755 -d /etc/apt/keyrings
curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# ---------- canonical repo path for unit files ----------
mkdir -p /opt
ln -sfn "$REPO_DIR" "$REPO_FIXED"

# ---------- make data dirs ----------
mkdir -p "$STACK_DIR" "$MUSIC_LIB" "$MUSIC_DATA" "$(dirname "$FILEBROWSER_DB")" "$CADDY_SNIPPETS"
chmod -R 755 "$DATA_ROOT"
chmod 775 "$MUSIC_LIB" || true

# ---------- UPLOAD_HASH auto-gen if needed ----------
if [[ "${UPLOAD_BASIC_AUTH_ENABLE}" == "true" ]]; then
  if [[ -z "${UPLOAD_HASH:-}" || "$UPLOAD_HASH" == '""' ]]; then
    echo "No UPLOAD_HASH found. Let's create one."
    echo "Enter upload password (blank = generate strong random):"
    pw="$(prompt_hidden 'Password:')"
    if [[ -z "$pw" ]]; then pw="$(randpass)"; echo "Generated password: $pw"; fi
    docker pull caddy:2 >/dev/null
    UPLOAD_HASH="$(printf '%s' "$pw" | docker run --rm -i caddy:2 caddy hash-password)"
    sed -i "s|^UPLOAD_HASH=.*|UPLOAD_HASH=\"${UPLOAD_HASH}\"|" "$REPO_DIR/config/web.env"
    export UPLOAD_HASH
  fi
  # Toggle snippet via symlink
  rm -f "${CADDY_SNIPPETS}/basicauth.caddy"
  if [[ "${UPLOAD_BASIC_AUTH_ENABLE}" == "true" ]]; then
    ln -s "${REPO_ROOT}/caddy/snippets/basicauth.enabled.caddy" "${CADDY_SNIPPETS}/basicauth.caddy"
  else
    ln -s "${REPO_ROOT}/caddy/snippets/basicauth.disabled.caddy" "${CADDY_SNIPPETS}/basicauth.caddy"
  fi
else
  rm -f "${CADDY_SNIPPETS}/basicauth.caddy"
  ln -s "${REPO_ROOT}/caddy/snippets/basicauth.disabled.caddy" "${CADDY_SNIPPETS}/basicauth.caddy"
fi

# ---------- export env for compose ----------
set -a
. "$REPO_DIR/config/paths.env"
. "$REPO_DIR/config/web.env"
set +a

# ---------- bring up the stack ----------
cd "${REPO_ROOT}/docker"
docker compose up -d

# ---------- Tailscale ----------
if [[ "${TAILSCALE_ENABLE}" == "true" ]]; then
  curl -fsSL https://tailscale.com/install.sh | bash
  install -D -m 0644 "${REPO_ROOT}/systemd/streamingserver-tailscale-up.service" "/etc/systemd/system/streamingserver-tailscale-up.service"
  systemctl daemon-reload
  systemctl enable --now streamingserver-tailscale-up.service
fi

# ---------- Autorip ----------
if [[ "${AUTORIP_ENABLE}" == "true" ]]; then
  apt-get -y install abcde cdparanoia flac lame opus-tools id3v2 eyeD3 cd-discid eject beets python3-pip imagemagick || true
  install -D -m 0755 "${REPO_ROOT}/autorip/cd-autorip.sh" /usr/local/bin/cd-autorip.sh
  install -D -m 0644 "${REPO_ROOT}/autorip/systemd/cd-autorip@.service" "/etc/systemd/system/cd-autorip@.service"
  install -D -m 0644 "${REPO_ROOT}/autorip/udev/99-cd-autorip.rules" "/etc/udev/rules.d/99-cd-autorip.rules"
  udevadm control --reload
  systemctl daemon-reload
fi

echo
echo "=========================================================="
echo "🎉 Installation Complete!"
echo "=========================================================="
echo
echo "Your streaming server is now running at:"
echo "  📤 Upload music: https://${DUCKDNS_DOMAIN}.duckdns.org/upload"
echo "  🎵 Listen to music: https://${DUCKDNS_DOMAIN}.duckdns.org/listen"
echo
if [[ "${UPLOAD_BASIC_AUTH_ENABLE}" == "true" ]]; then
  echo "Upload is protected with Basic Auth:"
  echo "  Username: ${UPLOAD_USER}"
  echo "  Password: (the one you set/generated during installation)"
  echo
fi
echo "Features enabled:"
echo "  • Tailscale: ${TAILSCALE_ENABLE}"
echo "  • Autorip:   ${AUTORIP_ENABLE}"
echo
echo "Next steps:"
echo "  1. Upload some music files to /upload"
echo "  2. Access your music library at /listen"
echo "  3. Install the Navidrome mobile app and connect to:"
echo "     https://${DUCKDNS_DOMAIN}.duckdns.org"
if [[ "${TAILSCALE_ENABLE}" == "true" ]]; then
  echo "  4. Run 'tailscale up' to enable secure remote access"
fi
echo
echo "Configuration files are in: /opt/streamingserver/config/"
echo "Music library is stored in: /srv/streamingserver/music/library/"
echo "=========================================================="
