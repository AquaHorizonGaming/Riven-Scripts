#!/usr/bin/env bash
set -euo pipefail

############################################
# CONSTANTS
############################################
INSTALL_DIR="/opt/riven"
BACKEND_PATH="/mnt/riven/backend"
MOUNT_PATH="/mnt/riven/mount"

MEDIA_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.media.yml"
RIVEN_COMPOSE_URL="https://raw.githubusercontent.com/AquaHorizonGaming/distributables/main/ubuntu/docker-compose.yml"

DEFAULT_ORIGIN="http://localhost:3000"

############################################
# HELPERS
############################################
banner(){ echo -e "\n========================================\n $1\n========================================"; }
ok(){ echo "[✔] $1"; }
warn(){ echo "[!] $1"; }
fail(){ echo "[✖] $1"; exit 1; }

require_non_empty() {
  local prompt="$1" val
  while true; do
    read -rsp "$prompt: " val
    echo
    # Strip ALL newlines / carriage returns defensively
    val="$(printf '%s' "$val" | tr -d '\r\n')"
    [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    warn "Value required"
  done
}

require_url() {
  local prompt="$1" val
  while true; do
    read -rp "$prompt: " val
    [[ "$val" =~ ^https?:// ]] && { echo "$val"; return; }
    warn "Must include http:// or https://"
  done
}

############################################
# ROOT CHECK
############################################
[[ "$(id -u)" -eq 0 ]] || fail "Run with sudo"

############################################
# TIMEZONE
############################################
banner "Timezone"
TZ_DETECTED="$(timedatectl show --property=Timezone --value || echo UTC)"
read -rp "Timezone [$TZ_DETECTED]: " TZ_INPUT
TZ_SELECTED="${TZ_INPUT:-$TZ_DETECTED}"
timedatectl set-timezone "$TZ_SELECTED"
ok "Timezone set: $TZ_SELECTED"

############################################
# SYSTEM DEPS
############################################
banner "System Dependencies"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release openssl fuse3

############################################
# DOCKER
############################################
banner "Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi
ok "Docker ready"

############################################
# FILESYSTEM
############################################
banner "Filesystem"
mkdir -p "$BACKEND_PATH" "$MOUNT_PATH" "$INSTALL_DIR"
chown -R "${SUDO_USER:-1000}:${SUDO_USER:-1000}" /mnt/riven
ok "Filesystem ready"

############################################
# DOWNLOAD COMPOSE FILES FIRST
############################################
banner "Docker Compose Files"
cd "$INSTALL_DIR"
curl -fsSL "$MEDIA_COMPOSE_URL" -o docker-compose.media.yml
curl -fsSL "$RIVEN_COMPOSE_URL" -o docker-compose.yml
ok "Compose files downloaded"

############################################
# MEDIA SERVER SELECTION (REQUIRED)
############################################
banner "Media Server Selection (REQUIRED)"
echo "1) Jellyfin"
echo "2) Plex"
echo "3) Emby"
read -rp "Select ONE media server: " MEDIA_SEL

case "$MEDIA_SEL" in
  1) MEDIA_PROFILE="jellyfin"; MEDIA_PORT=8096 ;;
  2) MEDIA_PROFILE="plex";     MEDIA_PORT=32400 ;;
  3) MEDIA_PROFILE="emby";     MEDIA_PORT=8097 ;;
  *) fail "Media server REQUIRED" ;;
esac

############################################
# START MEDIA SERVER ONLY
############################################
banner "Starting Media Server"
docker compose -f docker-compose.media.yml --profile "$MEDIA_PROFILE" up -d
ok "Media server started"

SERVER_IP="$(hostname -I | awk '{print $1}')"

echo
echo "➡️  Open your media server in a browser:"
echo "👉  http://$SERVER_IP:$MEDIA_PORT"
echo
echo "• Complete setup"
echo "• Create admin user"
echo "• Generate API key / token"
echo
read -rp "Press ENTER once media server setup is complete..."

############################################
# MEDIA API KEY
############################################
banner "Media API Key"
MEDIA_API_KEY="$(require_non_empty "Enter media API key / token")"

############################################
# FRONTEND ORIGIN (MOVED HERE)
############################################
banner "Frontend Origin"
ORIGIN="$DEFAULT_ORIGIN"
read -rp "Using reverse proxy? (y/N): " USE_PROXY
[[ "${USE_PROXY,,}" == "y" ]] && ORIGIN="$(require_url "Public frontend URL")"
ok "ORIGIN=$ORIGIN"

############################################
# DOWNLOADER (REQUIRED)
############################################
banner "Downloader Selection (REQUIRED)"
echo "1) Real-Debrid"
echo "2) All-Debrid"
echo "3) Debrid-Link"
read -rp "Select ONE: " DL_SEL

RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=false
RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=false

RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY=""
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY=""
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY=""

case "$DL_SEL" in
  1)
    RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED=true
    RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY="$(require_non_empty "Real-Debrid API Key")"
    ;;
  2)
    RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED=true
    RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY="$(require_non_empty "All-Debrid API Key")"
    ;;
  3)
    RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED=true
    RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY="$(require_non_empty "Debrid-Link API Key")"
    ;;
  *)
    fail "Downloader REQUIRED"
    ;;
esac

############################################
# SCRAPER (REQUIRED)
############################################
banner "Scraper Selection (REQUIRED)"
echo "1) Torrentio"
echo "2) Prowlarr"
read -rp "Select ONE: " SCR_SEL

RIVEN_SCRAPING_TORRENTIO_ENABLED=false
RIVEN_SCRAPING_PROWLARR_ENABLED=false
RIVEN_SCRAPING_PROWLARR_URL=""
RIVEN_SCRAPING_PROWLARR_API_KEY=""

case "$SCR_SEL" in
  1)
    RIVEN_SCRAPING_TORRENTIO_ENABLED=true
    ;;
  2)
    RIVEN_SCRAPING_PROWLARR_ENABLED=true
    RIVEN_SCRAPING_PROWLARR_URL="$(require_url "Prowlarr URL")"
    RIVEN_SCRAPING_PROWLARR_API_KEY="$(require_non_empty "Prowlarr API Key")"
    ;;
  *)
    fail "Scraper REQUIRED"
    ;;
esac

############################################
# SECRETS
############################################
POSTGRES_PASSWORD="$(openssl rand -hex 24)"
BACKEND_API_KEY="$(openssl rand -hex 32)"
AUTH_SECRET="$(openssl rand -hex 32)"

############################################
# MEDIA UPDATER FLAGS
############################################
RIVEN_UPDATERS_JELLYFIN_ENABLED=false
RIVEN_UPDATERS_PLEX_ENABLED=false
RIVEN_UPDATERS_EMBY_ENABLED=false

RIVEN_UPDATERS_JELLYFIN_API_KEY=""
RIVEN_UPDATERS_PLEX_TOKEN=""
RIVEN_UPDATERS_EMBY_API_KEY=""

case "$MEDIA_PROFILE" in
  jellyfin)
    RIVEN_UPDATERS_JELLYFIN_ENABLED=true
    RIVEN_UPDATERS_JELLYFIN_API_KEY="$MEDIA_API_KEY"
    ;;
  plex)
    RIVEN_UPDATERS_PLEX_ENABLED=true
    RIVEN_UPDATERS_PLEX_TOKEN="$MEDIA_API_KEY"
    ;;
  emby)
    RIVEN_UPDATERS_EMBY_ENABLED=true
    RIVEN_UPDATERS_EMBY_API_KEY="$MEDIA_API_KEY"
    ;;
esac

############################################
# WRITE .env (ONCE, NO SED)
############################################
banner ".env Generation"

cat > .env <<EOF
TZ="$TZ_SELECTED"
ORIGIN="$ORIGIN"
MEDIA_PROFILE="$MEDIA_PROFILE"

POSTGRES_DB="riven"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="$POSTGRES_PASSWORD"

BACKEND_API_KEY="$BACKEND_API_KEY"
AUTH_SECRET="$AUTH_SECRET"

RIVEN_UPDATERS_LIBRARY_PATH="$BACKEND_PATH"
RIVEN_UPDATERS_UPDATER_INTERVAL="120"

RIVEN_UPDATERS_JELLYFIN_ENABLED="$RIVEN_UPDATERS_JELLYFIN_ENABLED"
RIVEN_UPDATERS_JELLYFIN_API_KEY="$RIVEN_UPDATERS_JELLYFIN_API_KEY"
RIVEN_UPDATERS_JELLYFIN_URL="http://jellyfin:8096"

RIVEN_UPDATERS_PLEX_ENABLED="$RIVEN_UPDATERS_PLEX_ENABLED"
RIVEN_UPDATERS_PLEX_TOKEN="$RIVEN_UPDATERS_PLEX_TOKEN"
RIVEN_UPDATERS_PLEX_URL="http://plex:32400"

RIVEN_UPDATERS_EMBY_ENABLED="$RIVEN_UPDATERS_EMBY_ENABLED"
RIVEN_UPDATERS_EMBY_API_KEY="$RIVEN_UPDATERS_EMBY_API_KEY"
RIVEN_UPDATERS_EMBY_URL="http://emby:8097"

RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED="$RIVEN_DOWNLOADERS_REAL_DEBRID_ENABLED"
RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY="$RIVEN_DOWNLOADERS_REAL_DEBRID_API_KEY"

RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED="$RIVEN_DOWNLOADERS_ALL_DEBRID_ENABLED"
RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY="$RIVEN_DOWNLOADERS_ALL_DEBRID_API_KEY"

RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED="$RIVEN_DOWNLOADERS_DEBRID_LINK_ENABLED"
RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY="$RIVEN_DOWNLOADERS_DEBRID_LINK_API_KEY"

RIVEN_SCRAPING_TORRENTIO_ENABLED="$RIVEN_SCRAPING_TORRENTIO_ENABLED"
RIVEN_SCRAPING_PROWLARR_ENABLED="$RIVEN_SCRAPING_PROWLARR_ENABLED"
RIVEN_SCRAPING_PROWLARR_URL="$RIVEN_SCRAPING_PROWLARR_URL"
RIVEN_SCRAPING_PROWLARR_API_KEY="$RIVEN_SCRAPING_PROWLARR_API_KEY"
EOF

############################################
# START RIVEN
############################################
banner "Starting Riven"
docker compose up -d
ok "Riven started"

banner "INSTALL COMPLETE"
